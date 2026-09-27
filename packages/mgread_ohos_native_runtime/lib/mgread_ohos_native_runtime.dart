/// Capability description for the staged OHOS Native/Rust Runtime.
///
/// The application intentionally keeps this false until the native module is
/// built, loaded, and accepted on a real arm64 device.
library;

export 'src/native_runtime_client.dart';

const bool ohosNativeRuntimeOptIn = bool.fromEnvironment('MGREAD_OHOS_NATIVE_RUNTIME', defaultValue: false);

final class OhosNativeRuntimeCapability {
  const OhosNativeRuntimeCapability({required this.available, required this.abiVersion});

  final bool available;
  final int abiVersion;
}
