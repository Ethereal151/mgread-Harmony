/**
 * HarmonyOS continuous-task owner for the native audio session.
 *
 * AVSession exposes transport controls but does not keep the application
 * process runnable or authorize a background media stream by itself. The
 * audioPlayback continuous task is acquired only after AVPlayer reaches
 * `playing` and released on pause or teardown. Network data transfer is not a
 * keepalive mode: HarmonyOS cancels that mode when its progress is not updated
 * for more than ten minutes.
 */
import common from '@ohos.app.ability.common'
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager'
import wantAgent, { WantAgent } from '@ohos.wantAgent'
import { Log } from '@ohos/flutter_ohos'

interface BackgroundTaskError {
  code?: number
  message?: string
}

export default class OhosAudioBackgroundTask {
  private static readonly TAG = 'MgReadOhosMedia'
  private context?: common.UIAbilityContext
  private running = false
  private tail: Promise<void> = Promise.resolve()
  private wantAgent?: WantAgent
  private continuousTaskId?: number
  private listenersRegistered = false

  private readonly onTaskCancel = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (this.continuousTaskId === undefined || info.id === this.continuousTaskId) {
      this.running = false
      this.continuousTaskId = undefined
    }
    Log.w(OhosAudioBackgroundTask.TAG, `background_task_cancelled id=${info.id} reason=${info.reason}`)
  }

  private readonly onTaskSuspend = (info: backgroundTaskManager.ContinuousTaskSuspendInfo): void => {
    // Suspend does not cancel the registered continuous task. Keeping the
    // registration prevents the next chapter from calling
    // startBackgroundRunning again and triggering OHOS 9800005.
    Log.w(OhosAudioBackgroundTask.TAG, `background_task_suspended id=${info.continuousTaskId} reason=${info.suspendReason}`)
  }

  private readonly onTaskActive = (info: backgroundTaskManager.ContinuousTaskActiveInfo): void => {
    this.continuousTaskId = info.id
    if (this.continuousTaskId === undefined || info.id === this.continuousTaskId) {
      this.running = true
    }
    Log.w(OhosAudioBackgroundTask.TAG, `background_task_active id=${info.id}`)
  }

  attach(context: common.UIAbilityContext): void {
    this.context = context
    if (this.listenersRegistered) return
    backgroundTaskManager.on('continuousTaskCancel', this.onTaskCancel)
    backgroundTaskManager.on('continuousTaskSuspend', this.onTaskSuspend)
    backgroundTaskManager.on('continuousTaskActive', this.onTaskActive)
    this.listenersRegistered = true
  }

  detach(): void {
    if (this.listenersRegistered) {
      backgroundTaskManager.off('continuousTaskCancel', this.onTaskCancel)
      backgroundTaskManager.off('continuousTaskSuspend', this.onTaskSuspend)
      backgroundTaskManager.off('continuousTaskActive', this.onTaskActive)
      this.listenersRegistered = false
    }
    this.context = undefined
    this.wantAgent = undefined
  }

  async start(): Promise<void> {
    await this.enqueue(async (): Promise<void> => {
      if (this.running) return
      const context = this.context
      if (context === undefined) {
        Log.w(OhosAudioBackgroundTask.TAG, 'background_task_start_skipped context_unavailable')
        return
      }
      try {
        const agent = this.wantAgent ??= await wantAgent.getWantAgent({
          wants: [{
            bundleName: context.abilityInfo.bundleName,
            abilityName: context.abilityInfo.name,
          }],
          operationType: wantAgent.OperationType.START_ABILITY,
          requestCode: 0,
          wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
        })
        await backgroundTaskManager.startBackgroundRunning(
          context,
          backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
          agent,
        )
        this.running = true
        Log.w(OhosAudioBackgroundTask.TAG, 'background_task_started mode=audioPlayback')
      } catch (error) {
        Log.w(OhosAudioBackgroundTask.TAG, `background_task_start_failed ${this.errorMessage(error)}`)
      }
    })
  }

  async stop(): Promise<void> {
    await this.enqueue(async (): Promise<void> => {
      if (!this.running && this.continuousTaskId === undefined) return
      const context = this.context
      if (context === undefined) return
      try {
        await backgroundTaskManager.stopBackgroundRunning(context)
        this.running = false
        this.continuousTaskId = undefined
        Log.w(OhosAudioBackgroundTask.TAG, 'background_task_stopped')
      } catch (error) {
        Log.w(OhosAudioBackgroundTask.TAG, `background_task_stop_failed ${this.errorMessage(error)}`)
      }
    })
  }

  private errorMessage(error: Object): string {
    const businessError = error as BackgroundTaskError
    const code = businessError.code === undefined ? 'unknown' : businessError.code
    const message = businessError.message ?? String(error)
    return `code=${code} message=${message}`
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.tail.then(operation)
    this.tail = next.catch(() => {})
    return next
  }
}
