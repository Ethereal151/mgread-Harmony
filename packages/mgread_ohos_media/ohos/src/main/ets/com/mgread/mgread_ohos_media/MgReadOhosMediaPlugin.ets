import {
  Any,
  EventChannel,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  AbilityAware,
  AbilityPluginBinding,
  Log,
  PlatformView,
  PlatformViewFactory,
  StandardMessageCodec,
} from '@ohos/flutter_ohos'
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView'
import common from '@ohos.app.ability.common'
import media from '@ohos.multimedia.media'
import audio from '@ohos.multimedia.audio'
import avSession from '@ohos.multimedia.avsession'
import OhosAudioBackgroundTask from './OhosAudioBackgroundTask'
import OhosMediaEventStreamHandler from './OhosMediaEventStreamHandler'

interface MediaSession {
  player: media.AVPlayer
  playerSurfaceId?: string
  video: boolean
  initialPositionMs: number
  loop: boolean
}

const VIDEO_SURFACE_VIEW_TYPE = 'mgread_ohos_video_surface'

class OhosVideoSurfacePlatformViewFactory extends PlatformViewFactory {
  private readonly owner: MgReadOhosMediaPlugin

  constructor(owner: MgReadOhosMediaPlugin) {
    super(StandardMessageCodec.INSTANCE)
    this.owner = owner
  }

  create(_context: common.Context, _viewId: number, _args: Any): PlatformView {
    return new OhosVideoSurfacePlatformView(this.owner)
  }
}

class OhosVideoSurfacePlatformView extends PlatformView {
  private readonly owner: MgReadOhosMediaPlugin
  private readonly controller: XComponentController = new XComponentController()
  private disposed = false

  constructor(owner: MgReadOhosMediaPlugin) {
    super()
    this.owner = owner
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(buildOhosVideoSurface)
  }

  markLoaded(): void {
    if (this.disposed) return
    this.owner.onVideoSurfaceReady(this, this.controller.getXComponentSurfaceId())
  }

  dispose(): void {
    if (this.disposed) return
    this.disposed = true
    this.owner.onVideoSurfaceDisposed(this)
  }

  getXComponentController(): XComponentController {
    return this.controller
  }

  dispatchTouch(event: TouchEvent): void {
    // HCPP places the DISPLAY platform view above Flutter's raster surface.
    // Forward touches from the native surface back to Flutter so the Dart
    // gesture layer can reveal controls, seek, and toggle playback. In the
    // texture path no dispatcher is installed, so the surface remains passive.
    if (this.ohosHcppViewId < 0 || this.touchDispatcher == null) return
    this.touchDispatcher(this.ohosHcppViewId, event)
  }
}

@Builder
function buildOhosVideoSurface(params: Params): void {
  Stack() {
    XComponent({
      id: 'mgread_ohos_video_surface',
      type: XComponentType.SURFACE,
      controller: (params.platformView as OhosVideoSurfacePlatformView).getXComponentController(),
    })
      .width('100%')
      .height('100%')
      // The SURFACE only renders video. Input belongs to the outer container,
      // matching the reference player's permanent-surface structure.
      .hitTestBehavior(HitTestMode.None)
      .backgroundColor('#000000')
      .onLoad((): void => (params.platformView as OhosVideoSurfacePlatformView).markLoaded())
  }
    .width('100%')
    .height('100%')
    // HCPP needs the container to receive the event before forwarding it to
    // Flutter's pointer arena. The texture path has no dispatcher and stays
    // passive through the guard in dispatchTouch().
    .hitTestBehavior(HitTestMode.Default)
    .onTouch((event: TouchEvent): void => {
      (params.platformView as OhosVideoSurfacePlatformView).dispatchTouch(event)
    })
}

interface OhosMediaEventPayload {
  sessionId: string
  kind: string
  value?: boolean | number | null
  message?: string
  width?: number
  height?: number
}

