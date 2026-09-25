import {
  Any,
  EventSink,
  MethodCall,
  MethodCallHandler,
  MethodResult,
  PlatformView,
  PlatformViewFactory,
  PlatformViewRegistry,
  StandardMessageCodec,
  StreamHandler,
} from '@ohos/flutter_ohos'
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView'
import common from '@ohos.app.ability.common'
import webview from '@ohos.web.webview'

const VIEW_TYPE = 'mgread_ohos_arkweb'
const MAX_WAIT_MS = 120_000
const POLL_MS = 80
const MAX_RESPONSE_BYTES = 2 * 1024 * 1024
interface WebHeaderPayload {
  headerKey: string
  headerValue: string
}

interface HtmlPayload {
  html: string
}

interface FetchPayload {
  status: number
  url: string
  headers: Any
  body: Any
  __mgreadBrowserSessionError?: string
}

interface CoordinatesPayload {
  x: number
  y: number
  width: number
  height: number
}

interface LegacyResponse {
  version: number
  status: number
  finalUrl: string
  headers: Map<string, string>
  body: Any
}

/** Broadcasts session creation, visibility and disposal to the Flutter overlay. */
export class OhosArkWebSessionStreamHandler implements StreamHandler {
  private sink: EventSink | null = null

  onListen(args: Any, events: EventSink): void {
    this.sink = events
  }

  onCancel(args: Any): void {
    this.sink = null
  }

  emit(event: Any): void {
    this.sink?.success(event)
  }
}

/**
 * Native ArkWeb owner for browser.session.v1.
 *
 * The Node Runtime never receives a WebView object, cookie, profile or window
 * handle. Flutter only receives the bounded result maps defined by the
 * browser-session contract. The supported ArkWeb API exposes global normal
 * and incognito stores rather than named persistent profiles, so the Dart
 * capability probe deliberately reports profile isolation as unavailable.
 */
export default class OhosArkWebHost implements MethodCallHandler {
  private readonly sessions = new Map<string, OhosArkWebPlatformView>()
  private readonly pendingPluginIds = new Array<string>()
  private readonly cancelled = new Set<string>()
  private readonly activeJobs = new Map<string, OhosArkWebPlatformView>()
  private readonly stream = new OhosArkWebSessionStreamHandler()

  getStreamHandler(): OhosArkWebSessionStreamHandler {
    return this.stream
  }

  register(registry: PlatformViewRegistry): void {
    registry.registerViewFactory(VIEW_TYPE, new OhosArkWebPlatformViewFactory(this))
  }

  emitVisibility(pluginId: string, visible: boolean): void {
    const event: Map<string, Any> = new Map<string, Any>()
    event.set('type', 'session')
    event.set('action', 'visibility')
    event.set('pluginId', pluginId)
    event.set('visible', visible)
    this.stream.emit(event)
  }

