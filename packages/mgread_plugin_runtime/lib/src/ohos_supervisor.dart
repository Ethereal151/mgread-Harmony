part of mgread_plugin_runtime;

const MethodChannel _ohosRuntimeChannel = MethodChannel('mgread_plugin_runtime/ohos');
const EventChannel _ohosRuntimeProgressChannel = EventChannel('mgread_plugin_runtime/ohos/progress');
const Duration _ohosRuntimeTimeout = Duration(seconds: 30);

@immutable
final class _OhosProxyInvocation extends PluginInvocation<_OhosProxyResult> {
  const _OhosProxyInvocation(this.proxyUri);

  final Uri? proxyUri;

  @override
  String get _wireMethod => 'runtime.pluginHttpProxy.configure.v1';

  @override
  Map<String, Object?> get _wireParams => <String, Object?>{'proxyUrl': proxyUri?.toString()};

  @override
  _OhosProxyResult _decodeResult(Object? value) {
    if (value is! Map<Object?, Object?> || value['enabled'] is! bool) {
      throw const PluginRuntimeException('invalid_response', 'The OHOS Runtime returned an invalid plugin HTTP proxy result.');
    }
    return _OhosProxyResult(value['enabled'] as bool);
  }
}

@immutable
final class _OhosProxyResult {
  const _OhosProxyResult(this.enabled);

  final bool enabled;
}

@immutable
final class _OhosRawInvocation extends PluginInvocation<_OhosRawResult> {
  const _OhosRawInvocation(this.method, this.params, {required this.timeout});

  final String method;
  final Map<String, Object?> params;
  final Duration timeout;

  @override
  String get _wireMethod => method;

  @override
  Map<String, Object?> get _wireParams => params;

  @override
  Duration get _timeout => timeout;

  @override
  _OhosRawResult _decodeResult(Object? value) => _OhosRawResult(value);
}

@immutable
final class _OhosRawResult {
  const _OhosRawResult(this.value);

  final Object? value;
}

