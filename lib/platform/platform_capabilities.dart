/// Cross-platform capabilities owned by the application composition root.
///
/// This boundary keeps OHOS sandbox and plugin-availability decisions out of
/// feature pages. It is intentionally a small, synchronous description of
/// platform support; IO remains owned by the feature that requested it.
library;

import 'dart:io';

import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mgread_ohos_system/mgread_ohos_system.dart';

/// Immutable result of one native OHOS capability probe.
final class OhosCapability {
  const OhosCapability({required this.available, required this.reason, required this.apiVersion, required this.architecture});

  final bool available;
  final String reason;
  final String apiVersion;
  final String architecture;

  factory OhosCapability.unavailable(String reason) =>
      OhosCapability(available: false, reason: reason, apiVersion: 'unknown', architecture: 'unknown');
}

/// Native OHOS probes used by feature entry points and diagnostics.
final class OhosCapabilitySnapshot {
  const OhosCapabilitySnapshot({
    required this.supportsOhosRuntime,
    required this.supportsOhosWebView,
    required this.supportsOhosBackgroundAudio,
    required this.supportsOhosAppUpdate,
    required this.supportsOhosNetworkEvents,
  });

  factory OhosCapabilitySnapshot.unavailable(String reason) => OhosCapabilitySnapshot(
    supportsOhosRuntime: OhosCapability.unavailable(reason),
    supportsOhosWebView: OhosCapability.unavailable(reason),
    supportsOhosBackgroundAudio: OhosCapability.unavailable(reason),
    supportsOhosAppUpdate: OhosCapability.unavailable(reason),
    supportsOhosNetworkEvents: OhosCapability.unavailable(reason),
  );

  final OhosCapability supportsOhosRuntime;
  final OhosCapability supportsOhosWebView;
  final OhosCapability supportsOhosBackgroundAudio;
  final OhosCapability supportsOhosAppUpdate;
  final OhosCapability supportsOhosNetworkEvents;

  OhosCapability operator [](String name) => switch (name) {
    'supportsOhosRuntime' => supportsOhosRuntime,
    'supportsOhosWebView' => supportsOhosWebView,
    'supportsOhosBackgroundAudio' => supportsOhosBackgroundAudio,
    'supportsOhosAppUpdate' => supportsOhosAppUpdate,
    'supportsOhosNetworkEvents' => supportsOhosNetworkEvents,
    _ => throw ArgumentError.value(name, 'name', 'Unknown OHOS capability'),
  };
}

/// Product-facing OHOS feature gates.  A gate is deliberately separate from
/// the native probe above: a native API may exist while its semantics are not
/// strong enough for MgRead's public contract.
enum OhosPlatformCapability {
  sourceHttpTransport,
  webViewProfileIsolation,
  webViewCancellation,
  sourceSystemProxy,
  playerHttpProxy,
  videoBufferedPosition,
  videoEnhancement,
  systemVolume,
  readerVolumeKeys,
}

/// The platform services that the current Flutter host can safely use.
final class PlatformCapabilities {
  PlatformCapabilities._(this.operatingSystem);

  /// Creates a capability description for tests without consulting plugins.
  @pragma('vm:prefer-inline')
  factory PlatformCapabilities.forOperatingSystem(String operatingSystem) => PlatformCapabilities._(operatingSystem);

  /// The current process platform, normalized by `dart:io`.
  factory PlatformCapabilities.current() => PlatformCapabilities._(Platform.operatingSystem);

  final String operatingSystem;
  Future<OhosCapabilitySnapshot>? _probeFuture;

  bool get isOhos => operatingSystem == 'ohos';
  bool get isAndroid => operatingSystem == 'android';
  bool get isWindows => operatingSystem == 'windows';
  bool get isMacOS => operatingSystem == 'macos';

  /// OHOS selection and export use the application-owned DocumentViewPicker
  /// bridge. Android selection is provided by the Runtime host, not this flag.
  bool get supportsFilePicker => !isAndroid;

  /// OHOS sharing uses a URI-granting implicit Want; other platforms keep their
  /// existing share_plus implementation.
  bool get supportsSharing => true;
  bool get supportsPackageInfo => true;
  bool get supportsExternalUrls => true;

  /// OHOS exposes an application-window brightness override through
  /// `@ohos.window`; global system brightness remains unavailable.
  bool get supportsApplicationBrightness => isAndroid || isOhos;
  bool get supportsKeepScreenOn => isAndroid || isWindows || isMacOS || isOhos;
  bool get supportsWindowManagement => isWindows;

  /// Audio and video are provided by the package-owned OHOS AVPlayer bridge.
  bool get supportsAudioPlayback => true;
  bool get supportsVideoPlayback => true;
  bool get supportsBarcodeScanning => true;

