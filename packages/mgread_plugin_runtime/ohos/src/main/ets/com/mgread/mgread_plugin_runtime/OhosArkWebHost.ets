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
const EVALUATE_POLL_MS = 500
// Keep the browser bridge at the Runtime resource contract's raw-byte limit;
// the previous 2 MiB host default rejected valid media before Runtime could
// validate or cache it.
const MAX_RESPONSE_BYTES = 16 * 1024 * 1024
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
      if (operation.startsWith('page.')) {
        // The Runtime serializes ordinary calls, but the platform bridge can
        // still deliver requests from separate loopback consumers while a
        // previous call is finishing. ArkWeb has one mutable document per
        // page; navigation, script injection, and fetch must therefore share
        // one host-side transaction boundary as well.
        response = isPageControlOperation(operation)
          ? await this.pageOperation(page, raw, jobId)
          : await page.runExclusive(() => this.pageOperation(page, raw, jobId))
      }
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
    const script = `const c=new AbortController();const t=setTimeout(()=>c.abort(),${Math.max(1, deadline - Date.now())});try{return await fetch(${JSON.stringify(url)},{method:${JSON.stringify(method)},headers:${JSON.stringify(headers)},body:${body === null || body === undefined ? 'null' : JSON.stringify(body)},credentials:'include',redirect:'follow',signal:c.signal}).then(async r=>{const source=new URL(${JSON.stringify(url)});const finalUrl=new URL(r.url);if(source.origin!==finalUrl.origin)throw new Error('cross_origin');const bytes=await r.arrayBuffer();if(bytes.byteLength>${maxResponseBytes})throw new Error('overloaded');const h={};for(const k of ['cache-control','content-type','etag','expires','last-modified']){const v=r.headers.get(k);if(v!==null)h[k]=v.slice(0,1024)};const text=new TextDecoder().decode(bytes);let b;${responseType === 'json' ? "b=JSON.parse(text)" : responseType === 'base64' ? "b=btoa(Array.from(new Uint8Array(bytes),x=>String.fromCharCode(x)).join(''))" : "b=text"};return {status:r.status,url:r.url,headers:h,body:b}})}catch(error){return {__mgreadBrowserSessionError:error?.message==='overloaded'?'overloaded':'plugin_execution_failed'}}finally{clearTimeout(t)}`
     const evaluated: Any = await page.evaluate(script)
     const payload: FetchPayload | null = evaluated !== null && typeof evaluated === 'object'
       ? (evaluated as Record<string, Any>)['value'] as FetchPayload | null
       : null
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
    let previousFingerprint = ''
    let stableSamples = 0
    while (true) {
      await this.ensureNotCancelled(jobId, deadline)
      try {
        const state = (await page.script('document.readyState')).replace(/"/g, '')
        if (targetUrl === 'about:blank') return
        if (await page.navigationMarkerPresent()) {
          await this.delay(POLL_MS)
          continue
        }
        const body = (await page.script('document.body?.innerHTML??""')).replace(/"/g, '')
        const currentUrl = page.url()
        // A source may navigate directly to a protected page after a
        // previously verified page. ArkWeb then renders the challenge page,
        // but the source must receive that DOM first so it can inspect and
        // solve the challenge through the public WebView API. Waiting here for
        // the challenge to finish deadlocks that source-side flow.
        const challengePage = currentUrl.includes('/__gatekeeper_challenge/') &&
          body.includes('challengeId:') && body.includes('verifyUrl:')
        if (challengePage) return
        if (isImageDocumentUrl(currentUrl, targetUrl) && page.isPageEnded(currentUrl)) return
        if (state === 'complete') {
          const ready = body.trim().length > 0
          if (ready) {
            const fingerprint = (await page.script('(()=>{const s=document.documentElement?.outerHTML??"";let h=0;for(let i=0;i<s.length;i++)h=((h<<5)-h+s.charCodeAt(i))|0;return `${s.length}:${h}`})()')).replace(/"/g, '')
            stableSamples = fingerprint === previousFingerprint ? stableSamples + 1 : 1
            previousFingerprint = fingerprint
            if (stableSamples >= 3) return
          } else {
            stableSamples = 0
            previousFingerprint = ''
          }
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

function isPageControlOperation(operation: string): boolean {
  return operation === 'page.open' || operation === 'page.show' ||
    operation === 'page.hide' || operation === 'page.close'
}

function isImageDocumentUrl(currentUrl: string, requestUrl: string): boolean {
  if (currentUrl.length === 0 || currentUrl !== requestUrl) return false
  try {
    return /\.(?:avif|gif|jpe?g|png|webp)(?:$|[?#])/iu.test(currentUrl)
  } catch (_) {
    return false
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
  private evaluateSequence = 0
  private evaluateTail: Promise<void> = Promise.resolve()
  private pageOperationTail: Promise<void> = Promise.resolve()
  private navigationMarker = ''
  private explicitNavigationUrl = ''
  private pageEndUrl = ''

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

  shouldInterceptNavigation(event: Any): boolean {
    try {
      const targetUrl = String(event.data.getRequestUrl())
      if (/^https?:\/\//u.test(targetUrl)) {
        // Let ArkWeb follow the server redirect itself.
        // Replaying redirects through about:blank can turn a legitimate
        // multi-host chain into a redirect loop.
      }
      const currentUrl = this.controller.getUrl()
      if (!currentUrl.includes('/__gatekeeper_challenge/') || targetUrl.includes('/__gatekeeper_challenge/')) return false
      if (targetUrl === this.explicitNavigationUrl) {
        this.explicitNavigationUrl = ''
        return false
      }
      return true
    } catch (_) {
      return false
    }
  }

  onPageEnd(event: Any): void {
    try {
      const endedUrl = String(event.url ?? '')
      this.pageEndUrl = endedUrl
    } catch (_) {
      this.pageEndUrl = ''
    }
  }

  isPageEnded(url: string): boolean {
    return this.pageEndUrl === url
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(buildOhosArkWeb)
  }

  async load(url: string, headers: Array<webview.WebHeader>): Promise<void> {
    if (this.disposed) throw new OhosArkWebError('unsupported')
    let lastError: Object | null = null
    for (let attempt = 0; attempt < 75; attempt++) {
      try {
        this.explicitNavigationUrl = url
        this.pageEndUrl = ''
        if (url === 'about:blank') {
          this.navigationMarker = ''
          this.controller.loadUrl(url, headers)
          return
        }
        // Do not inject a marker into the current document before navigation.
        // Image documents on ArkWeb can stop accepting scripts after repeated
        // image-to-page transitions. The load-end callback is the platform
        // navigation boundary and is sufficient for the subsequent readiness
        // probe.
        this.navigationMarker = ''
        this.controller.loadUrl(url, headers)
        for (let waitAttempt = 0; waitAttempt < 75; waitAttempt++) {
          try {
            const current = this.controller.getUrl()
            if (current.length > 0 && current !== 'about:blank' && this.pageEndUrl.length > 0) {
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

  async navigationMarkerPresent(): Promise<boolean> {
    if (this.navigationMarker.length === 0) return false
    const value = await this.script(`document.documentElement?.getAttribute('data-mgread-navigation-marker')===${JSON.stringify(this.navigationMarker)}`)
    return value.replace(/"/g, '') === 'true'
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
    let release: () => void = (): void => {}
    const turn = new Promise<void>((resolve): void => {
      release = resolve
    })
    const previous = this.evaluateTail
    this.evaluateTail = previous.then((): Promise<void> => turn)
    await previous
    try {
      return await this.evaluateUnlocked(source)
    } finally {
      release()
    }
  }

  async runExclusive(operation: () => Promise<Any>): Promise<Any> {
    let release: () => void = (): void => {}
    const turn = new Promise<void>((resolve): void => {
      release = resolve
    })
    const previous = this.pageOperationTail
    this.pageOperationTail = previous.then((): Promise<void> => turn)
    await previous
    try {
      return await operation()
    } finally {
      release()
    }
  }

  private async evaluateUnlocked(source: string): Promise<Any> {
    try {
      const trimmed = source.trim()
      if (!trimmed.includes(';') && !/\breturn\b/.test(trimmed)) {
        const value = await this.script(`JSON.stringify(${source})`)
        return {value: this.parseScriptResult(value)}
      }
      const key = `__mgreadEvaluate_${this.evaluateSequence++}`
      const keyLiteral = JSON.stringify(key)
      const navigationBaseLiteral = JSON.stringify(this.url())
      const injected = `(()=>{
        const originalFetch=window.fetch
        const restore=()=>{window.fetch=originalFetch}
        const publish=(value)=>{window[${keyLiteral}]=JSON.stringify(value)}
        const finish=(value)=>{publish({value:value===undefined?null:value});restore()}
        const fail=(error)=>{publish({error:'plugin_execution_failed',detail:String(error)});restore()}
        const asyncFetch=(input,init={})=>new Promise((resolve,reject)=>{
          const navigationBase=${navigationBaseLiteral}
          const request=new URL(typeof input==='string'?input:input?.url||String(input),navigationBase)
          const navigationOrigin=/^https?:\\/\\//.test(navigationBase)?new URL(navigationBase).origin:''
          if(navigationOrigin.length>0&&request.pathname.startsWith('/__gatekeeper_challenge/')&&request.origin!==navigationOrigin)request.href=new URL(request.pathname+request.search+request.hash,navigationOrigin).toString()
          const requestUrl=request.toString()
          const method=init.method||'GET'
          const requestHeaders=Object.assign({},init.headers||{})
          const xhr=new XMLHttpRequest()
          xhr.open(method,requestUrl,true)
          xhr.responseType='arraybuffer'
          xhr.withCredentials=init.credentials==='include'||init.credentials==='same-origin'
          const forbiddenRequestHeader=/^(?:accept-charset|accept-encoding|access-control-request-headers|access-control-request-method|connection|content-length|cookie2?|date|dnt|expect|host|keep-alive|origin|proxy-|referer|sec-|te|trailer|transfer-encoding|upgrade|user-agent|via)$/i
          Object.entries(requestHeaders).forEach(([name,value])=>{if(!forbiddenRequestHeader.test(name))xhr.setRequestHeader(name,String(value))})
          const complete=()=>{
            try{
              const responseHeaders={}
              ;(xhr.getAllResponseHeaders()||'').trim().split(/[\\r\\n]+/).forEach((line)=>{
                const separator=line.indexOf(':')
                if(separator>0)responseHeaders[line.slice(0,separator).trim().toLowerCase()]=line.slice(separator+1).trim()
              })
              const rawBytes=xhr.response instanceof ArrayBuffer?new Uint8Array(xhr.response):new Uint8Array()
              const body=new TextDecoder().decode(rawBytes)
              resolve({bodyUsed:false,ok:xhr.status>=200&&xhr.status<300,status:xhr.status,statusText:xhr.statusText||'',url:xhr.responseURL||requestUrl,headers:{get:(name)=>responseHeaders[String(name).toLowerCase()]??null},text:()=>Promise.resolve(body),json:()=>Promise.resolve(JSON.parse(body)),arrayBuffer:()=>Promise.resolve(rawBytes.buffer.slice(rawBytes.byteOffset,rawBytes.byteOffset+rawBytes.byteLength))})
            }catch(error){reject(error)}
          }
          xhr.onload=complete
          xhr.onerror=()=>reject(new Error('network_error'))
          xhr.onabort=()=>reject(new Error('aborted'))
          if(init.signal){
            if(init.signal.aborted){xhr.abort()}
            else init.signal.addEventListener('abort',()=>xhr.abort(),{once:true})
          }
          try{xhr.send(init.body===undefined||init.body===null?null:String(init.body))}catch(error){reject(error)}
        })
        window.fetch=asyncFetch
        try{
          const value=(async(fetch)=>{${source}\n})(asyncFetch)
          if(value&&typeof value.then==='function')value.then(finish,fail)
          else finish(value)
        }catch(error){fail(error)}
      })()`
      const expression = `(()=>{
        const key=${keyLiteral}
        window[key]={pending:true}
        ;(${injected})
        return 'started'
      })()`
      await this.script(expression)
      await new Promise<void>((resolve): void => {
        setTimeout((): void => resolve(), EVALUATE_POLL_MS)
      })
      const deadline = Date.now() + MAX_WAIT_MS
      let decoded: Any = null
      while (Date.now() < deadline) {
        const pending = await this.script(`JSON.stringify(window[${keyLiteral}]??null)`)
        decoded = this.parseScriptResult(pending)
        const unresolved = decoded === null || (
          typeof decoded === 'object' && decoded !== null &&
          (decoded as Record<string, Any>)['pending'] === true
        )
        if (!unresolved) break
        await new Promise<void>((resolve): void => {
          setTimeout((): void => resolve(), EVALUATE_POLL_MS)
        })
      }
      await this.script(`delete window[${keyLiteral}]`)
      if (decoded === null) throw new OhosArkWebError('timeout')
      if (decoded !== null && typeof decoded === 'object') {
        const error = (decoded as Record<string, string>)['error']
        if (error === 'plugin_execution_failed') {
          throw new OhosArkWebError('plugin_execution_failed')
        }
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
    // ArkWeb can keep returning the pre-redirect controller URL after the
    // load-end callback has reported the committed document.  The load-end
    // URL is the authoritative page origin for subsequent script requests.
    if (this.pageEndUrl.length > 0) return this.pageEndUrl
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
    for (let depth = 0; depth < 4 && typeof decoded === 'string'; depth++) {
      const nested = decoded.trim()
      if (!nested.startsWith('{') && !nested.startsWith('[') && !nested.startsWith('"')) break
      try {
        decoded = JSON.parse(nested)
      } catch (_) {
        break
      }
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
    .onPageEnd((event: Any): void => (params.platformView as OhosArkWebPlatformView).onPageEnd(event))
    .onLoadIntercept((event: Any): boolean => (params.platformView as OhosArkWebPlatformView).shouldInterceptNavigation(event))
    .onControllerAttached((): void => (params.platformView as OhosArkWebPlatformView).markReady())
}
