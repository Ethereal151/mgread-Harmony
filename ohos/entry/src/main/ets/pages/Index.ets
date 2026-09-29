
import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";

  build() {
    Column() {
      // This ability is a single full-screen Flutter surface. ArkUI can
      // briefly report a zero visible ratio while applying safe-area or
      // full-screen changes; pausing Flutter for that transient callback
      // leaves the XComponent skipped even though the window is visible.
      FlutterPage({
        viewId: this.viewId,
        shouldPauseWhenInvisible: false,
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