/** Native AVPlayer owner for OHOS audio and video sessions. */
export default class MgReadOhosMediaPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private static readonly TAG = 'MgReadOhosMedia'
  private methodChannel?: MethodChannel
  private eventChannel?: EventChannel
  private readonly events = new OhosMediaEventStreamHandler()
  private sessions: Map<string, MediaSession> = new Map()
  private videoSurfaceId?: string
  private videoSurfaceOwner?: OhosVideoSurfacePlatformView
  private videoSurfaceWaiters: Array<(surfaceId: string) => void> = []
  private context?: common.UIAbilityContext
  private audioSession?: avSession.AVSession
  private audioSessionManager?: audio.AudioSessionManager
  private audioSessionId?: string
  private audioState: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_INITIAL
  private audioPosition = 0
  private audioDuration = 0
  private audioSpeed = 1
  private audioVolume = 1
  private audioWasPlayingBeforeInterrupt = false
  private audioInterruptionActive = false
  // AVPlayer emits timeUpdate much faster than the AVSession service can
  // consume state writes. Keep one write in flight and coalesce the newest
  // position so Bluetooth/Star Flash controllers see fresh state without
  // building an unbounded AVSession request queue.
  private audioPlaybackSyncInFlight = false
  private audioPlaybackSyncPending = false
  private audioPlaybackSyncTimer?: number
  private audioPlaybackSyncLastSentAt = 0
  private audioPlaybackSyncGeneration = 0
  private static readonly AUDIO_PLAYBACK_SYNC_INTERVAL_MS = 1000
  private readonly audioBackgroundTask = new OhosAudioBackgroundTask()

  getUniqueClassName(): string {
    return 'MgReadOhosMediaPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    binding.getPlatformViewRegistry().registerViewFactory(
      VIDEO_SURFACE_VIEW_TYPE,
      new OhosVideoSurfacePlatformViewFactory(this),
    )
    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), 'mgread/ohos_media')
    this.methodChannel.setMethodCallHandler(this)
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'mgread/ohos_media/events')
    this.eventChannel.setStreamHandler(this.events)
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context as common.UIAbilityContext
    this.audioBackgroundTask.attach(this.context)
  }

  onDetachedFromAbility(): void {
    // The AVSession belongs to the process-scoped media host. An Ability can
    // detach while the app is backgrounded; destroying it here would make
    // lock-screen and Bluetooth controls stop the track mid-session.
    this.context = undefined
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.methodChannel?.setMethodCallHandler(null)
    this.eventChannel?.setStreamHandler(null)
    this.methodChannel = undefined
    this.eventChannel = undefined
    this.disposeAll()
      .then(() => this.destroyAudioSession())
      .then(() => {
        this.context = undefined
        this.audioBackgroundTask.detach()
      })
      .catch(() => {})
  }

  onVideoSurfaceReady(view: OhosVideoSurfacePlatformView, surfaceId: string): void {
    if (surfaceId.length === 0) return
    this.videoSurfaceOwner = view
    this.videoSurfaceId = surfaceId
    this.log(`video_surface_ready surfaceId=${surfaceId}`)
    const waiters = this.videoSurfaceWaiters
    this.videoSurfaceWaiters = []
    waiters.forEach((waiter: (id: string) => void): void => waiter(surfaceId))
  }

  onVideoSurfaceDisposed(view: OhosVideoSurfacePlatformView): void {
    if (this.videoSurfaceOwner !== view) return
    this.videoSurfaceOwner = undefined
    this.videoSurfaceId = undefined
    this.log('video_surface_disposed')
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args = call.args as Map<string, Object> | null
    switch (call.method) {
      case 'audio.open':
        this.open(args, false, result)
        break
      case 'video.open':
        this.open(args, true, result)
        break
      case 'dispose':
        this.disposeSession(this.sessionId(args)).then(() => result.success(null)).catch((error: Error) => {
          result.error('dispose_failed', this.errorMessage(error), null)
        })
        break
      case 'play':
        const playSessionId = this.sessionId(args)
        this.log(`command_received session=${playSessionId} method=play`)
        const playSession = this.sessions.get(playSessionId)
        if (playSession !== undefined && playSession.player.state === 'completed') {
          this.log(`command_translated session=${playSessionId} method=play target=next reason=completed`)
          this.emit(playSessionId, 'remoteCommand', 'next')
          result.success(null)
          break
        }
        this.run(args, (session) => this.playSession(playSessionId, session), result)
        break
      case 'pause':
        this.run(args, (session) => this.pauseSession(this.sessionId(args), session), result)
        break
      case 'seek':
        this.run(args, (session) => {
          session.player.seek(this.number(args, 'positionMs'))
          return Promise.resolve()
        }, result)
        break
      case 'setRate':
        this.run(args, (session) => {
          session.player.setPlaybackRate(this.number(args, 'rate'))
          return Promise.resolve()
        }, result)
        break
      case 'setVolume':
        this.run(args, (session) => {
          session.player.setVolume(this.number(args, 'volume'))
          return Promise.resolve()
        }, result)
        break
      case 'disposeAll':
        this.disposeAll()
        result.success(null)
        break
      default:
        result.notImplemented()
        break
    }
  }

  private async open(args: Map<string, Object> | null, video: boolean, result: MethodResult): Promise<void> {
    const sessionId = this.sessionId(args)
    const url = this.stringValue(args, 'url')
    if (sessionId.length === 0 || url.length === 0) {
      result.error('invalid_argument', 'A sessionId and URL are required.', null)
      return
    }
    try {
      await this.disposeSession(sessionId)
      const surfaceId = video ? await this.waitForVideoSurface() : undefined
      const player = await media.createAVPlayer()
      const headers = this.headers(args?.get('headers'))
      const initialPositionMs = this.number(args, 'initialPositionMs')
      const loop = this.booleanValue(args, 'loop')
      const session: MediaSession = {player, video, initialPositionMs, loop}
      this.sessions.set(sessionId, session)
      this.bind(sessionId, session)
      const resourceType = this.stringValue(args, 'resourceType')
      const hls = this.isHlsUrl(url, resourceType)
      this.log(`open session=${sessionId} video=${video} resourceType=${resourceType} hls=${hls} urlLength=${url.length} headerCount=${Object.keys(headers).length}`)
      const runtimeLoopback = this.isRuntimeLoopbackUrl(url)
      // Match LegadoArkTS: URL-backed playback must start through
      // AVPlayer.url. On API 26, MediaSource-backed streams may close their
      // loader before the first bytes are read and leave AVPlayer in
      // initialized forever. Runtime media URLs are private loopback proxy
      // endpoints; their upstream headers are owned by Runtime and must not
      // be replayed as headers on the local request. Use the same URL-first
      // path for both HLS and loopback resources.
      if (hls || runtimeLoopback) {
        player.url = url
        const mode = hls ? (runtimeLoopback ? 'loopback_hls' : 'remote_hls') : 'loopback_media'
        this.log(`url_set session=${sessionId} mode=${mode}`)
      } else {
        const source = media.createMediaSourceWithUrl(url, headers)
        // API 26 devices expose setMediaSource(strategy) in the type surface,
        // but the runtime does not expose preferredBufferDurationForPlaying or
        // preferredBufferDuration. Passing a PlaybackStrategy therefore makes
        // the native parser enter an unsupported configuration before it reads
        // the HLS playlist. Let MediaKit use its default buffering policy.
        await player.setMediaSource(source)
      }
      this.log(`source_set session=${sessionId} state=${player.state}`)
      await this.waitForState(player, 'initialized')
      if (surfaceId !== undefined) {
        player.surfaceId = surfaceId
        session.playerSurfaceId = surfaceId
        this.log(`surface_bound session=${sessionId} playerSurfaceId=${surfaceId} mode=xcomponent`)
      }
      if (!video) {
        await this.prepareSession(sessionId, args, session)
        if (this.booleanValue(args, 'play')) await this.playSession(sessionId, session)
      }
      result.success({
        sessionId,
        durationMs: video ? 0 : player.duration,
      })
    } catch (error) {
      await this.disposeSession(sessionId)
      result.error('open_failed', this.errorMessage(error), null)
    }
  }

  private bind(sessionId: string, session: MediaSession): void {
    const player = session.player
    player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => {
      this.log(`state session=${sessionId} state=${state} reason=${reason}`)
      this.emit(sessionId, 'state', state)
      if (state === 'playing') this.emit(sessionId, 'playing', true)
      if (state === 'paused' || state === 'completed' || state === 'stopped') this.emit(sessionId, 'playing', false)
      if (state === 'completed') this.emit(sessionId, 'completed', true)
      if (state === 'error') this.emit(sessionId, 'error', null, `avplayer_state_error_${reason}`)
      if (!session.video) {
        const playbackState = this.playbackState(state)
        if (playbackState !== undefined) this.syncAudioPlaybackState(sessionId, playbackState)
      }
    })
    player.on('timeUpdate', (value: number) => {
      // Keep the latest position locally. Huawei AVSession state writes are
      // control-plane operations; sending one for every AVPlayer timeUpdate
      // blocks the service executor and makes Bluetooth/Star Flash controls
      // time out. Position is published with the next state/seek update.
      if (this.audioSessionId === sessionId) this.audioPosition = value
      this.emit(sessionId, 'position', value)
    })
    player.on('durationUpdate', (value: number) => {
      this.emit(sessionId, 'duration', value)
      if (!session.video) this.syncAudioPlaybackState(sessionId, undefined, undefined, value)
    })
    player.on('bufferingUpdate', (kind: media.BufferingInfoType, value: number) => {
      if (kind === media.BufferingInfoType.BUFFERING_START) {
        this.emit(sessionId, 'buffering', true)
      } else if (kind === media.BufferingInfoType.BUFFERING_END) {
        this.emit(sessionId, 'buffering', false)
      } else if (kind === media.BufferingInfoType.BUFFERING_PERCENT) {
        this.emit(sessionId, 'bufferingPercent', value)
      } else if (kind === media.BufferingInfoType.CACHED_DURATION) {
        // HarmonyOS reports the playable cache in milliseconds. Preserve it
        // as a real time-based buffered position for the Flutter backend.
        this.emit(sessionId, 'buffered', value)
      }
    })
    player.on('videoSizeChange', (width: number, height: number) => {
      this.log(`video_size session=${sessionId} width=${width} height=${height}`)
      if (width > 0 && height > 0) {
        this.emitVideoSize(sessionId, width, height)
      }
    })
    player.on('startRenderFrame', () => {
      this.log(`first_frame session=${sessionId}`)
      this.emit(sessionId, 'firstFrame', true)
    })
    player.on('endOfStream', () => this.emit(sessionId, 'completed', true))
    player.on('volumeChange', (value: number) => {
      this.emit(sessionId, 'volume', value)
      if (!session.video) this.syncAudioPlaybackState(sessionId, undefined, undefined, undefined, undefined, value)
    })
    player.on('playbackRateDone', (value: number) => {
      this.emit(sessionId, 'rate', value)
      if (!session.video) this.syncAudioPlaybackState(sessionId, undefined, undefined, undefined, value)
    })
    player.on('error', (error: Error) => {
      const message = this.errorMessage(error)
      Log.e(MgReadOhosMediaPlugin.TAG, `player_error session=${sessionId} message=`, message)
      this.emit(sessionId, 'error', null, message)
    })
    player.on('audioInterrupt', (event: audio.InterruptEvent) => {
      const shared = event.forceType === audio.InterruptForceType.INTERRUPT_SHARE
      this.log(`audio_interrupt type=${event.eventType} force=${event.forceType} hint=${event.hintType} shared=${shared}`)
      // Huawei documents INTERRUPT_SHARE as an advisory event: the system
      // does not perform the pause/stop operation and the application chooses
      // how to proceed. A notification sound must not pause spoken audio or
      // stop its continuous task. A forced DUCK/MUTE event is also not a
      // pause: Huawei supplies those hints for volume/mute handling while the
      // renderer remains active. Only forced PAUSE/STOP enters the existing
      // interruption recovery path.
      if (shared) return
      const pauseOrStop = event.hintType === audio.InterruptHint.INTERRUPT_HINT_PAUSE ||
        event.hintType === audio.InterruptHint.INTERRUPT_HINT_STOP
      const isBegin = event.eventType === audio.InterruptType.INTERRUPT_TYPE_BEGIN
      if (isBegin && pauseOrStop) {
        this.beginAudioInterruption(sessionId, player)
      } else if (!isBegin && this.audioInterruptionActive) {
        this.endAudioInterruption(sessionId, player)
      }
    })
  }

  private handleAudioSessionState(sessionId: string, event: audio.AudioSessionStateChangedEvent): void {
    const session = this.sessions.get(sessionId)
    if (session === undefined) return
    switch (event.stateChangeHint) {
      case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_PAUSE:
      case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_STOP:
      case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_TIME_OUT_STOP:
        this.beginAudioInterruption(sessionId, session.player)
        break
      case audio.AudioSessionStateChangeHint.AUDIO_SESSION_STATE_CHANGE_HINT_RESUME:
        this.endAudioInterruption(sessionId, session.player)
        break
      default:
        break
    }
  }

  private beginAudioInterruption(sessionId: string, player: media.AVPlayer): void {
    if (this.audioInterruptionActive) return
    this.audioInterruptionActive = true
    this.audioWasPlayingBeforeInterrupt = player.state === 'playing'
    if (this.audioWasPlayingBeforeInterrupt) {
      player.pause()
        .then(() => this.audioBackgroundTask.stop())
        .catch((error: Error) => this.emit(sessionId, 'error', null, `audio_interrupt_pause_failed: ${this.errorMessage(error)}`))
    }
    this.emit(sessionId, 'interrupted', true)
  }

  private endAudioInterruption(sessionId: string, player: media.AVPlayer): void {
    if (!this.audioInterruptionActive) return
    this.audioInterruptionActive = false
    const resume = this.audioWasPlayingBeforeInterrupt
    this.audioWasPlayingBeforeInterrupt = false
    if (resume) {
      const session = this.sessions.get(sessionId)
      if (session !== undefined) {
        this.playSession(sessionId, session)
          .catch((error: Error) => this.emit(sessionId, 'error', null, `audio_interrupt_resume_failed: ${this.errorMessage(error)}`))
      }
    }
    this.emit(sessionId, 'interrupted', false)
  }

  private run(args: Map<string, Object> | null, operation: (session: MediaSession) => Promise<void>, result: MethodResult): void {
    const session = this.sessions.get(this.sessionId(args))
    if (session === undefined) {
      result.error('session_unavailable', 'The OHOS media session is not available.', null)
      return
    }
    Promise.resolve().then(() => operation(session)).then(() => result.success(null)).catch((error: Error) => result.error('operation_failed', this.errorMessage(error), null))
  }

  private async playSession(sessionId: string, session: MediaSession): Promise<void> {
    // Some API 26 devices send the interruption begin callback but omit the
    // matching RESUME after a third-party player is paused or force-stopped.
    // An explicit user play is a safe focus reassertion and clears that stale
    // state without claiming that the system sent a recovery event.
    if (this.audioInterruptionActive) {
      this.audioInterruptionActive = false
      this.audioWasPlayingBeforeInterrupt = false
      this.emit(sessionId, 'interrupted', false)
    }
    await this.prepareSession(sessionId, null, session)
    await session.player.play()
    this.log(`play_requested session=${sessionId}`)
    this.log(`surface_playing session=${sessionId}`)
    // HarmonyOS resolves AVPlayer.play() before the asynchronous state change
    // is observable. Do not let Dart issue pause/seek-after-play while the
    // player is still in `prepared`, because OHOS rejects pause in that state.
    await this.waitForState(session.player, 'playing')
    await this.audioBackgroundTask.start()
    this.log(`playing session=${sessionId}`)
  }

  private async pauseSession(sessionId: string, session: MediaSession): Promise<void> {
    // A user pause supersedes any still-pending forced-interruption recovery.
    // Otherwise a delayed RESUME from an earlier notification/call can invoke
    // playSession after this pause and silently restart playback.
    if (this.audioInterruptionActive || this.audioWasPlayingBeforeInterrupt) {
      this.audioInterruptionActive = false
      this.audioWasPlayingBeforeInterrupt = false
      this.emit(sessionId, 'interrupted', false)
    }
    await session.player.pause()
    if (this.audioSessionId === sessionId) await this.audioBackgroundTask.stop()
  }

  private async prepareSession(
    sessionId: string,
    args: Map<string, Object> | null,
    session: MediaSession,
  ): Promise<void> {
    const player = session.player
    if (player.state === 'initialized') {
      this.log(`prepare_start session=${sessionId}`)
      await player.prepare()
      await this.waitForState(player, 'prepared')
      player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT
      this.log(`video_scale session=${sessionId} mode=scaled_aspect state=${player.state}`)
      this.log(`prepared session=${sessionId} durationMs=${player.duration} videoSize=${player.width}x${player.height}`)
      if (session.initialPositionMs > 0) player.seek(session.initialPositionMs)
      if (session.loop) player.loop = true
      // Use the shared interruption unit for every AVPlayer with an audio
      // track, including video, so another app's focus change is observable.
      player.audioInterruptMode = audio.InterruptMode.SHARE_MODE
      await this.prepareAudioSession(sessionId, args, player.duration, session.video ? 'video' : 'audio')
    }
  }

  private log(message: string): void {
    // console.info is not present in the selected HiLog stream on API 26.
    // Flutter's Log bridge is routed through HiLog and remains observable in
    // both debug and release HAPs.
    Log.w(MgReadOhosMediaPlugin.TAG, message)
  }

  private emit(sessionId: string, kind: string, value?: Any, message?: string): void {
    const event: OhosMediaEventPayload = {sessionId, kind}
    if (value !== undefined) event.value = value as boolean | number | null
    if (message !== undefined) event.message = message
    this.events.emit(event)
  }

  private emitVideoSize(sessionId: string, width: number, height: number): void {
    const event: OhosMediaEventPayload = {sessionId, kind: 'videoSize', width, height}
    this.events.emit(event)
  }

  private async disposeSession(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId)
    if (session === undefined) return
    this.sessions.delete(sessionId)
    if (sessionId === this.audioSessionId) {
      await this.audioBackgroundTask.stop()
      await this.destroyAudioSession()
    }
    try {
      await session.player.release()
    } catch (_) {
      // Release is best effort after the session has been removed from the
      // registry; a native cleanup error must not block the next media item.
    } finally {
      this.emit(sessionId, 'released', true)
    }
  }

  private async disposeAll(): Promise<void> {
    const sessionIds = Array.from(this.sessions.keys())
    await Promise.all(sessionIds.map((sessionId) => this.disposeSession(sessionId)))
  }

  private async waitForState(player: media.AVPlayer, expected: media.AVPlayerState): Promise<void> {
    const deadline = Date.now() + 30_000
    while (player.state !== expected) {
      if (player.state === 'error' || player.state === 'released') {
        throw new Error(`avplayer_state_${player.state}`)
      }
      if (Date.now() >= deadline) throw new Error(`avplayer_state_timeout_${expected}`)
      await new Promise<void>((resolve): void => {
        setTimeout((): void => resolve(), 80)
      })
    }
  }

  private sessionId(args: Map<string, Object> | null): string {
    return this.stringValue(args, 'sessionId')
  }

  private number(args: Map<string, Object> | null, name: string): number {
    const value: Object | undefined = args?.get(name)
    return typeof value === 'number' ? value : 0
  }

  private stringValue(args: Map<string, Object> | null, name: string): string {
    const value: Object | undefined = args?.get(name)
    return typeof value === 'string' ? value : ''
  }

  private booleanValue(args: Map<string, Object> | null, name: string): boolean {
    return args?.get(name) === true
  }

  private headers(value: Object | undefined): Record<string, string> {
    const result: Record<string, string> = {}
    if (!(value instanceof Map)) return result
    value.forEach((header: Object, name: string): void => {
      if (typeof name === 'string' && typeof header === 'string') result[name] = header
    })
    return result
  }

  private isHlsUrl(url: string, resourceType: string): boolean {
    if (resourceType === 'hls') return true
    const path = url.split('?', 1)[0].split('#', 1)[0].toLowerCase()
    return path.endsWith('.m3u8')
  }

  private isRuntimeLoopbackUrl(url: string): boolean {
    return url.startsWith('http://127.0.0.1:') || url.startsWith('http://localhost:') || url.startsWith('http://[::1]:')
  }

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }

  private async prepareAudioSession(
    sessionId: string,
    args: Map<string, Object> | null,
    duration: number,
    sessionType: avSession.AVSessionType,
  ): Promise<void> {
    this.audioPlaybackSyncGeneration += 1
    if (this.audioPlaybackSyncTimer !== undefined) {
      clearTimeout(this.audioPlaybackSyncTimer)
      this.audioPlaybackSyncTimer = undefined
    }
    this.audioPlaybackSyncInFlight = false
    this.audioPlaybackSyncPending = false
    this.audioPlaybackSyncLastSentAt = 0
    if (this.context === undefined) {
      throw new Error('avsession_unavailable: The OHOS ability context is not ready.')
    }
    if (this.audioSessionManager === undefined) {
      const manager = audio.getAudioManager().getSessionManager()
      manager.setAudioSessionScene(audio.AudioSessionScene.AUDIO_SESSION_SCENE_MEDIA)
      manager.on('audioSessionStateChanged', (event: audio.AudioSessionStateChangedEvent) => {
        this.handleAudioSessionState(sessionId, event)
      })
      this.audioSessionManager = manager
      try {
        await manager.activateAudioSession({
          // Media playback must remain active while system notification sounds
          // are rendered. The default strategy lets the system pause this
          // session; that pause path stops the audio continuous task and the
          // app is then frozen in the background. Mixing is the documented
          // media-session policy for concurrent audio streams.
          concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS,
        })
      } catch (error) {
        manager.off('audioSessionStateChanged')
        this.audioSessionManager = undefined
        throw new Error(this.errorMessage(error as Object))
      }
    }
    if (this.audioSession === undefined) {
      try {
        const session = await avSession.createAVSession(this.context, 'MgRead', sessionType)
        this.audioSession = session
        session.on('play', () => this.runAudioCommand('play'))
        session.on('pause', () => this.runAudioCommand('pause'))
        session.on('playNext', () => this.emitRemoteCommand('next'))
        session.on('playPrevious', () => this.emitRemoteCommand('previous'))
        session.on('seek', (position: number) => this.runAudioCommand('seek', position))
        await session.activate()
      } catch (error) {
        await this.destroyAudioSession()
        throw new Error(this.errorMessage(error as Object))
      }
    }
    this.audioSessionId = sessionId
    this.audioState = avSession.PlaybackState.PLAYBACK_STATE_PREPARE
    this.audioPosition = 0
    this.audioDuration = duration
    this.audioSpeed = 1
    const metadata: avSession.AVMetadata = {
      assetId: this.stringValue(args, 'trackId') || sessionId,
      title: this.stringValue(args, 'title'),
      artist: this.stringValue(args, 'artist'),
      avQueueName: this.stringValue(args, 'queueTitle'),
      mediaImage: this.stringValue(args, 'artworkUrl'),
      duration,
    }
    await this.audioSession.setAVMetadata(metadata)
    await this.syncAudioPlaybackState(sessionId)
  }

  private syncAudioPlaybackState(
    sessionId: string,
    state?: avSession.PlaybackState,
    position?: number,
    duration?: number,
    speed?: number,
    volume?: number,
  ): void {
    if (this.audioSessionId !== sessionId || this.audioSession === undefined) return
    if (state !== undefined) this.audioState = state
    if (position !== undefined) this.audioPosition = position
    if (duration !== undefined) this.audioDuration = duration
    if (speed !== undefined) this.audioSpeed = speed
    if (volume !== undefined) this.audioVolume = volume
    if (this.audioPlaybackSyncInFlight) {
      this.audioPlaybackSyncPending = true
      return
    }
    this.audioPlaybackSyncPending = true
    this.scheduleAudioPlaybackStateSync(sessionId, this.audioPlaybackSyncGeneration)
  }

  private scheduleAudioPlaybackStateSync(sessionId: string, generation: number): void {
    if (
      generation !== this.audioPlaybackSyncGeneration ||
      this.audioSessionId !== sessionId ||
      this.audioSession === undefined ||
      !this.audioPlaybackSyncPending ||
      this.audioPlaybackSyncTimer !== undefined ||
      this.audioPlaybackSyncInFlight
    ) return
    const elapsed = Date.now() - this.audioPlaybackSyncLastSentAt
    const delay = Math.max(0, MgReadOhosMediaPlugin.AUDIO_PLAYBACK_SYNC_INTERVAL_MS - elapsed)
    this.audioPlaybackSyncTimer = setTimeout((): void => {
      this.audioPlaybackSyncTimer = undefined
      if (
        generation !== this.audioPlaybackSyncGeneration ||
        this.audioSessionId !== sessionId ||
        this.audioSession === undefined ||
        !this.audioPlaybackSyncPending ||
        this.audioPlaybackSyncInFlight
      ) return
      this.audioPlaybackSyncPending = false
      this.audioPlaybackSyncInFlight = true
      this.audioPlaybackSyncLastSentAt = Date.now()
      this.flushAudioPlaybackState(sessionId, generation)
    }, delay)
  }

  private flushAudioPlaybackState(sessionId: string, generation: number): void {
    if (
      generation !== this.audioPlaybackSyncGeneration ||
      this.audioSessionId !== sessionId ||
      this.audioSession === undefined
    ) {
      this.audioPlaybackSyncInFlight = false
      this.audioPlaybackSyncPending = false
      return
    }
    const session = this.audioSession
    session.setAVPlaybackState({
      state: this.audioState,
      speed: this.audioSpeed,
      position: { elapsedTime: this.audioPosition, updateTime: Date.now() },
      duration: this.audioDuration,
      volume: this.audioVolume,
    }).then(() => this.finishAudioPlaybackStateSync(sessionId, generation)).catch((error: Error) => {
      this.emit(sessionId, 'error', null, `avsession_state_failed: ${this.errorMessage(error)}`)
      this.finishAudioPlaybackStateSync(sessionId, generation)
    })
  }

  private finishAudioPlaybackStateSync(sessionId: string, generation: number): void {
    if (generation !== this.audioPlaybackSyncGeneration) return
    this.audioPlaybackSyncInFlight = false
    if (!this.audioPlaybackSyncPending) return
    this.scheduleAudioPlaybackStateSync(sessionId, generation)
  }

  private playbackState(state: media.AVPlayerState): avSession.PlaybackState | undefined {
    switch (state) {
      case 'playing':
        return avSession.PlaybackState.PLAYBACK_STATE_PLAY
      case 'paused':
        return avSession.PlaybackState.PLAYBACK_STATE_PAUSE
      case 'completed':
        return avSession.PlaybackState.PLAYBACK_STATE_COMPLETED
      case 'stopped':
        return avSession.PlaybackState.PLAYBACK_STATE_STOP
      default:
        return undefined
    }
  }

  private emitRemoteCommand(command: string): void {
    const sessionId = this.audioSessionId
    if (sessionId !== undefined) this.emit(sessionId, 'remoteCommand', command)
  }

  private runAudioCommand(command: string, value?: number): void {
    const sessionId = this.audioSessionId
    const session = sessionId === undefined ? undefined : this.sessions.get(sessionId)
    if (session === undefined) return
    const activeSessionId = sessionId as string
    let operation: Promise<void>
    switch (command) {
      case 'play':
        // A controller can replay a stale PLAY command immediately after
        // Huawei reports COMPLETED. Replaying the same AVPlayer resets the
        // ended item to position zero and preempts the host's next-track
        // recovery. Leave a completed session untouched so the existing
        // queue continuation can select the next chapter.
        if (session.player.state === 'completed') {
          this.log(`command_translated session=${activeSessionId} method=play target=next reason=completed`)
          this.emitRemoteCommand('next')
          return
        }
        operation = this.playSession(activeSessionId, session)
        break
      case 'pause':
        operation = this.pauseSession(activeSessionId, session)
        break
      case 'seek':
        session.player.seek(value ?? 0)
        this.syncAudioPlaybackState(activeSessionId, undefined, value ?? 0)
        operation = Promise.resolve()
        break
      default:
        return
    }
    operation.catch((error: Error) => this.emit(activeSessionId, 'error', null, `avsession_control_failed: ${this.errorMessage(error)}`))
  }

  private async destroyAudioSession(): Promise<void> {
    this.audioPlaybackSyncGeneration += 1
    if (this.audioPlaybackSyncTimer !== undefined) {
      clearTimeout(this.audioPlaybackSyncTimer)
      this.audioPlaybackSyncTimer = undefined
    }
    this.audioPlaybackSyncInFlight = false
    this.audioPlaybackSyncPending = false
    this.audioPlaybackSyncLastSentAt = 0
    await this.audioBackgroundTask.stop()
    const manager = this.audioSessionManager
    const session = this.audioSession
    this.audioSessionManager = undefined
    this.audioSession = undefined
    this.audioSessionId = undefined
    this.audioWasPlayingBeforeInterrupt = false
    this.audioInterruptionActive = false
    if (manager !== undefined) {
      manager.off('audioSessionStateChanged')
      try {
        await manager.deactivateAudioSession()
      } catch (_) {
        // The service may already have released the session during teardown.
      }
    }
    if (session !== undefined) {
      try {
        await session.destroy()
      } catch (_) {
        // AVSession cleanup is best effort after the media registry is closed.
      }
    }
  }

  private waitForVideoSurface(): Promise<string> {
    const current = this.videoSurfaceId
    if (current !== undefined && current.length > 0) return Promise.resolve(current)
    return new Promise<string>((resolve, reject): void => {
      const waiter = (surfaceId: string): void => {
        clearTimeout(timer)
        resolve(surfaceId)
      }
      const timer = setTimeout((): void => {
        const index = this.videoSurfaceWaiters.indexOf(waiter)
        if (index >= 0) this.videoSurfaceWaiters.splice(index, 1)
        reject(new Error('video_surface_unavailable'))
      }, 10_000)
      this.videoSurfaceWaiters.push(waiter)
    })
  }
}