/// Flutter-side OHOS Runtime host boundary.
///
/// The native plugin owns all process/VM details. Dart only sees the same
/// typed invocation envelope used by the other Runtime hosts.
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
  Future<Map<String, String>>? _runtimeRoots;

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

  Future<Map<String, String>> _ensureRuntimeRoots() async {
    return _runtimeRoots ??= () async {
      final encoded = await _ohosRuntimeChannel.invokeMethod<String>('runtimePaths');
      if (encoded == null) {
        throw const PluginRuntimeException('runtime_no_response', 'The OHOS Runtime did not return its private roots.');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<Object?, Object?> || decoded['dataRoot'] is! String || decoded['inboxRoot'] is! String) {
        throw const PluginRuntimeException('invalid_response', 'The OHOS Runtime returned invalid private roots.');
      }
      return <String, String>{'dataRoot': decoded['dataRoot'] as String, 'inboxRoot': decoded['inboxRoot'] as String};
    }();
  }

  Future<Object?> _invokeRaw(String method, Map<String, Object?> params, {Duration timeout = const Duration(minutes: 2)}) =>
      invoke<_OhosRawResult>(_OhosRawInvocation(method, params, timeout: timeout)).then((value) => value.value);

  Future<void> _restartNativeRuntime() async {
    try {
      await _ohosRuntimeChannel.invokeMethod<String>('restart');
    } on Object catch (error) {
      throw PluginRuntimeException('runtime_shutdown_failed', 'The OHOS Runtime could not be restarted: $error');
    }
  }

  Future<void> _copyStream(Stream<List<int>> source, File target, int expectedBytes) async {
    var copied = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in source) {
        copied += chunk.length;
        if (copied > expectedBytes || copied > maxPluginTransferBytes) {
          throw const PluginRuntimeException('plugin_transfer_size_mismatch', 'The plugin transfer artifact exceeded its declared size.');
        }
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    if (copied != expectedBytes) {
      throw const PluginRuntimeException('plugin_transfer_size_mismatch', 'The plugin transfer artifact was truncated.');
    }
  }

  Stream<List<int>> _readTemporary(File file, int expectedBytes) async* {
    var copied = 0;
    try {
      await for (final chunk in file.openRead()) {
        copied += chunk.length;
        yield chunk;
      }
      if (copied != expectedBytes) {
        throw const PluginRuntimeException('plugin_transfer_size_mismatch', 'The OHOS Runtime transfer artifact was truncated.');
      }
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {}
    }
  }

  @override
  Future<void> configureNodeEnvironmentProxy(bool enabled) async {
    // The embedded host has no ambient process proxy toggle. Source HTTP
    // proxying is configured explicitly through the Runtime control method.
    if (enabled) return;
  }

  @override
  Future<void> configurePluginHttpProxy(Uri? proxyUri) async {
    final result = await invoke<_OhosProxyResult>(_OhosProxyInvocation(proxyUri));
    if (result.enabled != (proxyUri != null)) {
      throw const PluginRuntimeException('invalid_response', 'The OHOS Runtime returned an invalid plugin HTTP proxy result.');
    }
  }

  @override
  Future<void> importLocalPlugin(String sourcePath) => _importLocalPlugin(sourcePath);

  @override
  Future<bool> pickAndImportLocalPlugin() => _pickAndImportLocalPlugin();

  @override
  Future<Stream<List<int>>> exportPluginArtifact(PluginTransferArtifact artifact) async {
    final materialized = await materializePluginArtifact(
      PluginTransferOffer(
        developmentFingerprint: artifact.developmentFingerprint,
        developmentRevision: artifact.developmentRevision,
        format: artifact.format,
        pluginId: artifact.pluginId,
        provenance: artifact.provenance,
        version: artifact.version,
      ),
    );
    if (materialized.artifact.bytes != artifact.bytes || materialized.artifact.checksum != artifact.checksum) {
      throw const PluginRuntimeException(
        'plugin_transfer_checksum_mismatch',
        'The Runtime transfer artifact identity did not match the request.',
      );
    }
    return materialized.bytes;
  }

  @override
  Future<MaterializedPluginArtifact> materializePluginArtifact(PluginTransferOffer offer) => _materializePluginArtifact(offer);

  @override
  Future<PluginDevelopmentPackage> packageDevelopmentPlugin(String pluginId, String directoryPath) =>
      _packageDevelopmentPlugin(pluginId, directoryPath);

  @override
  Future<List<PluginTransferImportResult>> importPluginArtifacts(
    List<({PluginTransferArtifact artifact, Stream<List<int>> bytes})> artifacts, {
    Set<String> forceUpgradePluginIds = const <String>{},
  }) => _importPluginArtifacts(artifacts, forceUpgradePluginIds: forceUpgradePluginIds);

  @override
  Future<void> setDevelopmentDirectory(String path) =>
      Future<void>.error(const PluginRuntimeException('invalid_request', 'OHOS development sources must be imported as plugin artifacts.'));

  Future<void> _importLocalPlugin(String sourcePath) async {
    final format = _formatForPath(sourcePath);
    if (format == null) throw const PluginRuntimeException('file_name_invalid', 'The selected file is not a MgRead plugin artifact.');
    final source = File(sourcePath);
    if (!await source.exists()) throw const PluginRuntimeException('not_found', 'The selected plugin artifact is unavailable.');
    final roots = await _ensureRuntimeRoots();
    final inbox = Directory(roots['inboxRoot']!);
    await inbox.create(recursive: true);
    final suffix = format == PluginArtifactFormat.singleFile ? '.mgplugin.js' : '.mgplugin';
    final target = File('${inbox.path}${Platform.pathSeparator}import-${DateTime.now().microsecondsSinceEpoch}$suffix');
    final temporary = File('${target.path}.part');
    try {
      await source.copy(temporary.path);
      await temporary.rename(target.path);
      await _restartNativeRuntime();
      await invoke(const RuntimePingInvocation());
    } on FileSystemException {
      throw const PluginRuntimeException('disk_full', 'The selected plugin artifact could not be imported.');
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<bool> _pickAndImportLocalPlugin() async {
    final encoded = await _ohosRuntimeChannel.invokeMethod<String>('pickLocalPlugin');
    if (encoded == null || encoded.isEmpty) return false;
    await _importLocalPlugin(encoded);
    return true;
  }

  Future<MaterializedPluginArtifact> _materializePluginArtifact(PluginTransferOffer offer) async {
    final raw = await _invokeRaw('plugins.transfer.export.v2', <String, Object?>{'id': offer.pluginId, 'version': offer.version});
    final result = _jsonObject(raw, 'Plugin transfer export result');
    final token = result['token'];
    final artifact = _decodePluginTransferArtifact(result);
    if (token is! String ||
        artifact.pluginId != offer.pluginId ||
        artifact.version != offer.version ||
        artifact.format != offer.format ||
        artifact.provenance != offer.provenance ||
        artifact.developmentFingerprint != offer.developmentFingerprint ||
        artifact.developmentRevision != offer.developmentRevision) {
      throw const PluginRuntimeException(
        'plugin_transfer_checksum_mismatch',
        'The Runtime transfer artifact identity did not match the request.',
      );
    }
    final roots = await _ensureRuntimeRoots();
    final directory = Directory('${roots['dataRoot']!}${Platform.pathSeparator}temporary${Platform.pathSeparator}ohos-transfer');
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}export-${DateTime.now().microsecondsSinceEpoch}');
    final encoded = await _ohosRuntimeChannel.invokeMethod<String>('materializeTransfer', <String, Object?>{
      'token': token,
      'destination': file.path,
    });
    if (encoded == null) throw const PluginRuntimeException('runtime_no_response', 'The OHOS Runtime did not return the transfer result.');
    final copied = jsonDecode(encoded);
    if (copied is! Map<Object?, Object?> || copied['ok'] != true)
      throw const PluginRuntimeException(
        'plugin_transfer_artifact_missing',
        'The OHOS Runtime could not materialize the transfer artifact.',
      );
    return MaterializedPluginArtifact(artifact: artifact, bytes: _readTemporary(file, artifact.bytes));
  }

  Future<PluginDevelopmentPackage> _packageDevelopmentPlugin(String pluginId, String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) throw const PluginRuntimeException('file_unavailable', 'The selected output directory is unavailable.');
    final result = _jsonObject(
      await _invokeRaw('plugins.development.package.v1', <String, Object?>{'pluginId': pluginId}, timeout: const Duration(minutes: 2)),
      'Development plugin package result',
    );
    final token = result['token'];
    final fileName = result['fileName'];
    final artifact = _decodePluginTransferArtifact(result);
    if (token is! String || fileName is! String)
      throw const PluginRuntimeException('invalid_response', 'The Runtime returned an invalid development package result.');
    final target = File('${directory.path}${Platform.pathSeparator}$fileName');
    if (await target.exists())
      throw const PluginRuntimeException(
        'file_already_exists',
        'A plugin artifact with this version already exists in the selected directory.',
      );
    final roots = await _ensureRuntimeRoots();
    final temporary = File(
      '${roots['dataRoot']}${Platform.pathSeparator}temporary${Platform.pathSeparator}ohos-package-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.parent.create(recursive: true);
    try {
      final encoded = await _ohosRuntimeChannel.invokeMethod<String>('materializeTransfer', <String, Object?>{
        'token': token,
        'destination': temporary.path,
      });
      if (encoded == null || jsonDecode(encoded) is! Map<Object?, Object?> || (jsonDecode(encoded) as Map<Object?, Object?>)['ok'] != true)
        throw const PluginRuntimeException(
          'plugin_transfer_artifact_missing',
          'The Runtime could not materialize the development package.',
        );
      await temporary.rename(target.path);
      return PluginDevelopmentPackage(artifact: artifact, fileName: fileName);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<List<PluginTransferImportResult>> _importPluginArtifacts(
    List<({PluginTransferArtifact artifact, Stream<List<int>> bytes})> artifacts, {
    required Set<String> forceUpgradePluginIds,
  }) async {
    if (artifacts.isEmpty) throw const PluginRuntimeException('plugin_transfer_batch_too_large', 'The plugin transfer batch is invalid.');
    final plan = await invoke(
      PluginTransferPlanInvocation(artifacts: [for (final item in artifacts) item.artifact], forceUpgradePluginIds: forceUpgradePluginIds),
    );
    if (plan.any(
      (item) =>
          item.action == PluginTransferPlanAction.developmentConflict ||
          item.action == PluginTransferPlanAction.receiverNewer ||
          item.action == PluginTransferPlanAction.same ||
          item.action == PluginTransferPlanAction.unavailable,
    ))
      throw const PluginRuntimeException('invalid_request', 'The plugin transfer would downgrade or replace an equal Runtime version.');
    var total = 0;
    for (final item in artifacts) {
      if (item.artifact.bytes <= 0 || item.artifact.bytes > maxPluginTransferBytes)
        throw const PluginRuntimeException('plugin_transfer_artifact_too_large', 'The plugin transfer artifact is too large.');
      total += item.artifact.bytes;
      if (total > maxPluginTransferBatchBytes)
        throw const PluginRuntimeException('plugin_transfer_batch_too_large', 'The plugin transfer batch is too large.');
    }
    final roots = await _ensureRuntimeRoots();
    final inbox = Directory(roots['inboxRoot']!)..createSync(recursive: true);
    final temporaryFiles = <File>[];
    try {
      for (final item in artifacts) {
        final suffix = item.artifact.format == PluginArtifactFormat.singleFile ? '.mgplugin.js' : '.mgplugin';
        final target = File(
          '${inbox.path}${Platform.pathSeparator}transfer-${item.artifact.pluginId}-${DateTime.now().microsecondsSinceEpoch}$suffix',
        );
        final temporary = File('${target.path}.part');
        temporaryFiles.add(temporary);
        await _copyStream(item.bytes, temporary, item.artifact.bytes);
        await temporary.rename(target.path);
      }
      await _invokeRaw('plugins.transfer.verify.v2', <String, Object?>{
        'artifacts': artifacts.map((item) => item.artifact.toJson()).toList(growable: false),
      }, timeout: const Duration(minutes: 2));
      await _restartNativeRuntime();
      await invoke(const RuntimePingInvocation());
      return <PluginTransferImportResult>[
        for (final item in artifacts)
          PluginTransferImportResult(
            pluginId: item.artifact.pluginId,
            status: PluginTransferImportStatus.installed,
            version: item.artifact.version,
          ),
      ];
    } finally {
      for (final file in temporaryFiles) {
        if (await file.exists()) await file.delete();
      }
    }
  }

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
