import common from '@ohos.app.ability.common'
import window from '@ohos.window'
import webview from '@ohos.web.webview'
import {
  Any,
  MethodResult,
  PlatformView,
  PlatformViewFactory,
  StandardMessageCodec,
  Log,
} from '@ohos/flutter_ohos'
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView'

const VIEW_TYPE = 'mgread_ohos_hls_video'

export class OhosHlsVideoHost {
  private readonly views: Map<string, OhosHlsVideoPlatformView> = new Map()

  factory(): PlatformViewFactory {
    return new OhosHlsVideoPlatformViewFactory(this)
  }

  attach(view: OhosHlsVideoPlatformView): void {
    this.views.set(view.sessionId, view)
  }

  detach(sessionId: string): void {
    this.views.delete(sessionId)
  }

  command(args: Map<string, Object> | null, result: MethodResult): void {
    const sessionId = this.stringValue(args, 'sessionId')
    const command = this.stringValue(args, 'command')
    const view = this.views.get(sessionId)
    if (view === undefined) {
      result.error('session_unavailable', 'The OHOS HLS WebView is unavailable.', null)
      return
    }
    view.command(command, args).then(() => result.success(null)).catch((error: Error) => {
      result.error('operation_failed', String(error), null)
    })
  }

  private stringValue(args: Map<string, Object> | null, key: string): string {
    const value = args?.get(key)
    return typeof value === 'string' ? value : ''
  }
}

export class OhosHlsVideoPlatformView extends PlatformView {
  readonly controller: webview.WebviewController
  readonly sessionId: string
  private readonly url: string
  private readonly host: OhosHlsVideoHost
  private readonly context: common.Context
  private started = false
  private disposed = false

  constructor(args: Any, host: OhosHlsVideoHost, context: common.Context) {
    super()
    const values = args as Map<string, Object>
    this.sessionId = this.stringValue(values, 'sessionId')
    this.url = this.stringValue(values, 'url')
    this.host = host
    this.context = context
    this.controller = new webview.WebviewController()
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(buildOhosHlsVideo)
  }

  start(): void {
    if (this.started || this.disposed || this.url.length === 0) return
    this.started = true
    const html = `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><style>html,body,video{margin:0;width:100%;height:100%;background:#000}video{object-fit:contain}</style><script src="https://oss.l-il.cn/libs/hls/hls.light-0.8.8.min.js"></script></head><body><video id="mgread-video" controls autoplay muted playsinline></video><script>const v=document.getElementById('mgread-video');const source=${JSON.stringify(this.url)};const start=()=>{v.muted=true;v.play().then(()=>setTimeout(()=>{v.muted=false},800)).catch(()=>{})};if(window.Hls&&Hls.isSupported()){const hls=new Hls();hls.on(Hls.Events.MANIFEST_PARSED,start);hls.on(Hls.Events.ERROR,(event,data)=>{document.title='mgread-hls-error-'+String(data?.details??'unknown')});hls.loadSource(source);hls.attachMedia(v)}else{v.src=source;v.addEventListener('loadedmetadata',start)}</script></body></html>`
    Log.w('MgReadOhosMedia', `web_start session=${this.sessionId} urlLength=${this.url.length}`)
    this.controller.loadData(html, 'text/html', 'UTF-8', 'https://player.mcue.cc/yinhua/')
    this.host.attach(this)
    this.scheduleWebPlay(2500)
    this.scheduleWebPlay(6000)
    this.scheduleWebProbe(9000)
  }

  private scheduleWebPlay(delayMs: number): void {
    setTimeout((): void => {
      if (this.disposed) return
      this.controller.runJavaScript('(()=>{const v=document.querySelector("video");if(v){v.muted=true;return v.play()}})()').then((value: string): void => {
        Log.w('MgReadOhosMedia', `web_play session=${this.sessionId} value=${value}`)
      }).catch((error: Error): void => Log.w('MgReadOhosMedia', `web_play_error session=${this.sessionId} message=${String(error)}`))
    }, delayMs)
  }

  private scheduleWebProbe(delayMs: number): void {
    setTimeout((): void => {
      if (this.disposed) return
      this.controller.runJavaScript('(()=>{const v=document.querySelector("video");return JSON.stringify({readyState:v?.readyState??-1,networkState:v?.networkState??-1,paused:v?.paused??true,currentTime:v?.currentTime??0,currentSrc:v?.currentSrc??"",duration:v?.duration??0,videoWidth:v?.videoWidth??0,videoHeight:v?.videoHeight??0,error:v?.error?.code??0,title:document.title,videoCount:document.querySelectorAll("video").length})})()').then((value: string): void => {
        Log.w('MgReadOhosMedia', `web_state session=${this.sessionId} value=${value}`)
      }).catch((error: Error): void => Log.w('MgReadOhosMedia', `web_probe_error session=${this.sessionId} message=${String(error)}`))
    }, delayMs)
  }

