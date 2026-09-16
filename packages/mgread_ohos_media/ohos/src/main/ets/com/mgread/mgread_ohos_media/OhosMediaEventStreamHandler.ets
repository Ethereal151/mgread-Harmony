import { Any, EventSink, StreamHandler } from '@ohos/flutter_ohos'

export default class OhosMediaEventStreamHandler implements StreamHandler {
  private sink: EventSink | null = null

  onListen(args: Any, events: EventSink): void {
    this.sink = events
  }

  onCancel(args: Any): void {
    this.sink = null
  }

  emit(event: Record<string, Any>): void {
    this.sink?.success(event)
  }
}
