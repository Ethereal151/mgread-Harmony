import { Any, EventSink, StreamHandler } from '@ohos/flutter_ohos'

/** Bounded bridge for Network Kit availability transitions. */
export default class OhosNetworkEventStreamHandler implements StreamHandler {
  private sink: EventSink | null = null

  onListen(args: Any, events: EventSink): void {
    this.sink = events
  }

  onCancel(args: Any): void {
    this.sink = null
  }

  emit(available: boolean): void {
    this.sink?.success(available)
  }
}
