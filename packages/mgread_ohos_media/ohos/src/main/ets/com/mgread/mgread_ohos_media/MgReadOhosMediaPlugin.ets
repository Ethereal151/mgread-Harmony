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
} from '@ohos/flutter_ohos'
import common from '@ohos.app.ability.common'
import media from '@ohos.multimedia.media'
import audio from '@ohos.multimedia.audio'
import avSession from '@ohos.multimedia.avsession'
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
export default class MgReadOhosMediaPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private methodChannel?: MethodChannel
  private eventChannel?: EventChannel
  private readonly events = new OhosMediaEventStreamHandler()
  private sessions: Map<string, MediaSession> = new Map()
  private textures?: TextureRegistry
  private context?: common.UIAbilityContext
  private audioSession?: avSession.AVSession
  private audioSessionId?: string
  private audioState: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_INITIAL
  private audioPosition = 0
  private audioDuration = 0
  private audioSpeed = 1
  private audioVolume = 1

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

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context as common.UIAbilityContext
  }

  onDetachedFromAbility(): void {
    this.context = undefined
    this.destroyAudioSession()
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.methodChannel?.setMethodCallHandler(null)
    this.eventChannel?.setStreamHandler(null)
    this.methodChannel = undefined
    this.eventChannel = undefined
    this.disposeAll()
    this.destroyAudioSession()
    this.context = undefined
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
        this.disposeSession(this.sessionId(args)).then(() => result.success(null)).catch((error: Error) => {
          result.error('dispose_failed', this.errorMessage(error), null)
        })
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
    try {
      await this.disposeSession(sessionId)
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
      if (!video) await this.prepareAudioSession(sessionId, args, player.duration)
      if (args?.['play'] === true) await player.play()
      result.success({
        sessionId,
        textureId: texture?.getTextureId(),
        durationMs: player.duration,
      })
    } catch (error) {
      await this.disposeSession(sessionId)
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
      if (!session.video) {
        const playbackState = this.playbackState(state)
        if (playbackState !== undefined) this.syncAudioPlaybackState(sessionId, playbackState)
      }
    })
    player.on('timeUpdate', (value: number) => {
      this.emit(sessionId, 'position', value)
      if (!session.video) this.syncAudioPlaybackState(sessionId, undefined, value)
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
      }
    })
    player.on('startRenderFrame', () => this.emit(sessionId, 'firstFrame', true))
    player.on('endOfStream', () => this.emit(sessionId, 'completed', true))
    player.on('volumeChange', (value: number) => {
      this.emit(sessionId, 'volume', value)
      if (!session.video) this.syncAudioPlaybackState(sessionId, undefined, undefined, undefined, undefined, value)
    })
    player.on('playbackRateDone', (value: number) => {
      this.emit(sessionId, 'rate', value)
      if (!session.video) this.syncAudioPlaybackState(sessionId, undefined, undefined, undefined, value)
    })
    player.on('error', (error: Error) => this.emit(sessionId, 'error', null, this.errorMessage(error)))
    player.on('audioInterrupt', (event: audio.InterruptEvent) => {
      this.emit(sessionId, 'interrupted', event.eventType === audio.InterruptType.INTERRUPT_TYPE_BEGIN)
    })
  }

  private run(args: Record<string, Any> | null, operation: (session: MediaSession) => Promise<void>, result: MethodResult): void {
    const session = this.sessions.get(this.sessionId(args))
    if (session === undefined) {
      result.error('session_unavailable', 'The OHOS media session is not available.', null)
      return
    }
    Promise.resolve().then(() => operation(session)).then(() => result.success(null)).catch((error: Error) => result.error('operation_failed', this.errorMessage(error), null))
  }

  private emit(sessionId: string, kind: string, value?: Any, message?: string): void {
    const event: OhosMediaEventPayload = {sessionId, kind}
    if (value !== undefined) event.value = value as boolean | number | null
    if (message !== undefined) event.message = message
    this.events.emit(event)
  }

  private async disposeSession(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId)
    if (session === undefined) return
    this.sessions.delete(sessionId)
    if (sessionId === this.audioSessionId) this.audioSessionId = undefined
    try {
      await session.player.release()
    } catch (_) {
      // Release is best effort after the session has been removed from the
      // registry; a native cleanup error must not block the next media item.
    } finally {
      session.texture?.release()
    }
  }

  private async disposeAll(): Promise<void> {
    const sessionIds = Array.from(this.sessions.keys())
    await Promise.all(sessionIds.map((sessionId) => this.disposeSession(sessionId)))
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

  private async prepareAudioSession(
    sessionId: string,
    args: Record<string, Any> | null,
    duration: number,
  ): Promise<void> {
    if (this.context === undefined) {
      throw new Error('avsession_unavailable: The OHOS ability context is not ready.')
    }
    if (this.audioSession === undefined) {
      const session = await avSession.createAVSession(this.context, 'MgRead', 'audio')
      session.on('play', () => this.runAudioCommand('play'))
      session.on('pause', () => this.runAudioCommand('pause'))
      session.on('playNext', () => this.emitRemoteCommand('next'))
      session.on('playPrevious', () => this.emitRemoteCommand('previous'))
      session.on('seek', (position: number) => this.runAudioCommand('seek', position))
      await session.activate()
      this.audioSession = session
    }
    this.audioSessionId = sessionId
    this.audioState = avSession.PlaybackState.PLAYBACK_STATE_PREPARE
    this.audioPosition = 0
    this.audioDuration = duration
    this.audioSpeed = 1
    const metadata: avSession.AVMetadata = {
      assetId: (args?.['trackId'] as string | undefined) ?? sessionId,
      title: args?.['title'] as string | undefined,
      artist: args?.['artist'] as string | undefined,
      avQueueName: args?.['queueTitle'] as string | undefined,
      mediaImage: args?.['artworkUrl'] as string | undefined,
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
    this.audioSession.setAVPlaybackState({
      state: this.audioState,
      speed: this.audioSpeed,
      position: { elapsedTime: this.audioPosition, updateTime: Date.now() },
      duration: this.audioDuration,
      volume: this.audioVolume,
    }).catch((error: Error) => {
      this.emit(sessionId, 'error', null, `avsession_state_failed: ${this.errorMessage(error)}`)
    })
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
        operation = session.player.play()
        break
      case 'pause':
        operation = session.player.pause()
        break
      case 'seek':
        session.player.seek(value ?? 0)
        operation = Promise.resolve()
        break
      default:
        return
    }
    operation.catch((error: Error) => this.emit(activeSessionId, 'error', null, `avsession_control_failed: ${this.errorMessage(error)}`))
  }

  private destroyAudioSession(): void {
    const session = this.audioSession
    this.audioSession = undefined
    this.audioSessionId = undefined
    if (session !== undefined) session.destroy().catch(() => {})
  }
}
