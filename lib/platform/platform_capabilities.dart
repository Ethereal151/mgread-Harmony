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

  /// OHOS currently has no registered `file_selector` implementation in this
  /// app. Android selection is provided by the Runtime host, not this flag.
  bool get supportsFilePicker => !isOhos && !isAndroid;

  /// `share_plus` and `path_provider` do not currently have an OHOS adapter in
  /// the resolved plugin graph.
  bool get supportsSharing => !isOhos;
  bool get supportsPackageInfo => !isOhos;
  bool get supportsExternalUrls => !isOhos;

  /// OHOS exposes an application-window brightness override through
  /// `@ohos.window`; global system brightness remains unavailable.
  bool get supportsApplicationBrightness => isAndroid || isOhos;
  bool get supportsKeepScreenOn => isAndroid || isWindows || isMacOS;
  bool get supportsWindowManagement => isWindows;

  /// Audio and video are provided by the package-owned OHOS AVPlayer bridge.
  bool get supportsAudioPlayback => true;
  bool get supportsVideoPlayback => true;
  bool get supportsBarcodeScanning => !isOhos;

  /// Node 24.16.0 is not bundled for OHOS arm64 yet. The Runtime facade still
  /// exposes a typed host boundary, but the capability remains unavailable.
  /// Whether the Flutter bridge is registered. OHOS returns true because the
  /// staged bridge provides a typed unsupported result instead of a missing
  /// plugin/channel failure.
  bool get supportsPluginRuntime => isAndroid || isWindows || isMacOS || isOhos;

  /// Whether a verified executable/embedded Node host is available.
  bool get supportsPluginRuntimeNode => isAndroid || isWindows || isMacOS;

  /// Resolves the app-owned persistence directory.
  ///
  /// The OHOS path is inside the application EL2 sandbox and survives normal
  /// HAP updates. Other platforms continue to use the platform provider.
  Future<Directory> resolvePersistenceRoot() async {
    if (isOhos) {
      return Directory('/data/storage/el2/base/files/persistence');
    }
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}persistence');
  }
}

final PlatformCapabilities platformCapabilities = PlatformCapabilities.current();
