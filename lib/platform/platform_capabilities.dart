/// Cross-platform capabilities owned by the application composition root.
///
/// This boundary keeps OHOS sandbox and plugin-availability decisions out of
/// feature pages. It is intentionally a small, synchronous description of
/// platform support; IO remains owned by the feature that requested it.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The platform services that the current Flutter host can safely use.
final class PlatformCapabilities {
  PlatformCapabilities._(this.operatingSystem);

  /// Creates a capability description for tests without consulting plugins.
  @pragma('vm:prefer-inline')
  factory PlatformCapabilities.forOperatingSystem(String operatingSystem) => PlatformCapabilities._(operatingSystem);

  /// The current process platform, normalized by `dart:io`.
  factory PlatformCapabilities.current() => PlatformCapabilities._(Platform.operatingSystem);

  final String operatingSystem;

  bool get isOhos => operatingSystem == 'ohos';
  bool get isAndroid => operatingSystem == 'android';
  bool get isWindows => operatingSystem == 'windows';
  bool get isMacOS => operatingSystem == 'macos';

  /// OHOS file selection is not yet registered in the application plugin graph.
  /// Android selection is provided by the Runtime host, not this flag.
  bool get supportsFilePicker => !isOhos && !isAndroid;

  /// `share_plus` and `path_provider` do not currently have an OHOS adapter in
  /// the resolved plugin graph.
  bool get supportsSharing => !isOhos;
  bool get supportsPackageInfo => !isOhos;
  bool get supportsExternalUrls => !isOhos;

  /// OHOS exposes an application-window brightness override through
  /// `@ohos.window`; global system brightness remains unavailable.
  bool get supportsApplicationBrightness => isAndroid || isOhos;
  bool get supportsKeepScreenOn => isAndroid || isWindows || isMacOS || isOhos;
  bool get supportsWindowManagement => isWindows;

  /// Audio and video are provided by the package-owned OHOS AVPlayer bridge.
  bool get supportsAudioPlayback => true;
  bool get supportsVideoPlayback => true;
  bool get supportsBarcodeScanning => true;

  /// Whether the Flutter Runtime bridge is registered.
  bool get supportsPluginRuntime => isAndroid || isWindows || isMacOS || isOhos;

  /// Whether a verified executable/embedded Node host is available. The x64
  /// emulator intentionally uses the native stub; arm64 is enabled only after
  /// the real-device smoke gate.
  bool get supportsPluginRuntimeNode => isAndroid || isWindows || isMacOS;

  /// Resolves the app-owned persistence directory.
  ///
  /// The OHOS path is inside the application EL2 sandbox and survives normal
  /// HAP updates. Other platforms continue to use the platform provider.
  Future<Directory> resolvePersistenceRoot() async {
    if (isOhos) {
      return Directory('/data/storage/el2/base/haps/entry/files/persistence');
    }
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}persistence');
  }
}

final PlatformCapabilities platformCapabilities = PlatformCapabilities.current();
