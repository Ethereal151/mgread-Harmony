import {
  Any,
  EventChannel,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos'
import media from '@ohos.multimedia.media'
import { SurfaceTextureEntry, TextureRegistry } from '@ohos/flutter_ohos'
import OhosMediaEventStreamHandler from './OhosMediaEventStreamHandler'

interface MediaSession {
  player: media.AVPlayer
  texture?: SurfaceTextureEntry
  video: boolean
}

interface OhosMediaEventPayload {
  sessionId: string
  kind: string
  value?: boolean | number | null
  message?: string
}

/** Native AVPlayer owner for OHOS audio and video sessions. */
export default class MgReadOhosMediaPlugin implements FlutterPlugin, MethodCallHandler {
  private methodChannel?: MethodChannel
  private eventChannel?: EventChannel
  private readonly events = new OhosMediaEventStreamHandler()
  private sessions: Map<string, MediaSession> = new Map()
  private textures?: TextureRegistry

  getUniqueClassName(): string {
    return 'MgReadOhosMediaPlugin'
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.textures = binding.getTextureRegistry()
    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), 'mgread/ohos_media')
    this.methodChannel.setMethodCallHandler(this)
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'mgread/ohos_media/events')
    this.eventChannel.setStreamHandler(this.events)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.methodChannel?.setMethodCallHandler(null)
    this.eventChannel?.setStreamHandler(null)
    this.methodChannel = undefined
    this.eventChannel = undefined
    this.disposeAll()
    this.textures = undefined
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const args = call.args as Record<string, Any> | null
    switch (call.method) {
      case 'audio.open':
        this.open(args, false, result)
        break
      case 'video.open':
        this.open(args, true, result)
        break
      case 'dispose':
        this.disposeSession(this.sessionId(args))
        result.success(null)
        break
      case 'play':
        this.run(args, (session) => session.player.play(), result)
        break
      case 'pause':
        this.run(args, (session) => session.player.pause(), result)
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

  private async open(args: Record<string, Any> | null, video: boolean, result: MethodResult): Promise<void> {
    const sessionId = this.sessionId(args)
    const url = args?.['url'] as string | undefined
    if (sessionId.length === 0 || url === undefined || url.length === 0) {
      result.error('invalid_argument', 'A sessionId and URL are required.', null)
      return
    }
    this.disposeSession(sessionId)
    try {
      const player = await media.createAVPlayer()
      const texture = video ? this.textures?.createSurfaceTexture() : undefined
      if (video && texture === undefined) {
        await player.release()
        result.error('surface_unavailable', 'The OHOS texture registry is unavailable.', null)
        return
      }
      if (texture !== undefined) player.surfaceId = String(texture.getSurfaceId())
      const headers = (args?.['headers'] as Record<string, string> | undefined) ?? {}
      const source = media.createMediaSourceWithUrl(url, headers)
      const session: MediaSession = {player, texture, video}
      this.sessions.set(sessionId, session)
      this.bind(sessionId, session)
      await player.setMediaSource(source)
      await player.prepare()
      const initialPosition = this.number(args, 'initialPositionMs')
      if (initialPosition > 0) player.seek(initialPosition)
      if (args?.['play'] === true) await player.play()
      result.success({
        sessionId,
        textureId: texture?.getTextureId(),
        durationMs: player.duration,
      })
    } catch (error) {
      this.disposeSession(sessionId)
      result.error('open_failed', this.errorMessage(error), null)
    }
  }

  private bind(sessionId: string, session: MediaSession): void {
    const player = session.player
    player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => {
      this.emit(sessionId, 'state', state)
      if (state === 'playing') this.emit(sessionId, 'playing', true)
      if (state === 'paused' || state === 'completed' || state === 'stopped') this.emit(sessionId, 'playing', false)
      if (state === 'completed') this.emit(sessionId, 'completed', true)
    })
    player.on('timeUpdate', (value: number) => this.emit(sessionId, 'position', value))
    player.on('durationUpdate', (value: number) => this.emit(sessionId, 'duration', value))
    player.on('bufferingUpdate', (kind: media.BufferingInfoType, value: number) => {
      if (kind === media.BufferingInfoType.BUFFERING_START) {
        this.emit(sessionId, 'buffering', true)
      } else if (kind === media.BufferingInfoType.BUFFERING_END) {
        this.emit(sessionId, 'buffering', false)
      }
    })
    player.on('startRenderFrame', () => this.emit(sessionId, 'firstFrame', true))
    player.on('endOfStream', () => this.emit(sessionId, 'completed', true))
    player.on('volumeChange', (value: number) => this.emit(sessionId, 'volume', value))
    player.on('playbackRateDone', (value: number) => this.emit(sessionId, 'rate', value))
    player.on('error', (error: Error) => this.emit(sessionId, 'error', null, this.errorMessage(error)))
  }

  private run(args: Record<string, Any> | null, operation: (session: MediaSession) => Promise<void>, result: MethodResult): void {
    const session = this.sessions.get(this.sessionId(args))
    if (session === undefined) {
      result.error('session_unavailable', 'The OHOS media session is not available.', null)
      return
    }
    operation(session).then(() => result.success(null)).catch((error: Error) => result.error('operation_failed', this.errorMessage(error), null))
  }

  private emit(sessionId: string, kind: string, value?: Any, message?: string): void {
    const event: OhosMediaEventPayload = {sessionId, kind}
    if (value !== undefined) event.value = value as boolean | number | null
    if (message !== undefined) event.message = message
    this.events.emit(event)
  }

  private disposeSession(sessionId: string): void {
    const session = this.sessions.get(sessionId)
    if (session === undefined) return
    this.sessions.delete(sessionId)
    session.texture?.release()
    session.player.release().catch(() => {})
  }

  private disposeAll(): void {
    for (const sessionId of this.sessions.keys()) this.disposeSession(sessionId)
  }

  private sessionId(args: Record<string, Any> | null): string {
    return args?.['sessionId'] as string ?? ''
  }

  private number(args: Record<string, Any> | null, name: string): number {
    const value: number | undefined = args?.[name] as number | undefined
    return value ?? 0
  }

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }
}