  /// OHOS capabilities whose UI and public actions must agree with the
  /// implementation.  Unsupported entries are intentionally explicit rather
  /// than inferred from plugin registration.
  bool supportsOhosCapability(OhosPlatformCapability capability) {
    if (!isOhos) return true;
    return switch (capability) {
      OhosPlatformCapability.sourceHttpTransport => true,
      OhosPlatformCapability.webViewProfileIsolation => false,
      OhosPlatformCapability.webViewCancellation => true,
      OhosPlatformCapability.sourceSystemProxy => true,
      // AVPlayer has no supported per-session HTTP proxy contract on OHOS.
      OhosPlatformCapability.playerHttpProxy => false,
      // AVPlayer exposes BufferingInfoType.CACHED_DURATION in milliseconds.
      OhosPlatformCapability.videoBufferedPosition => true,
      OhosPlatformCapability.videoEnhancement => false,
      // HarmonyOS application APIs can read but cannot directly adjust the
      // global system media volume for a normal third-party application.
      OhosPlatformCapability.systemVolume => false,
      OhosPlatformCapability.readerVolumeKeys => false,
    };
  }

  bool get supportsOhosSourceHttpTransport => supportsOhosCapability(OhosPlatformCapability.sourceHttpTransport);
  bool get supportsOhosWebViewProfileIsolation => supportsOhosCapability(OhosPlatformCapability.webViewProfileIsolation);
  bool get supportsOhosWebViewCancellation => supportsOhosCapability(OhosPlatformCapability.webViewCancellation);
  bool get supportsOhosSourceSystemProxy => supportsOhosCapability(OhosPlatformCapability.sourceSystemProxy);
  bool get supportsOhosPlayerHttpProxy => supportsOhosCapability(OhosPlatformCapability.playerHttpProxy);
  bool get supportsOhosVideoBufferedPosition => supportsOhosCapability(OhosPlatformCapability.videoBufferedPosition);
  bool get supportsOhosVideoEnhancement => supportsOhosCapability(OhosPlatformCapability.videoEnhancement);
  bool get supportsOhosSystemVolume => supportsOhosCapability(OhosPlatformCapability.systemVolume);
  bool get supportsOhosReaderVolumeKeys => supportsOhosCapability(OhosPlatformCapability.readerVolumeKeys);

  /// Whether the Flutter Runtime bridge is registered.
  bool get supportsPluginRuntime => isAndroid || isWindows || isMacOS || isOhos;

  /// Whether this platform has a native Node host route. OHOS performs a
  /// separate ABI probe because the x64 emulator intentionally uses a stub.
  bool get supportsPluginRuntimeNode => isAndroid || isWindows || isMacOS || isOhos;

  /// Reads all OHOS probes through the native system bridge.
  ///
  /// The first call is single-flight and cached for the lifetime of the
  /// process. A refresh is available for diagnostics after the app returns
  /// from background or after the native host has been reattached.
  Future<OhosCapabilitySnapshot> probe({bool refresh = false}) {
    if (!isOhos) return Future<OhosCapabilitySnapshot>.value(OhosCapabilitySnapshot.unavailable('not_ohos'));
    if (!refresh) {
      final cached = _probeFuture;
      if (cached != null) return cached;
    }
    final future = _readProbe();
    _probeFuture = future;
    return future;
  }

  Future<OhosCapabilitySnapshot> _readProbe() async {
    try {
      final raw = await OhosSystemClient.getCapabilitySnapshot();
      OhosCapability read(String key) {
        final value = raw[key];
        if (value == null) return OhosCapability.unavailable('probe_missing');
        return OhosCapability(
          available: value.available,
          reason: value.reason,
          apiVersion: value.apiVersion,
          architecture: value.architecture,
        );
      }

      final runtimeBridge = read('supportsOhosRuntime');
      final runtimeAvailable = await PluginRuntime.ohosNodeHostAvailable();
      final runtime = OhosCapability(
        available: runtimeBridge.available && runtimeAvailable,
        reason: runtimeBridge.available && runtimeAvailable ? runtimeBridge.reason : 'native_node_host_unavailable',
        apiVersion: runtimeBridge.apiVersion,
        architecture: runtimeBridge.architecture,
      );
      return OhosCapabilitySnapshot(
        supportsOhosRuntime: runtime,
        supportsOhosWebView: read('supportsOhosWebView'),
        supportsOhosBackgroundAudio: read('supportsOhosBackgroundAudio'),
        supportsOhosAppUpdate: read('supportsOhosAppUpdate'),
        supportsOhosNetworkEvents: read('supportsOhosNetworkEvents'),
      );
    } on Object {
      return OhosCapabilitySnapshot.unavailable('probe_failed');
    }
  }

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
