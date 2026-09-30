
import window from '@ohos.window';
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

export default class EntryAbility extends FlutterAbility {
  /**
   * The FlutterAbility base class applies its default full-screen layout after
   * loading the Flutter page. That changes the XComponent window after the
   * raster surface has been created; on API 26 the old EGL surface then keeps
   * returning false from eglSwapBuffers, so every SurfaceFrame submission
   * fails. Apply the layout before Flutter creates the XComponent and disable
   * the base class's late second transition.
   */
  override isDefaultFullScreen(): boolean {
    return false;
  }

  override onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.getMainWindowSync().setWindowLayoutFullScreen(true);
    super.onWindowStageCreate(windowStage);
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
  }
}