  async command(command: string, args: Map<string, Object> | null): Promise<void> {
    if (this.disposed) throw new Error('The OHOS HLS WebView is disposed.')
    const positionMs = this.numberValue(args, 'positionMs')
    const rate = this.numberValue(args, 'rate')
    const volume = this.numberValue(args, 'volume')
    let script = ''
    switch (command) {
      case 'play':
        script = '(()=>{const v=document.getElementById("mgread-video");if(v){v.muted=false;return v.play()}})()'
        break
      case 'pause':
        script = 'document.getElementById("mgread-video")?.pause()'
        break
      case 'seek':
        script = `document.getElementById("mgread-video").currentTime=${positionMs / 1000}`
        break
      case 'setRate':
        script = `document.getElementById("mgread-video").playbackRate=${rate}`
        break
      case 'setVolume':
        script = `document.getElementById("mgread-video").volume=${volume}`
        break
      case 'dispose':
        this.dispose()
        return
      default:
        return
    }
    await this.controller.runJavaScript(script)
  }

  dispose(): void {
    if (this.disposed) return
    this.disposed = true
    this.host.detach(this.sessionId)
    try { this.controller.stop() } catch (_) { /* best effort */ }
  }

  async handleFullscreen(fullscreen: boolean): Promise<void> {
    try {
      const target = await window.getLastWindow(this.context)
      await target.setPreferredOrientation(
        fullscreen ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT,
      )
      // Keep the video surface behind the system-bar areas for both
      // orientations. In portrait, hiding the navigation area prevents the
      // gesture region from exposing the device-default light background.
      await target.setWindowLayoutFullScreen(true)
      await target.setWindowSystemBarEnable(fullscreen ? [] : ['status'])
      await target.setWindowSystemBarProperties({
        statusBarColor: '#000000',
        navigationBarColor: '#000000',
        statusBarContentColor: '#FFFFFF',
        navigationBarContentColor: '#FFFFFF',
      })
      Log.w('MgReadOhosMedia', `web_fullscreen session=${this.sessionId} value=${fullscreen}`)
      if (!fullscreen) {
        // ArkWeb/WMS reapplies the navigation bar after the rotation
        // animation. Reassert the portrait video chrome after that transition
        // or the gesture area becomes white again.
        setTimeout((): void => {
          this.reapplyPortraitSystemBars(target).catch((error: Object) => {
            Log.w('MgReadOhosMedia', `web_portrait_bars_error session=${this.sessionId} message=${String(error)}`)
          })
        }, 1000)
      }
    } catch (error) {
      Log.w('MgReadOhosMedia', `web_fullscreen_error session=${this.sessionId} message=${String(error)}`)
    }
  }

  private async reapplyPortraitSystemBars(target: window.Window): Promise<void> {
    await target.setWindowLayoutFullScreen(true)
    await target.setWindowSystemBarEnable(['status'])
    await target.setWindowSystemBarProperties({
      statusBarColor: '#000000',
      navigationBarColor: '#000000',
      statusBarContentColor: '#FFFFFF',
      navigationBarContentColor: '#FFFFFF',
    })
    Log.w('MgReadOhosMedia', `web_portrait_bars_reapplied session=${this.sessionId}`)
  }

  private stringValue(args: Map<string, Object>, key: string): string {
    const value = args.get(key)
    return typeof value === 'string' ? value : ''
  }

  private numberValue(args: Map<string, Object> | null, key: string): number {
    const value = args?.get(key)
    return typeof value === 'number' ? value : 0
  }
}

class OhosHlsVideoPlatformViewFactory extends PlatformViewFactory {
  private readonly host: OhosHlsVideoHost

  constructor(host: OhosHlsVideoHost) {
    super(StandardMessageCodec.INSTANCE)
    this.host = host
  }

  create(context: common.Context, viewId: number, args: Any): PlatformView {
    return new OhosHlsVideoPlatformView(args, this.host, context)
  }
}

@Builder
function buildOhosHlsVideo(params: Params): void {
  Web({src: 'about:blank', controller: (params.platformView as OhosHlsVideoPlatformView).controller})
    .width('100%')
    .height('100%')
    .javaScriptAccess(true)
    .zoomAccess(false)
    .onFullScreenEnter((): void => {
      (params.platformView as OhosHlsVideoPlatformView).handleFullscreen(true)
    })
    .onFullScreenExit((): void => {
      (params.platformView as OhosHlsVideoPlatformView).handleFullscreen(false)
    })
    .onAppear((): void => (params.platformView as OhosHlsVideoPlatformView).start())
}

export { VIEW_TYPE }
