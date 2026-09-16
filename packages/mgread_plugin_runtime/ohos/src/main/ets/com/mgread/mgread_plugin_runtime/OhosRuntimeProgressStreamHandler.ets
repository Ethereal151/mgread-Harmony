import { Any } from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';

/** Bridges Node host progress events to Flutter's broadcast stream. */
export default class OhosRuntimeProgressStreamHandler implements StreamHandler {
  private eventSink: EventSink | null = null

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events
  }

  onCancel(args: Any): void {
    this.eventSink = null
  }

  emit(value: Any): void {
    this.eventSink?.success(value)
  }
}
