part of mgread_plugin_runtime;

/// Native/Rust supervisor for the opt-in OHOS release engine.
///
/// The Rust bridge intentionally exposes one built-in source rather than a
/// filesystem plugin installer. This supervisor adapts that source to the
/// same typed Runtime facade used by the Android and desktop engines.
final class _OhosNativeRuntimeSupervisor implements _RuntimeSupervisor {
  static const String _sourceId = 'org.mgread.aisishuwu.native';
  static const String _sourceName = '爱丽丝书屋（Rust）';
  static const String _ohosArchitecture = String.fromEnvironment('MGREAD_OHOS_ARCH', defaultValue: 'arm64');
  static String get _abi => _ohosArchitecture == 'x64' ? 'x86_64' : 'arm64-v8a';
  static const MethodChannel _channel = MethodChannel('mgread_ohos_native_runtime');

  bool _installed = false;
  bool _enabled = true;
  String _version = 'mgread-ohos-native-runtime/unknown';
  Uri? _proxyUri;
  Future<void>? _startup;
  bool _disposed = false;

  final StreamController<RuntimeDiagnostic> _diagnostics = StreamController<RuntimeDiagnostic>.broadcast();
  final StreamController<RuntimeInitializationProgress> _initialization = StreamController<RuntimeInitializationProgress>.broadcast();

  @override
  Stream<RuntimeDiagnostic> get diagnostics => _diagnostics.stream;

  @override
  Stream<RuntimeInitializationProgress> get initialization => _initialization.stream;

  @override
  Stream<DevelopmentPluginChangeBatch> get developmentChanges => const Stream<DevelopmentPluginChangeBatch>.empty();

  @override
  List<RuntimeDiagnostic> get latestDiagnostics => const <RuntimeDiagnostic>[];

  @override
  int get debugProcessStartCount => 0;

  Future<void> _ensureStarted() {
    if (_disposed) {
      throw const PluginRuntimeException('runtime_disposed', 'The OHOS Native Runtime has been disposed.');
    }
    return _startup ??= _start();
  }

  Future<void> _start() async {
    try {
      _version = await _channel.invokeMethod<String>('version') ?? _version;
      final config = jsonEncode(<String, Object?>{if (_proxyUri != null) 'proxy': _proxyUri.toString()});
      // The OHOS NAPI create entrypoint constructs the bridge and calls
      // mgread_runtime_start immediately; its integer result is a status code,
      // not an opaque handle. Calling start again made the Dart health gate
      // depend on a second bridge transition and surfaced runtime_start_failed
      // even though the native runtime was already ready.
      final createResult = await _channel.invokeMethod<int>('create', <String, Object?>{'configJson': config}) ?? -1;
      if (createResult != 0) throw const PluginRuntimeException('runtime_start_failed', 'OHOS Native Runtime 创建失败。');
      _installed = true;
      final progress = RuntimeInitializationProgress.fromPlatform(
        completedBytes: 1,
        totalBytes: 1,
        stage: 'node_starting',
        detail: 'Rust 原生数据源引擎已启动',
      );
      if (progress != null) _initialization.add(progress);
    } on PluginRuntimeException {
      rethrow;
    } on PlatformException catch (error) {
      throw PluginRuntimeException('runtime_start_failed', error.message ?? 'OHOS Native Runtime 启动失败。');
    }
  }

  Map<String, Object?> _plugin({bool? enabled}) => <String, Object?>{
    'engine': 'native',
    'id': _sourceId,
    'name': _sourceId,
    'displayName': _sourceName,
    'description': '由 OHOS Rust 原生运行时提供的数据源',
    'iconUrl': null,
    'activeVersion': '0.1.0',
    'pendingVersion': null,
    'enabled': enabled ?? _enabled,
    'status': 'active',
    'contentKinds': <String>['novel'],
  };

  Future<T> _decode<T>(PluginInvocation<T> invocation, Object? value) async {
    await _ensureStarted();
    return invocation._decodeResult(value);
  }

