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

  private async open(args: Map<string, Object> | null, video: boolean, result: MethodResult): Promise<void> {
    const sessionId = this.sessionId(args)
    const url = this.stringValue(args, 'url')
    if (sessionId.length === 0 || url.length === 0) {
      result.error('invalid_argument', 'A sessionId and URL are required.', null)
      return
    }
    try {
      await this.disposeSession(sessionId)
      const player = await media.createAVPlayer()
      // The OHOS Flutter engine's deprecated createSurfaceTexture() path
      // creates an entry without registering a native surface (surfaceId is
      // left at 0). AVPlayer can prepare successfully against that value but
      // never receives a render target. Register an explicit texture so the
      // engine supplies both the Flutter texture id and a real surface id.
      const texture = video ? this.createVideoTexture() : undefined
      if (video && texture === undefined) {
        await player.release()
        result.error('surface_unavailable', 'The OHOS texture registry is unavailable.', null)
        return
      }
      const headers = this.headers(args?.get('headers'))
      const source = media.createMediaSourceWithUrl(url, headers)
      const session: MediaSession = {player, texture, video}
      this.sessions.set(sessionId, session)
      this.bind(sessionId, session)
      await player.setMediaSource(source)
      await this.waitForState(player, 'initialized')
      if (texture !== undefined) player.surfaceId = String(texture.getSurfaceId())
      await player.prepare()
      await this.waitForState(player, 'prepared')
      const initialPosition = this.number(args, 'initialPositionMs')
      if (initialPosition > 0) player.seek(initialPosition)
      if (!video) await this.prepareAudioSession(sessionId, args, player.duration)
      if (this.booleanValue(args, 'play')) await player.play()
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

  private createVideoTexture(): SurfaceTextureEntry | undefined {
    if (this.textures === undefined) return undefined
    const textureId = this.textures.getTextureId()
    return this.textures.registerTexture(textureId)
  }

  private bind(sessionId: string, session: MediaSession): void {
    const player = session.player
    player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason) => {
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
      } else if (kind === media.BufferingInfoType.BUFFERING_PERCENT) {
        this.emit(sessionId, 'bufferingPercent', value)
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

  private run(args: Map<string, Object> | null, operation: (session: MediaSession) => Promise<void>, result: MethodResult): void {
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
    if (sessionId === this.audioSessionId) this.destroyAudioSession()
    try {
      await session.player.release()
    } catch (_) {
      // Release is best effort after the session has been removed from the
      // registry; a native cleanup error must not block the next media item.
    } finally {
      session.texture?.release()
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

  private errorMessage(error: Object): string {
    return String((error as Record<string, Any>)['message'] ?? error)
  }

  private async prepareAudioSession(
    sessionId: string,
    args: Map<string, Object> | null,
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
