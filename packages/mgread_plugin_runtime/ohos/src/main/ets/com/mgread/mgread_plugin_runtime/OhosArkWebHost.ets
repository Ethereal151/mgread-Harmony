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
 * browser-session contract.
 */
export default class OhosArkWebHost implements MethodCallHandler {
  private readonly sessions = new Map<string, OhosArkWebPlatformView>()
  private readonly waiting = new Map<string, Array<(page: OhosArkWebPlatformView) => void>>()
  private readonly pendingPluginIds = new Array<string>()
  private readonly unboundPages = new Array<OhosArkWebPlatformView>()
  private readonly cancelled = new Set<string>()
  private readonly stream = new OhosArkWebSessionStreamHandler()

  getStreamHandler(): OhosArkWebSessionStreamHandler {
    return this.stream
  }

  register(registry: PlatformViewRegistry): void {
    registry.registerViewFactory(VIEW_TYPE, new OhosArkWebPlatformViewFactory(this))
  }

  emitVisibility(pluginId: string, visible: boolean): void {
    const event: Any = {type: 'session', action: 'visibility', pluginId, visible}
    this.stream.emit(event)
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'request':
        this.handleRequest(call.args as Map<string, Any> | null, result)
        break
      case 'cancel':
        this.cancel(call.args as Map<string, Any> | null)
        result.success(null)
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

  attach(pluginId: string, page: OhosArkWebPlatformView): void {
    if (pluginId.length === 0) {
      const pendingPluginId = this.pendingPluginIds.length > 0 ? this.pendingPluginIds[0] : ''
      if (pendingPluginId.length > 0) {
        page.bindPluginId(pendingPluginId)
        return
      }
      this.unboundPages.push(page)
      return
    }
    this.sessions.set(pluginId, page)
    const pendingIndex = this.pendingPluginIds.indexOf(pluginId)
    if (pendingIndex >= 0) this.pendingPluginIds.splice(pendingIndex, 1)
    const listeners = this.waiting.get(pluginId)
    if (listeners !== undefined) {
      this.waiting.delete(pluginId)
      listeners.forEach((listener: (page: OhosArkWebPlatformView) => void): void => listener(page))
    }
  }

  bindUnboundPage(pluginId: string): void {
    if (pluginId.length === 0 || this.unboundPages.length === 0) return
    const page = this.unboundPages.shift()
    if (page !== undefined) page.bindPluginId(pluginId)
  }

  detach(pluginId: string, page: OhosArkWebPlatformView): void {
    if (this.sessions.get(pluginId) !== page) return
    this.sessions.delete(pluginId)
  }

  private async handleRequest(args: Map<string, Any> | null, result: MethodResult): Promise<void> {
    try {
      const envelope: Map<string, Any> = args ?? new Map<string, Any>()
      const nested: Any = envelope.get('raw')
      const raw: Map<string, Any> = nested instanceof Map ? nested as Map<string, Any> : envelope
      if (!raw.has('jobId')) raw.set('jobId', envelope.get('jobId'))
      if (!raw.has('deadlineUnixMs')) raw.set('deadlineUnixMs', envelope.get('deadlineUnixMs'))
      const pluginId = this.stringValue(raw, 'pluginId')
      const pluginName = this.stringValue(raw, 'pluginName')
      if (pluginId.length === 0 || pluginName.length === 0) throw new OhosArkWebError('plugin_execution_failed')
      const jobId = this.stringValue(raw, 'jobId')
      const page = await this.pageFor(pluginId, pluginName)
      const operation = this.stringValue(raw, 'operation')
       let response: Any
      if (operation === 'debug') {
        await page.setVisible(true)
        response = {version: 1, accepted: true, action: this.stringValue(raw, 'action')}
      } else if (operation.startsWith('page.')) {
        response = await this.pageOperation(page, raw, jobId)
      } else if (operation === 'interaction') {
        response = await this.interaction(page, raw, jobId)
      } else {
        response = await this.legacyRequest(page, raw, jobId)
      }
      result.success(response)
    } catch (error) {
      result.error(this.errorCode(error), this.errorMessage(error), null)
    }
  }

  private async pageFor(pluginId: string, pluginName: string): Promise<OhosArkWebPlatformView> {
    const existing = this.sessions.get(pluginId)
    if (existing !== undefined) return existing
    return await new Promise<OhosArkWebPlatformView>((resolve, reject): void => {
      const listeners = this.waiting.get(pluginId) ?? []
      listeners.push(resolve)
      this.waiting.set(pluginId, listeners)
      if (!this.pendingPluginIds.includes(pluginId)) this.pendingPluginIds.push(pluginId)
      this.stream.emit({type: 'session', action: 'upsert', pluginId, pluginName, visible: false})
      this.bindUnboundPage(pluginId)
      setTimeout((): void => {
        const current = this.sessions.get(pluginId)
        if (current !== undefined) return
        const pending = this.waiting.get(pluginId)
        if (pending === undefined) return
        this.waiting.delete(pluginId)
        reject(new OhosArkWebError('unsupported'))
      }, 5_000)
    })
  }

  resolvePluginId(args: Any): string {
    if (args instanceof Map) {
      const value: Any = args.get('pluginId')
      if (typeof value === 'string' && value.length > 0) {
        return value
      }
    }
    const fallback = this.pendingPluginIds.length > 0 ? this.pendingPluginIds[0] : ''
    return fallback
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
      await this.waitReady(page, jobId, deadline)
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
    if (transport === 'http') throw new OhosArkWebError('unsupported')
    const url = this.stringValue(raw, 'url')
    await page.load(url, this.headers(raw.get('headers')))
    await this.waitReady(page, jobId, deadline)
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
    const headers = this.headers(raw.get('headers'))
    const body: Any = raw.get('body')
    const responseType = this.stringValue(raw, 'responseType') || 'text'
    const script = `fetch(${JSON.stringify(url)},{method:${JSON.stringify(method)},headers:${JSON.stringify(headers)},body:${body === null || body === undefined ? 'null' : JSON.stringify(body)},credentials:'include',redirect:'follow'}).then(async r=>{const h={};r.headers.forEach((v,k)=>h[k]=v);let b;${responseType === 'json' ? "b=await r.json()" : responseType === 'base64' ? "b=btoa(String.fromCharCode(...new Uint8Array(await r.arrayBuffer())))" : "b=await r.text()"};return JSON.stringify({status:r.status,url:r.url,headers:h,body:b})}).catch(_=>JSON.stringify({__mgreadBrowserSessionError:'plugin_execution_failed'}))`
     const payload: FetchPayload | null = await this.decode(await page.script(script)) as FetchPayload | null
     if (payload !== null && payload.__mgreadBrowserSessionError !== undefined) throw new OhosArkWebError('plugin_execution_failed')
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

  private async waitReady(page: OhosArkWebPlatformView, jobId: string, deadline: number): Promise<void> {
    while (true) {
      await this.ensureNotCancelled(jobId, deadline)
      try {
        const state = (await page.script('document.readyState')).replace(/"/g, '')
        if (state === 'interactive' || state === 'complete') return
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
    if (jobId.length > 0) this.cancelled.add(jobId)
  }

  dispose(): void {
    this.cancelled.clear()
    this.waiting.clear()
    this.sessions.forEach((page: OhosArkWebPlatformView, pluginId: string): void => {
      page.close()
      this.stream.emit({type: 'session', action: 'remove', pluginId})
    })
    this.sessions.clear()
  }

  private deadline(raw: Map<string, Any>): number {
     const value: Any = raw.get('deadlineUnixMs')
    const parsed = typeof value === 'number' ? value : Number(value ?? 0)
    if (!Number.isFinite(parsed) || parsed <= Date.now()) throw new OhosArkWebError('timeout')
    return Math.min(parsed, Date.now() + MAX_WAIT_MS)
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

  constructor(pluginId: string, host: OhosArkWebHost) {
    super()
    this.controller = new webview.WebviewController()
    this.pluginId = pluginId
    this.host = host
    host.attach(pluginId, this)
  }

  bindPluginId(pluginId: string): void {
    if (this.pluginId.length > 0 || pluginId.length === 0) return
    this.pluginId = pluginId
    this.host.attach(pluginId, this)
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(buildOhosArkWeb)
  }

  async load(url: string, headers: Array<webview.WebHeader>): Promise<void> {
    if (this.disposed) throw new OhosArkWebError('unsupported')
    this.controller.loadUrl(url, headers)
  }

  async script(source: string): Promise<string> {
    if (this.disposed) throw new OhosArkWebError('unsupported')
    return await this.controller.runJavaScript(source)
  }

  async evaluate(source: string): Promise<Any> {
    const value = await this.script(`(async()=>{const AsyncFunction=Object.getPrototypeOf(async function(){}).constructor;const value=await new AsyncFunction(${JSON.stringify(source)}).call(window);return JSON.stringify({value});})()`)
    const decoded: Any = this.parseScriptResult(value)
    if (decoded === null || typeof decoded !== 'object') throw new OhosArkWebError('plugin_execution_failed')
     return decoded
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

  async setVisible(value: boolean): Promise<void> {
    this.visible = value
    this.host.emitVisibility(this.pluginId, value)
  }

  async close(): Promise<void> {
    if (this.disposed) return
    this.disposed = true
    try { this.controller.stop() } catch (_) { /* best effort */ }
    this.host.detach(this.pluginId, this)
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
}
