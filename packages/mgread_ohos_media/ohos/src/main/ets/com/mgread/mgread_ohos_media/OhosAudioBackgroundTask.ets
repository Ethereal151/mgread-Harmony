/**
 * HarmonyOS continuous-task owner for the native audio session.
 *
 * AVSession exposes transport controls but does not keep the application
 * process runnable. The official audioPlayback continuous task is acquired
 * only after AVPlayer reaches `playing` and released on pause or teardown.
 */
import common from '@ohos.app.ability.common'
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager'
import wantAgent, { WantAgent } from '@ohos.wantAgent'
import { Log } from '@ohos/flutter_ohos'

export default class OhosAudioBackgroundTask {
  private static readonly TAG = 'MgReadOhosMedia'
  private context?: common.UIAbilityContext
  private running = false
  private tail: Promise<void> = Promise.resolve()
  private wantAgent?: WantAgent

  attach(context: common.UIAbilityContext): void {
    this.context = context
  }

  detach(): void {
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
        Log.w(OhosAudioBackgroundTask.TAG, `background_task_start_failed message=${String(error)}`)
      }
    })
  }

  async stop(): Promise<void> {
    await this.enqueue(async (): Promise<void> => {
      if (!this.running) return
      const context = this.context
      if (context === undefined) return
      try {
        await backgroundTaskManager.stopBackgroundRunning(context)
        this.running = false
        Log.w(OhosAudioBackgroundTask.TAG, 'background_task_stopped')
      } catch (error) {
        Log.w(OhosAudioBackgroundTask.TAG, `background_task_stop_failed message=${String(error)}`)
      }
    })
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.tail.then(operation)
    this.tail = next.catch(() => {})
    return next
  }
}
