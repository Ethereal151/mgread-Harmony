import { Any, EventSink, StreamHandler } from '@ohos/flutter_ohos'

export default class OhosMediaEventStreamHandler implements StreamHandler {
  private sink: EventSink | null = null
  private pending: Array<Record<string, Any>> = []

  onListen(args: Any, events: EventSink): void {
    this.sink = events
    const pending = this.pending
    this.pending = []
    pending.forEach((event: Record<string, Any>): void => {
      events.success(event)
    })
  }

  onCancel(args: Any): void {
    this.sink = null
  }

  emit(event: Record<string, Any>): void {
    if (this.sink !== null) {
      this.sink.success(event)
      return
    }
    // The native player can emit initialized/prepared/first-frame events
    // before Dart has finished attaching the broadcast EventChannel. Keep a
    // bounded startup queue so those lifecycle events are not lost.
    if (this.pending.length >= 128) this.pending.shift()
    this.pending.push(event)
  }
}