  emitRemoved(pluginId: string): void {
    if (pluginId.length === 0) return
    const event: Map<string, Any> = new Map<string, Any>()
    event.set('type', 'session')
    event.set('action', 'remove')
    event.set('pluginId', pluginId)
    this.stream.emit(event)
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'request':
        this.request(call.args as Map<string, Any> | null)
          .then((response: Any): void => result.success(response))
          .catch((error: Object): void => result.error(this.errorCode(error), this.errorMessage(error), null))
        break
      case 'cancel':
        this.cancel(call.args as Map<string, Any> | null)
        result.success(null)
        break
      case 'configureProxy':
        this.configureProxy(call.args as Map<string, Any> | null, result)
        break
      case 'dispose':
        this.dispose()
        result.success(null)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private configureProxy(args: Map<string, Any> | null, result: MethodResult): void {
    const raw: Any = args?.get('proxyUri')
    if (raw !== undefined && raw !== null && typeof raw !== 'string') {
      result.error('invalid_argument', 'proxyUri must be a URI string or null.', null)
      return
    }
    try {
      if (raw === undefined || raw === null || (raw as string).length === 0) {
        webview.ProxyController.removeProxyOverride((): void => result.success(null))
        return
      }
      const proxy = raw as string
      const separator = proxy.indexOf('://')
      if (separator <= 0 || separator + 3 >= proxy.length) {
        result.error('invalid_argument', 'proxyUri must include a scheme and endpoint.', null)
        return
      }
      const inputScheme = proxy.substring(0, separator).toLowerCase()
      const scheme = inputScheme === 'socks5' ? 'socks' : inputScheme
      if (scheme !== 'http' && scheme !== 'https' && scheme !== 'socks') {
        result.error('invalid_argument', 'OHOS ArkWeb supports HTTP, HTTPS, and SOCKS proxies.', null)
        return
      }
      const config = new webview.ProxyConfig()
      config.insertProxyRule(`${scheme}://${proxy.substring(separator + 3)}`)
      config.insertBypassRule('localhost')
      config.insertBypassRule('127.0.0.1')
      config.insertBypassRule('::1')
      webview.ProxyController.applyProxyOverride(config, (): void => result.success(null))
    } catch (error) {
      result.error('proxy_failed', this.errorMessage(error), null)
    }
  }

  attach(pluginId: string, page: OhosArkWebPlatformView): void {
    if (pluginId.length === 0) return
    this.sessions.set(pluginId, page)
    const pendingIndex = this.pendingPluginIds.indexOf(pluginId)
    if (pendingIndex >= 0) this.pendingPluginIds.splice(pendingIndex, 1)
  }

  detach(pluginId: string, page: OhosArkWebPlatformView): void {
    if (this.sessions.get(pluginId) !== page) return
    this.sessions.delete(pluginId)
  }

  async request(args: Map<string, Any> | null): Promise<Any> {
    const envelope: Map<string, Any> = args ?? new Map<string, Any>()
    const nested: Any = envelope.get('raw')
    const raw: Map<string, Any> = nested instanceof Map ? nested as Map<string, Any> : envelope
    if (!raw.has('jobId')) raw.set('jobId', envelope.get('jobId'))
    if (!raw.has('deadlineUnixMs')) raw.set('deadlineUnixMs', envelope.get('deadlineUnixMs'))
    const pluginId = this.stringValue(raw, 'pluginId')
    const pluginName = this.stringValue(raw, 'pluginName')
    const jobId = this.stringValue(raw, 'jobId')
    const operation = this.stringValue(raw, 'operation')
    if (pluginId.length === 0 || (operation.startsWith('page.') && pluginName.length === 0)) {
      throw new OhosArkWebError('plugin_execution_failed')
    }
    const deadline = this.deadline(raw)
    const page = await this.pageFor(pluginId, pluginName, jobId, deadline)
    if (operation === 'debug') {
      await page.setVisible(true)
      return {version: 1, accepted: true, action: this.stringValue(raw, 'action')}
    }
    if (jobId.length > 0) this.activeJobs.set(jobId, page)
    try {
      let response: Any
      if (operation.startsWith('page.')) response = await this.pageOperation(page, raw, jobId)
      else if (operation === 'interaction') response = await this.interaction(page, raw, jobId)
      else response = await this.legacyRequest(page, raw, jobId)
      return response
    } catch (error) {
      if (error instanceof OhosArkWebError) throw error
      throw new OhosArkWebError('plugin_execution_failed')
    } finally {
      if (jobId.length > 0 && this.activeJobs.get(jobId) === page) {
        this.activeJobs.delete(jobId)
      }
    }
  }

  async requestJson(payload: string, browserRequestId: string = ''): Promise<Any> {
    const decoded: Any = JSON.parse(payload)
    const value: Any = this.fromJsonValue(decoded)
    if (!(value instanceof Map)) throw new OhosArkWebError('plugin_execution_failed')
    const request: Map<string, Any> = value as Map<string, Any>
    if (this.stringValue(request, 'operation') === 'cancel') {
      this.cancel(request)
      throw new OhosArkWebError('cancelled')
    }
    if (browserRequestId.length > 0 && !request.has('jobId')) request.set('jobId', browserRequestId)
    return await this.request(request)
  }

  private async pageFor(pluginId: string, pluginName: string, jobId: string, deadline: number): Promise<OhosArkWebPlatformView> {
    const existing = this.sessions.get(pluginId)
    if (existing !== undefined) return existing
    if (!this.pendingPluginIds.includes(pluginId)) {
      this.pendingPluginIds.push(pluginId)
      const event: Map<string, Any> = new Map<string, Any>()
      event.set('type', 'session')
      event.set('action', 'upsert')
      event.set('pluginId', pluginId)
      event.set('pluginName', pluginName)
      event.set('visible', false)
      this.stream.emit(event)
    }
    // Waiting for Flutter to mount the platform view is part of the browser
    // request. Polling keeps cancellation and the caller deadline visible;
    // the former fixed five-second timer could outlive a canceled Runtime job.
    while (Date.now() < deadline) {
      this.ensureNotCancelled(jobId, deadline)
      const page = this.sessions.get(pluginId)
      if (page !== undefined) return page
      await this.delay(POLL_MS)
    }
    throw new OhosArkWebError('timeout')
  }

  resolvePluginId(args: Any): string {
    if (args instanceof Map) {
      const value: Any = args.get('pluginId')
      if (typeof value === 'string' && value.length > 0) {
        return value
      }
    }
    return ''
  }

  private async pageOperation(page: OhosArkWebPlatformView, raw: Map<string, Any>, jobId: string): Promise<Any> {
    const operation = this.stringValue(raw, 'operation')
    const deadline = this.deadline(raw)
    if (operation === 'page.open') {
      await page.setVisible(this.booleanValue(raw, 'visible'))
      return {}
    }
    if (operation === 'page.show') {
      await page.setVisible(true)
      return {}
    }
    if (operation === 'page.hide') {
      await page.setVisible(false)
      return {}
    }
    if (operation === 'page.close') {
      await page.close()
      return {}
    }
    if (operation === 'page.navigate') {
      await page.load(this.stringValue(raw, 'url'), this.headers(raw.get('headers')))
      await this.ensureNotCancelled(jobId, deadline)
      await this.waitReady(page, jobId, deadline, this.stringValue(raw, 'url'))
      return {}
    }
    if (operation === 'page.evaluate') {
      await this.ensureNotCancelled(jobId, deadline)
      return await page.evaluate(this.stringValue(raw, 'code'))
    }
    if (operation === 'page.html') {
      await this.ensureNotCancelled(jobId, deadline)
      return await page.html()
    }
    if (operation === 'page.fetch') {
      return await this.fetch(page, raw, jobId, deadline)
    }
    if (operation === 'page.click') {
      await this.ensureVisible(page)
      await this.ensureNotCancelled(jobId, deadline)
      return await page.click(this.numberValue(raw, 'x'), this.numberValue(raw, 'y'))
    }
    if (operation === 'page.input') {
      await this.ensureVisible(page)
      await this.ensureNotCancelled(jobId, deadline)
      return await page.input(this.stringValue(raw, 'text'))
    }
    if (operation === 'page.key') {
      await this.ensureVisible(page)
      await this.ensureNotCancelled(jobId, deadline)
      return await page.key(this.stringValue(raw, 'key'), this.stringList(raw.get('modifiers')))
    }
    if (operation === 'page.waitText') {
      return await this.waitText(page, raw, jobId, deadline)
    }
    if (operation === 'page.getUrl') {
      await this.ensureNotCancelled(jobId, deadline)
      return {url: page.url()}
    }
    throw new OhosArkWebError('unsupported')
  }

  private async legacyRequest(page: OhosArkWebPlatformView, raw: Map<string, Any>, jobId: string): Promise<Any> {
    const transport = this.stringValue(raw, 'transport')
    const deadline = this.deadline(raw)
    const presentation = this.stringValue(raw, 'presentation')
    await page.setVisible(presentation === 'visible')
    // ArkWeb fetch uses the same page Cookie jar, redirect policy and user
    // agent as the visible WebView.  It is the OHOS equivalent of Android's
    // host HTTP transport; do not navigate the page for this branch.
    if (transport === 'http') return await this.fetch(page, raw, jobId, deadline)
    const url = this.stringValue(raw, 'url')
    await page.load(url, this.headers(raw.get('headers')))
    await this.ensureNotCancelled(jobId, deadline)
    await this.waitReady(page, jobId, deadline, url)
    if (transport === 'html') {
      const body: HtmlPayload = await page.html() as HtmlPayload
      const responseHeaders = new Map<string, string>()
      responseHeaders.set('content-type', 'text/html')
      const response: LegacyResponse = {version: 1, status: 200, finalUrl: page.url(), headers: responseHeaders, body: body.html}
      return response
    }
    return await this.fetch(page, raw, jobId, deadline)
  }

  private async interaction(page: OhosArkWebPlatformView, raw: Map<string, Any>, jobId: string): Promise<Any> {
    const deadline = this.deadline(raw)
    await this.ensureNotCancelled(jobId, deadline)
    if (this.stringValue(raw, 'presentation') !== 'visible') throw new OhosArkWebError('interaction_required')
    const action = this.stringValue(raw, 'action')
    const selector = this.stringValue(raw, 'selector')
    if (action === 'coordinates') {
      const value: CoordinatesPayload | null = await this.decode(await page.script(`(() => { const e=document.querySelector(${JSON.stringify(selector)}); if(!e)return null; const r=e.getBoundingClientRect(); return JSON.stringify({x:r.x+r.width/2,y:r.y+r.height/2,width:r.width,height:r.height}); })()`)) as CoordinatesPayload | null
      if (value === null) throw new OhosArkWebError('interaction_required')
       const coordinates: CoordinatesPayload = value as CoordinatesPayload
       return {version: 1, accepted: true, action, x: coordinates.x, y: coordinates.y, width: coordinates.width, height: coordinates.height}
    }
    if (action === 'native-input') {
      await page.script(`(() => { const e=document.querySelector(${JSON.stringify(selector)}); if(!e)return false; e.focus(); e.value=${JSON.stringify(this.stringValue(raw, 'text'))}; e.dispatchEvent(new Event('input',{bubbles:true})); return true; })()`)
      return {version: 1, accepted: true, action}
    }
    if (action === 'control-click') {
      await page.script(`(() => { const e=document.querySelector(${JSON.stringify(selector)}); if(!e)return false; e.click(); return true; })()`)
      return {version: 1, accepted: true, action}
    }
    throw new OhosArkWebError('unsupported')
  }

  private async fetch(page: OhosArkWebPlatformView, raw: Map<string, Any>, jobId: string, deadline: number): Promise<Any> {
    await this.ensureNotCancelled(jobId, deadline)
    const url = this.stringValue(raw, 'url')
    const method = this.stringValue(raw, 'method') || 'GET'
    const headers = this.fetchHeaders(raw.get('headers'))
    const body: Any = raw.get('body')
    const responseType = this.stringValue(raw, 'responseType') || 'text'
    const maxResponseBytes = this.numberValue(raw, 'maxResponseBytes') || MAX_RESPONSE_BYTES
    const script = `(()=>{const c=new AbortController();const t=setTimeout(()=>c.abort(),${Math.max(1, deadline - Date.now())});return fetch(${JSON.stringify(url)},{method:${JSON.stringify(method)},headers:${JSON.stringify(headers)},body:${body === null || body === undefined ? 'null' : JSON.stringify(body)},credentials:'include',redirect:'follow',signal:c.signal}).then(async r=>{const source=new URL(${JSON.stringify(url)});const finalUrl=new URL(r.url);if(source.origin!==finalUrl.origin)throw new Error('cross_origin');const bytes=await r.arrayBuffer();if(bytes.byteLength>${maxResponseBytes})throw new Error('overloaded');const h={};for(const k of ['cache-control','content-type','etag','expires','last-modified']){const v=r.headers.get(k);if(v!==null)h[k]=v.slice(0,1024)};const text=new TextDecoder().decode(bytes);let b;${responseType === 'json' ? "b=JSON.parse(text)" : responseType === 'base64' ? "b=btoa(Array.from(new Uint8Array(bytes),x=>String.fromCharCode(x)).join(''))" : "b=text"};return JSON.stringify({status:r.status,url:r.url,headers:h,body:b})}).catch(error=>JSON.stringify({__mgreadBrowserSessionError:error?.message==='overloaded'?'overloaded':'plugin_execution_failed'})).finally(()=>clearTimeout(t))})()`
     const payload: FetchPayload | null = await this.decode(await page.script(script)) as FetchPayload | null
     await this.ensureNotCancelled(jobId, deadline)
     if (payload !== null && payload.__mgreadBrowserSessionError !== undefined) throw new OhosArkWebError(payload.__mgreadBrowserSessionError)
     if (payload === null) throw new OhosArkWebError('plugin_execution_failed')
     return responseType === 'text' ? {version: 1, status: payload.status, finalUrl: payload.url, headers: payload.headers, body: payload.body} : payload
  }

  private async waitText(page: OhosArkWebPlatformView, raw: Map<string, Any>, jobId: string, deadline: number): Promise<Any> {
    const text = this.stringValue(raw, 'text')
    const scope = this.stringValue(raw, 'scope') || 'text'
    while (true) {
      await this.ensureNotCancelled(jobId, deadline)
      const value = await page.script(scope === 'html' ? 'document.documentElement?.outerHTML??""' : 'document.documentElement?.innerText??""')
      if (value.includes(text)) return {url: page.url()}
      await this.delay(POLL_MS)
    }
  }

  private async waitReady(page: OhosArkWebPlatformView, jobId: string, deadline: number, targetUrl: string): Promise<void> {
    while (true) {
      await this.ensureNotCancelled(jobId, deadline)
      try {
        const state = (await page.script('document.readyState')).replace(/"/g, '')
        if (state === 'interactive' || state === 'complete') {
          if (targetUrl === 'about:blank') return
          const body = (await page.script('document.body?.innerHTML??""')).replace(/"/g, '')
          if (body.trim().length > 0) return
        }
      } catch (_) {
        // The first controller call can race Web initialization; keep polling.
      }
      await this.delay(POLL_MS)
    }
  }

  private async ensureVisible(page: OhosArkWebPlatformView): Promise<void> {
    if (!page.visible) throw new OhosArkWebError('interaction_required')
  }

  private async ensureNotCancelled(jobId: string, deadline: number): Promise<void> {
    if (jobId.length > 0 && this.cancelled.has(jobId)) {
      this.cancelled.delete(jobId)
      throw new OhosArkWebError('cancelled')
    }
    if (Date.now() >= deadline) throw new OhosArkWebError('timeout')
  }

  private cancel(args: Map<string, Any> | null): void {
    const jobId = this.stringValue(args ?? new Map<string, Any>(), 'jobId')
    if (jobId.length === 0) return
    this.cancelled.add(jobId)
    // stop() is the only ArkWeb primitive that releases an in-flight
    // load/script/fetch promptly on the supported API surface.  The job set
    // remains authoritative so a late Promise cannot publish a result.
    this.activeJobs.get(jobId)?.stop()
  }

  private fromJsonValue(value: Any): Any {
    if (Array.isArray(value)) return value.map((entry: Any): Any => this.fromJsonValue(entry))
    if (value !== null && typeof value === 'object') {
      const map: Map<string, Any> = new Map<string, Any>()
      Object.keys(value as Record<string, Any>).forEach((key: string): void => {
        map.set(key, this.fromJsonValue((value as Record<string, Any>)[key]))
      })
      return map
    }
    return value
  }

  dispose(): void {
    this.cancelled.clear()
    this.activeJobs.clear()
    this.sessions.forEach((page: OhosArkWebPlatformView, pluginId: string): void => {
      page.close()
    })
    this.sessions.clear()
  }

  private deadline(raw: Map<string, Any>): number {
    const value: Any = raw.get('deadlineUnixMs')
    const supplied = typeof value === 'number' ? value : Number(value ?? 0)
    const timeoutValue: Any = raw.get('timeoutMs')
    const timeout = typeof timeoutValue === 'number' && Number.isFinite(timeoutValue) && timeoutValue > 0
      ? timeoutValue
      : 30_000
    const now = Date.now()
    const parsed = Number.isFinite(supplied) && supplied > now ? supplied : now + timeout
    if (!Number.isFinite(parsed) || parsed <= now) throw new OhosArkWebError('timeout')
    return Math.min(parsed, now + MAX_WAIT_MS)
  }

  private headers(value: Any): Array<webview.WebHeader> {
    const result: Array<webview.WebHeader> = []
    if (!(value instanceof Map)) return result
    value.forEach((header: Any, name: string): void => {
      if (typeof name === 'string' && typeof header === 'string') {
        const payload: WebHeaderPayload = {headerKey: name, headerValue: header}
        result.push(payload as webview.WebHeader)
      }
    })
    return result
  }

  private fetchHeaders(value: Any): Record<string, string> {
    const result: Record<string, string> = {}
    if (!(value instanceof Map)) return result
    value.forEach((header: Any, name: string): void => {
      if (typeof name === 'string' && typeof header === 'string') result[name] = header
    })
    return result
  }

  private stringList(value: Any): Array<string> {
    return Array.isArray(value) ? value.filter((item: Any): boolean => typeof item === 'string') as Array<string> : []
  }

  private stringValue(args: Map<string, Any>, key: string): string {
     const value: Any = args.get(key)
    return typeof value === 'string' ? value : ''
  }

  private booleanValue(args: Map<string, Any>, key: string): boolean {
    return args.get(key) === true
  }

  private numberValue(args: Map<string, Any>, key: string): number {
     const value: Any = args.get(key)
    return typeof value === 'number' && Number.isFinite(value) ? value : 0
  }

  private async decode(value: string): Promise<Any | null> {
    try {
      let decoded: Any = JSON.parse(value)
      if (typeof decoded === 'string') {
        const nested = decoded.trim()
        if (nested.startsWith('{') || nested.startsWith('[')) decoded = JSON.parse(nested)
      }
      return decoded !== null && typeof decoded === 'object' && !Array.isArray(decoded) ? decoded : null
    } catch (_) {
      return null
    }
  }

  private async delay(milliseconds: number): Promise<void> {
     await new Promise<void>((resolve): void => {
       setTimeout((): void => resolve(), milliseconds)
     })
  }

  private errorCode(error: Object): string {
     return error instanceof OhosArkWebError ? error.code : 'plugin_execution_failed'
  }

  private errorMessage(error: Object): string {
     return error instanceof Error ? error.message : String(error)
  }
}

class OhosArkWebError extends Error {
  readonly code: string

  constructor(code: string) {
    super(code)
    this.code = code
  }
}

class OhosArkWebPlatformViewFactory extends PlatformViewFactory {
  private readonly host: OhosArkWebHost

  constructor(host: OhosArkWebHost) {
     super(StandardMessageCodec.INSTANCE)
     this.host = host
  }

  create(context: common.Context, viewId: number, args: Any): PlatformView {
    const pluginId = this.host.resolvePluginId(args)
    return new OhosArkWebPlatformView(pluginId, this.host)
  }
}

export class OhosArkWebPlatformView extends PlatformView {
  readonly controller: webview.WebviewController
  visible = false
  private disposed = false
  pluginId: string
  private readonly host: OhosArkWebHost
  private ready = false

  constructor(pluginId: string, host: OhosArkWebHost) {
    super()
    this.controller = new webview.WebviewController()
    this.pluginId = pluginId
    this.host = host
  }

  bindPluginId(pluginId: string): void {
    if (this.pluginId.length > 0 || pluginId.length === 0) return
    this.pluginId = pluginId
    if (this.ready) this.host.attach(pluginId, this)
  }

  markReady(): void {
    if (this.ready) return
    this.ready = true
    this.host.attach(this.pluginId, this)
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(buildOhosArkWeb)
  }

  async load(url: string, headers: Array<webview.WebHeader>): Promise<void> {
    if (this.disposed) throw new OhosArkWebError('unsupported')
    let lastError: Object | null = null
    for (let attempt = 0; attempt < 75; attempt++) {
      try {
        this.controller.loadUrl(url, headers)
        if (url === 'about:blank') return
        for (let waitAttempt = 0; waitAttempt < 75; waitAttempt++) {
          try {
            const current = this.controller.getUrl()
            if (current.length > 0 && current !== 'about:blank') {
              return
            }
          } catch (_) {
            // The controller can briefly lose its page while Web is attaching.
          }
          await new Promise<void>((resolve): void => {
            setTimeout((): void => resolve(), POLL_MS)
          })
        }
        throw new OhosArkWebError('plugin_execution_failed')
      } catch (error) {
        if (error instanceof OhosArkWebError) throw error
        lastError = error as Object
        await new Promise<void>((resolve): void => {
          setTimeout((): void => resolve(), POLL_MS)
        })
      }
    }
    throw new OhosArkWebError('plugin_execution_failed')
  }

  async script(source: string): Promise<string> {
    if (this.disposed) throw new OhosArkWebError('unsupported')
    try {
      const value: Any = await this.controller.runJavaScript(source)
      if (typeof value === 'string') return value
      if (value === undefined || value === null) return 'null'
      return JSON.stringify(value)
    } catch (error) {
      throw new OhosArkWebError(`plugin_execution_failed:${String(error)}`)
    }
  }

  async evaluate(source: string): Promise<Any> {
    try {
      // ArkWeb's runJavaScript returns a Promise. Execute through the
      // AsyncFunction constructor so snippets with `return`, await and
      // multiple statements have the same completion-value semantics as the
      // desktop host. `eval(source)` rejects top-level `return`, which makes
      // challenge solvers such as Baozimh look like an access block on OHOS.
      const expression = `(async()=>{try{const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;const value=await new AsyncFunction(${JSON.stringify(source)}).call(window);return JSON.stringify({value})}catch(_){return JSON.stringify({error:'plugin_execution_failed'})}})()`
      const value = await this.script(expression)
      const decoded: Any = this.parseScriptResult(value)
      if (decoded !== null && typeof decoded === 'object') {
        const error = (decoded as Record<string, string>)['error']
        if (error === 'plugin_execution_failed') throw new OhosArkWebError('plugin_execution_failed')
        return decoded
      }
      return {value: decoded}
    } catch (error) {
      throw new OhosArkWebError(`plugin_execution_failed:${String(error)}`)
    }
  }

  async html(): Promise<Any> {
    const value = await this.script('JSON.stringify({html:document.documentElement?.outerHTML??""})')
    const decoded: Any = this.parseScriptResult(value)
    if (decoded === null || typeof decoded !== 'object') throw new OhosArkWebError('plugin_execution_failed')
     return decoded
  }

  async click(x: number, y: number): Promise<Any> {
    const value = await this.script(`(()=>{const e=document.elementFromPoint(${x},${y});if(!e)return false;for(const t of ['pointerdown','mousedown','pointerup','mouseup'])e.dispatchEvent(new MouseEvent(t,{bubbles:true,clientX:${x},clientY:${y}}));e.click();return true})()`)
    if (value !== 'true') throw new OhosArkWebError('interaction_required')
    return {}
  }

  async input(text: string): Promise<Any> {
    const value = await this.script(`(()=>{const e=document.activeElement;if(!e)return false;e.value=${JSON.stringify(text)};e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));return true})()`)
    if (value !== 'true') throw new OhosArkWebError('interaction_required')
    return {}
  }

  async key(key: string, modifiers: Array<string>): Promise<Any> {
    await this.script(`document.activeElement?.dispatchEvent(new KeyboardEvent('keydown',{key:${JSON.stringify(key)},bubbles:true,altKey:${modifiers.includes('alt')},ctrlKey:${modifiers.includes('control')},shiftKey:${modifiers.includes('shift')}}))`)
    return {}
  }

  url(): string {
    try { return this.controller.getUrl() } catch (_) { return '' }
  }

  stop(): void {
    if (this.disposed) return
    try { this.controller.stop() } catch (_) { /* best effort */ }
  }

  async setVisible(value: boolean): Promise<void> {
    this.visible = value
    this.host.emitVisibility(this.pluginId, value)
  }

  async close(): Promise<void> {
    if (this.disposed) return
    this.stop()
    this.disposed = true
    this.host.detach(this.pluginId, this)
    this.host.emitRemoved(this.pluginId)
  }

  dispose(): void {
    this.close()
  }

  private parseScriptResult(value: string): Any {
    let decoded: Any = JSON.parse(value)
    if (typeof decoded === 'string') {
      const nested = decoded.trim()
      if (nested.startsWith('{') || nested.startsWith('[')) decoded = JSON.parse(nested)
    }
    return decoded
  }
}

@Builder
function buildOhosArkWeb(params: Params): void {
  Web({src: 'about:blank', controller: (params.platformView as OhosArkWebPlatformView).controller})
    .width('100%')
    .height('100%')
    .javaScriptAccess(true)
    .zoomAccess(true)
    .onAppear((): void => (params.platformView as OhosArkWebPlatformView).markReady())
}
