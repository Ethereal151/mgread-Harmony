/// Capability description for the staged OHOS Native/Rust Runtime.
///
/// Each OHOS ABI enables the Native Runtime only when its matching Rust module
/// is built into the HAP and accepted by that ABI's integration checks.
library;

export 'src/native_runtime_client.dart';

const bool ohosNativeRuntimeOptIn = bool.fromEnvironment('MGREAD_OHOS_NATIVE_RUNTIME', defaultValue: false);

final class OhosNativeRuntimeCapability {
  const OhosNativeRuntimeCapability({required this.available, required this.abiVersion});

  final bool available;
  final int abiVersion;
}
