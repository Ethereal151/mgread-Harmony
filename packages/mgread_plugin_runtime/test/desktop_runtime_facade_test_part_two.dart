part of 'desktop_runtime_facade_test.dart';

void registerDesktopRuntimeFacadeTestsPartTwo() {
  test(
    'caller cancellation ends a desktop source invocation without closing Runtime',
    () async {
      final runtimeDataRoot = await _stageInstalledStandardPlugin();
      addTearDown(() => runtimeDataRoot.delete(recursive: true));
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: nodeRuntimeRepositoryRoot,
        runtimeDataRoot: runtimeDataRoot,
      );
      addTearDown(runtime.debugDispose);
      await runtime.invoke(const InstalledPluginsInvocation());

      final cancellation = PluginInvocationCancellation();
      final stopwatch = Stopwatch()..start();
      unawaited(
        Future<void>.delayed(
          const Duration(milliseconds: 100),
          cancellation.cancel,
        ),
      );

      await expectLater(
        runtime.invoke(
          const SourceDiscoverInvocation(
            pluginId: 'org.mgread.flutter.fixture',
            target: 'slow-nested',
          ),
          cancellation: cancellation,
        ),
        throwsA(
          isA<PluginRuntimeException>().having(
            (error) => error.code,
            'code',
            'cancelled',
          ),
        ),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(
        (await runtime.invoke(const RuntimePingInvocation())).isHealthy,
        isTrue,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'bulk uninstall waits for an active source call beyond the control timeout',
    () async {
      final runtimeDataRoot = await _stageInstalledStandardPlugin();
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: nodeRuntimeRepositoryRoot,
        runtimeDataRoot: runtimeDataRoot,
      );
      addTearDown(() async {
        await runtime.debugDispose();
        await runtimeDataRoot.delete(recursive: true);
      });

      final slowDiscovery = runtime.invoke(
        const SourceDiscoverInvocation(
          pluginId: 'org.mgread.flutter.fixture',
          target: 'slow-nested',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await runtime.invoke(const UninstallAllPluginsInvocation());

      expect(await slowDiscovery, isA<PluginDiscoveryDocumentResult>());
      expect(await runtime.invoke(const InstalledPluginsInvocation()), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'desktop development source changes build and hot reload without restarting Runtime',
    () async {
      final repositoryRoot = nodeRuntimeRepositoryRoot;
      final root = await Directory.systemTemp.createTemp(
        'mgread-flutter-development-source-',
      );
      final developmentRoot = Directory(
        <String>[root.path, 'sources'].join(Platform.pathSeparator),
      );
      final runtimeDataRoot = Directory(
        <String>[root.path, 'runtime-data'].join(Platform.pathSeparator),
      );
      addTearDown(() => root.delete(recursive: true));
      await _writeDevelopmentPlugin(developmentRoot, '第一版');
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: repositoryRoot,
        runtimeDataRoot: runtimeDataRoot,
        developmentPluginRoot: developmentRoot,
      );
      addTearDown(runtime.debugDispose);

      final plugins = await runtime.invoke(const InstalledPluginsInvocation());
      final first = await runtime.invoke(
        const SourceSearchInvocation(
          pluginId: 'org.example.flutter-live',
          query: '测试',
        ),
      );
      expect(plugins.single.status, 'development');
      expect(first.items.single.title, '第一版：测试');
      expect(runtime.debugDesktopProcessStartCount, 1);

      final changed = runtime.developmentChanges.firstWhere(
        (batch) => batch.changes.any(
          (change) =>
              change.kind == DevelopmentPluginChangeKind.updated &&
              change.pluginId == 'org.example.flutter-live',
        ),
      );
      await _writeDevelopmentPlugin(developmentRoot, '第二版');
      await changed.timeout(const Duration(seconds: 15));
      final second = await runtime.invoke(
        const SourceSearchInvocation(
          pluginId: 'org.example.flutter-live',
          query: '测试',
        ),
      );
      expect(second.items.single.title, '第二版：测试');
      expect(runtime.debugDesktopProcessStartCount, 1);
      expect(
        Directory(
          <String>[
            runtimeDataRoot.path,
            'plugins',
            'org.example.flutter-live',
          ].join(Platform.pathSeparator),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('closed test Runtime rejects another Facade capability call', () async {
    final runtime = PluginRuntime.desktopForTesting(
      runtimeRepositoryRoot: nodeRuntimeRepositoryRoot,
    );
    addTearDown(runtime.debugDispose);

    await runtime.invoke(const RuntimePingInvocation());
    await runtime.debugDispose();

    await expectLater(
      runtime.invoke(const RuntimePingInvocation()),
      throwsA(
        isA<PluginRuntimeException>().having(
          (error) => error.code,
          'code',
          'runtime_unavailable',
        ),
      ),
    );
  });

  test(
    'Facade reports a missing packaged Node executable with a stable reason',
    () async {
      final repositoryRoot = nodeRuntimeRepositoryRoot;
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: repositoryRoot,
        nodeExecutableOverride: File(
          <String>[
            repositoryRoot.path,
            'missing-node.exe',
          ].join(Platform.pathSeparator),
        ),
      );
      final diagnostics = <RuntimeDiagnostic>[];
      final subscription = runtime.diagnostics.listen(diagnostics.add);
      addTearDown(() async {
        await subscription.cancel();
        await runtime.debugDispose();
      });

      late PluginRuntimeException error;
      for (var attempt = 0; attempt < 96; attempt += 1) {
        error = await _captureRuntimeFailure(
          runtime.invoke(const RuntimePingInvocation()),
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(error.code, 'runtime_node_executable_missing');
      expect(
        error.diagnostics.map((diagnostic) => diagnostic.code),
        contains('runtime_node_executable_missing'),
      );
      expect(
        diagnostics.map((diagnostic) => diagnostic.code),
        contains('runtime_node_executable_missing'),
      );
    },
  );

  test(
    'Facade reports a missing packaged main script with a stable reason',
    () async {
      final repositoryRoot = nodeRuntimeRepositoryRoot;
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: repositoryRoot,
        entrypointOverride: File(
          <String>[
            repositoryRoot.path,
            'missing-runtime-main.mjs',
          ].join(Platform.pathSeparator),
        ),
      );
      addTearDown(runtime.debugDispose);

      final error = await _captureRuntimeFailure(
        runtime.invoke(const RuntimePingInvocation()),
      );

      expect(error.code, 'runtime_entrypoint_missing');
      expect(
        error.diagnostics.map((diagnostic) => diagnostic.code),
        contains('runtime_entrypoint_missing'),
      );
    },
  );

  test(
    'Facade preserves a structured Node startup failure diagnostic',
    () async {
      final repositoryRoot = nodeRuntimeRepositoryRoot;
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: repositoryRoot,
        entrypointOverride: File(
          <String>[
            repositoryRoot.path,
            'test',
            'fixtures',
            'fatal-before-ready.mjs',
          ].join(Platform.pathSeparator),
        ),
      );
      addTearDown(runtime.debugDispose);

      final error = await _captureRuntimeFailure(
        runtime.invoke(const RuntimePingInvocation()),
      );

      expect(error.code, 'runtime_start_failed');
      expect(
        error.diagnostics.map((diagnostic) => diagnostic.code),
        contains('test_startup_failure'),
      );
    },
  );

  test(
    'a child exit before ready becomes a fatal Facade diagnostic and bounded fallback TXT',
    () async {
      final repositoryRoot = nodeRuntimeRepositoryRoot;
      final runtimeDataRoot = await Directory.systemTemp.createTemp(
        'mgread-runtime-preboot-fallback-',
      );
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: repositoryRoot,
        runtimeDataRoot: runtimeDataRoot,
        entrypointOverride: File(
          <String>[
            pluginRuntimeRepositoryRoot.path,
            'test',
            'fixtures',
            'exit-before-ready.mjs',
          ].join(Platform.pathSeparator),
        ),
      );
      addTearDown(() async {
        await runtime.debugDispose();
        await runtimeDataRoot.delete(recursive: true);
      });

      final error = await _captureRuntimeFailure(
        runtime.invoke(const RuntimePingInvocation()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final fallback = File(
        <String>[
          runtimeDataRoot.path,
          'diagnostics',
          'desktop-fatal-fallback.txt',
        ].join(Platform.pathSeparator),
      );
      final contents = await fallback.readAsString();

      expect(error.code, 'runtime_exited_before_ready');
      expect(
        error.diagnostics
            .singleWhere((item) => item.code == error.code)
            .isFatal,
        isTrue,
      );
      expect(contents, contains('"code":"runtime_exited_before_ready"'));
      expect(contents, contains('"phase":"startup"'));
      expect(contents, contains('"fingerprint":'));
      expect(contents, isNot(contains(runtimeDataRoot.path)));
      expect(contents, isNot(contains('exit-before-ready.mjs')));
      expect((await fallback.length()), lessThanOrEqualTo(16 * 1024));
    },
  );

  test(
    'a post-ready child exit emits a fatal diagnostic and only restarts on the next invocation',
    () async {
      final runtime = PluginRuntime.desktopForTesting(
        runtimeRepositoryRoot: nodeRuntimeRepositoryRoot,
        testExitAfterReady: const Duration(milliseconds: 250),
      );
      final fatalDiagnostics = <RuntimeDiagnostic>[];
      final subscription = runtime.fatalDiagnostics.listen(
        fatalDiagnostics.add,
      );
      addTearDown(() async {
        await subscription.cancel();
        await runtime.debugDispose();
      });

      await runtime.invoke(const RuntimePingInvocation());
      await _waitForDiagnosticCodes(fatalDiagnostics, const <String>[
        'runtime_process_exited',
      ]);
      expect(fatalDiagnostics.single.isFatal, isTrue);
      expect(runtime.debugDesktopProcessStartCount, 1);

      await runtime.invoke(const RuntimePingInvocation());
      expect(runtime.debugDesktopProcessStartCount, 2);
    },
  );
}
