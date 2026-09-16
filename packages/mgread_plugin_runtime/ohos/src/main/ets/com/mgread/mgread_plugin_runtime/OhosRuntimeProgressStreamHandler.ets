import { Any } from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';

/** Keeps the progress channel ready for the future Node host implementation. */
export default class OhosRuntimeProgressStreamHandler implements StreamHandler {
  private eventSink: EventSink | null = null

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events
  }

  onCancel(args: Any): void {
    this.eventSink = null
  }
}