  Future<T> _sourceInvoke<T>(PluginInvocation<T> invocation, String method, Map<String, Object?> request) async {
    if (!_enabled) throw const PluginRuntimeException('plugin_disabled', 'Rust 原生数据源未启用。');
    await _ensureStarted();
    final raw = await _channel.invokeMethod<String>('invoke', <String, Object?>{
      'requestJson': jsonEncode(<String, Object?>{
        'requestId': '${DateTime.now().microsecondsSinceEpoch}',
        'method': method,
        'request': request,
      }),
    });
    if (raw == null || raw.isEmpty) throw const PluginRuntimeException('invalid_response', 'OHOS Native Runtime 返回空结果。');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?> || decoded['ok'] != true || decoded['value'] is! Map<Object?, Object?>) {
      throw const PluginRuntimeException('plugin_load_failed', 'Rust 原生数据源返回了无效结果。');
    }
    final value = Map<String, Object?>.from(decoded['value'] as Map<Object?, Object?>);
    value['pluginId'] = _sourceId;
    value['sourceName'] = _sourceName;
    return _decode(invocation, value);
  }

  @override
  Future<T> invoke<T>(PluginInvocation<T> invocation, {PluginInvocationCancellation? cancellation}) async {
    cancellation?._throwIfCancelled();
    if (invocation is RuntimePingInvocation) {
      await _ensureStarted();
      return _decode(invocation, <String, Object?>{'ok': true, 'nodeVersion': '', 'runtimeVersion': _version});
    }
    if (invocation is InstalledPluginsInvocation) {
      await _ensureStarted();
      return _decode(invocation, _installed ? <Object?>[_plugin()] : const <Object?>[]);
    }
    if (invocation is PluginStartupRecoveryInvocation) return _decode(invocation, const <String, Object?>{'quarantinedCount': 0});
    if (invocation is RuntimeStatusInvocation) {
      await _ensureStarted();
      return _decode(invocation, <String, Object?>{
        'ok': true,
        'nodeVersion': '',
        'runtimeVersion': _version,
        'runtimeKind': 'native-rust',
        'platform': 'ohos',
        'arch': _abi,
        'uptimeMs': 0,
        'memory': <String, Object?>{'arrayBuffers': 0, 'external': 0, 'heapTotal': 0, 'heapUsed': 0, 'rss': 0},
        'plugins': _installed ? <Object?>[_plugin()] : const <Object?>[],
      });
    }
    if (invocation is SourceSearchInvocation) {
      final request = Map<String, Object?>.from(invocation._wireParams)..remove('pluginId');
      return _sourceInvoke(invocation, 'search', request);
    }
    if (invocation is SourceSearchSuggestionsInvocation) {
      final request = Map<String, Object?>.from(invocation._wireParams)..remove('pluginId');
      return _sourceInvoke(invocation, 'searchSuggestions', request);
    }
    if (invocation is SourceDiscoverInvocation) {
      final request = Map<String, Object?>.from(invocation._wireParams)..remove('pluginId');
      return _sourceInvoke(invocation, 'discover', request);
    }
    if (invocation is SourceDetailInvocation) {
      final request = Map<String, Object?>.from(invocation._wireParams)..remove('pluginId');
      return _sourceInvoke(invocation, 'getDetail', request);
    }
    if (invocation is SourceChaptersInvocation) {
      final request = Map<String, Object?>.from(invocation._wireParams)..remove('pluginId');
      return _sourceInvoke(invocation, 'getChapters', request);
    }
    if (invocation is SourceContentInvocation) {
      final request = Map<String, Object?>.from(invocation._wireParams)..remove('pluginId');
      return _sourceInvoke(invocation, 'getContent', request);
    }
    if (invocation is SetPluginEnabledInvocation) {
      final typed = invocation as SetPluginEnabledInvocation;
      if (typed.pluginId != _sourceId) throw const PluginRuntimeException('plugin_not_found', 'Rust 原生数据源不存在。');
      _enabled = typed.enabled;
      return _decode(invocation, _plugin());
    }
    if (invocation is UninstallPluginInvocation) {
      if ((invocation as UninstallPluginInvocation).pluginId == _sourceId) {
        _installed = false;
      }
      return null as T;
    }
    if (invocation is UninstallAllPluginsInvocation) {
      _installed = false;
      return null as T;
    }
    if (invocation is PluginInstallationSizeInvocation) {
      final typed = invocation as PluginInstallationSizeInvocation;
      return _decode(invocation, <String, Object?>{
        'pluginId': typed.pluginId,
        'scope': typed.scope.name,
        'bytes': 0,
        'fileCount': 0,
        'version': '0.1.0',
      });
    }
    if (invocation is PluginCacheUsageInvocation) return _decode(invocation, const <Object?>[]);
    throw const PluginRuntimeException('unsupported', '该 Native Runtime 能力暂未在 OHOS 暴露。');
  }

  @override
  Future<void> importLocalPlugin(String sourcePath) => _ensureStarted();

  @override
  Future<bool> pickAndImportLocalPlugin() async {
    await _ensureStarted();
    _installed = true;
    return true;
  }

  @override
  Future<Stream<List<int>>> exportPluginArtifact(PluginTransferArtifact artifact) =>
      Future<Stream<List<int>>>.error(const PluginRuntimeException('unsupported', 'OHOS Native Runtime 不支持导出内置来源。'));

  @override
  Future<MaterializedPluginArtifact> materializePluginArtifact(PluginTransferOffer offer) =>
      Future<MaterializedPluginArtifact>.error(const PluginRuntimeException('unsupported', 'OHOS Native Runtime 不支持导出内置来源。'));

  @override
  Future<PluginDevelopmentPackage> packageDevelopmentPlugin(String pluginId, String directoryPath) =>
      Future<PluginDevelopmentPackage>.error(const PluginRuntimeException('unsupported', 'OHOS Native Runtime 不支持开发目录来源。'));

  @override
  Future<List<PluginTransferImportResult>> importPluginArtifacts(
    List<({PluginTransferArtifact artifact, Stream<List<int>> bytes})> artifacts, {
    Set<String> forceUpgradePluginIds = const <String>{},
  }) => Future<List<PluginTransferImportResult>>.error(const PluginRuntimeException('unsupported', 'OHOS Rust 来源不是可上传的插件包。'));

  @override
  Future<void> setDevelopmentDirectory(String path) =>
      Future<void>.error(const PluginRuntimeException('unsupported', 'OHOS Native Runtime 不支持开发目录来源。'));

  @override
  Future<void> configureNodeEnvironmentProxy(bool enabled) async {}

  @override
  Future<void> configurePluginHttpProxy(Uri? proxyUri, {String? noProxy}) async {
    _proxyUri = proxyUri;
    if (_startup != null) {
      // The Rust ABI reads proxy configuration when the native handle is
      // created. A lifecycle-only restart keeps the old JSON, so replace the
      // handle with a newly configured instance while preserving the same
      // process-scoped Facade and built-in source identity.
      final result =
          await _channel.invokeMethod<int>('create', <String, Object?>{
            'configJson': jsonEncode(<String, Object?>{if (_proxyUri != null) 'proxy': _proxyUri.toString()}),
          }) ??
          -1;
      if (result != 0) {
        throw const PluginRuntimeException('runtime_restart_failed', 'OHOS Native Runtime 代理配置重载失败。');
      }
      _installed = true;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod<int>('stop');
      await _channel.invokeMethod<void>('dispose');
    } finally {
      await _diagnostics.close();
      await _initialization.close();
    }
  }
}
