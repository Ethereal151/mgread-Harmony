part of mgread_plugin_runtime;

const MethodChannel _ohosRuntimeChannel = MethodChannel('mgread_plugin_runtime/ohos');
const EventChannel _ohosRuntimeProgressChannel = EventChannel('mgread_plugin_runtime/ohos/progress');
const Duration _ohosRuntimeTimeout = Duration(seconds: 30);

/// Flutter-side OHOS Runtime host boundary.
///
/// The native plugin owns all process/VM details. The current OHOS SDK does
/// not ship a verified Node 24.16.0 OHOS arm64 binary, so the native host
/// returns a typed `unsupported` envelope until that PoC is supplied. Keeping
/// the bridge in place now prevents business code from gaining a second
/// platform-specific Runtime API later.
final class _OhosRuntimeSupervisor implements _RuntimeSupervisor {
  final StreamController<RuntimeDiagnostic> _diagnosticsController = StreamController<RuntimeDiagnostic>.broadcast();
  final StreamController<RuntimeInitializationProgress> _initializationController =
      StreamController<RuntimeInitializationProgress>.broadcast();
  _OhosRuntimeSupervisor() {
    _progressSubscription = _ohosRuntimeProgressChannel.receiveBroadcastStream().listen(
      _onNativeProgress,
      onError: (Object _, StackTrace __) {},
    );
  }

  late final StreamSubscription<dynamic> _progressSubscription;
  bool _disposed = false;
  int _invocationSequence = 0;

  void _onNativeProgress(dynamic raw) {
    if (raw is! Map) return;
    final progress = RuntimeInitializationProgress.fromPlatform(
      catalogState: raw['catalogState'] as String?,
      completedBytes: raw['completedBytes'] is int ? raw['completedBytes'] as int : 0,
      detail: raw['detail'] as String?,
      durationMicros: raw['durationMicros'] as int?,
      itemCount: raw['itemCount'] as int?,
      stage: raw['stage'] as String? ?? '',
      totalBytes: raw['totalBytes'] is int ? raw['totalBytes'] as int : 0,
    );
    if (progress != null) _initializationController.add(progress);
  }

  @override
  Stream<RuntimeDiagnostic> get diagnostics => _diagnosticsController.stream;

  @override
  Stream<RuntimeInitializationProgress> get initialization => _initializationController.stream;

  @override
  Stream<DevelopmentPluginChangeBatch> get developmentChanges => const Stream<DevelopmentPluginChangeBatch>.empty();

  @override
  List<RuntimeDiagnostic> get latestDiagnostics => const <RuntimeDiagnostic>[];

  @override
  int get debugProcessStartCount => 0;

  @override
  Future<T> invoke<T>(PluginInvocation<T> invocation, {PluginInvocationCancellation? cancellation}) async {
    if (_disposed) {
      throw const PluginRuntimeException('runtime_unavailable', 'The OHOS Runtime has been closed.');
    }
    cancellation?._throwIfCancelled();
    final requestId = 'ohos-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${++_invocationSequence}';
    final timeout = invocation._timeout > _ohosRuntimeTimeout ? invocation._timeout : _ohosRuntimeTimeout;
    try {
      final encoded =
          await _awaitPluginInvocation(
            _ohosRuntimeChannel.invokeMethod<String>('invoke', <String, Object?>{
              'requestId': requestId,
              'method': invocation._wireMethod,
              'params': invocation._wireParams,
              'deadlineUnixMs': DateTime.now().add(timeout).millisecondsSinceEpoch,
            }),
            cancellation,
            onCancel: () => _cancel(requestId),
          ).timeout(
            timeout,
            onTimeout: () {
              _cancel(requestId);
              throw const PluginRuntimeException('timeout', 'The OHOS Runtime capability call timed out.');
            },
          );
      if (encoded == null) {
        throw const PluginRuntimeException('runtime_no_response', 'The OHOS Runtime returned no result.');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<Object?, Object?>) {
        throw const PluginRuntimeException('invalid_response', 'The OHOS Runtime returned an invalid result.');
      }
      if (decoded['ok'] != true) {
        final error = decoded['error'];
        final code = error is Map<Object?, Object?> && error['code'] is String ? error['code'] as String : 'internal';
        final message = error is Map<Object?, Object?> && error['message'] is String
            ? error['message'] as String
            : 'The OHOS Runtime rejected the request.';
        throw PluginRuntimeException(code, message);
      }
      return invocation._decodeResult(decoded['result']);
    } on PluginRuntimeException {
      rethrow;
    } on PlatformException catch (error) {
      throw PluginRuntimeException(error.code, error.message ?? 'The OHOS Runtime platform bridge failed.');
    } on TimeoutException {
      throw const PluginRuntimeException('timeout', 'The OHOS Runtime capability call timed out.');
    } on Object {
      throw const PluginRuntimeException('runtime_unavailable', 'The OHOS Runtime capability call failed.');
    }
  }

  void _cancel(String requestId) {
    unawaited(
      _ohosRuntimeChannel.invokeMethod<void>('cancelInvocation', <String, Object?>{'requestId': requestId}).catchError((Object _) {}),
    );
  }

  PluginRuntimeException _unsupported(String operation) =>
      PluginRuntimeException('unsupported', 'The OHOS Runtime does not support $operation until the Node host is available.');

  @override
  Future<void> configureNodeEnvironmentProxy(bool enabled) => Future<void>.error(_unsupported('Node environment proxy configuration'));

  @override
  Future<void> configurePluginHttpProxy(Uri? proxyUri) => Future<void>.error(_unsupported('plugin HTTP proxy configuration'));

  @override
  Future<void> importLocalPlugin(String sourcePath) => Future<void>.error(_unsupported('local plugin import'));

  @override
  Future<bool> pickAndImportLocalPlugin() => Future<bool>.error(_unsupported('local plugin import'));

  @override
  Future<Stream<List<int>>> exportPluginArtifact(PluginTransferArtifact artifact) =>
      Future<Stream<List<int>>>.error(_unsupported('plugin export'));

  @override
  Future<MaterializedPluginArtifact> materializePluginArtifact(PluginTransferOffer offer) =>
      Future<MaterializedPluginArtifact>.error(_unsupported('plugin transfer'));

  @override
  Future<PluginDevelopmentPackage> packageDevelopmentPlugin(String pluginId, String directoryPath) =>
      Future<PluginDevelopmentPackage>.error(_unsupported('development plugin packaging'));

  @override
  Future<List<PluginTransferImportResult>> importPluginArtifacts(
    List<({PluginTransferArtifact artifact, Stream<List<int>> bytes})> artifacts, {
    Set<String> forceUpgradePluginIds = const <String>{},
  }) => Future<List<PluginTransferImportResult>>.error(_unsupported('plugin transfer'));

  @override
  Future<void> setDevelopmentDirectory(String path) => Future<void>.error(_unsupported('development plugin directories'));

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _progressSubscription.cancel();
    try {
      await _ohosRuntimeChannel.invokeMethod<void>('dispose');
    } on Object {
      // Native disposal is best effort; the host owns no Dart resources after
      // this point and must remain idempotent during app shutdown.
    }
    await _diagnosticsController.close();
    await _initializationController.close();
  }
}
