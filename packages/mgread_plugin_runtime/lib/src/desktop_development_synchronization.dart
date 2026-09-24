part of mgread_plugin_runtime;

/// Rebinds the immutable development root after an explicit directory change.
///
/// The supervisor's lifecycle admission tail announces this transition before
/// cleanup, drains ordinary invocation leases, and prevents a late startup
/// generation from publishing a connection.
extension _DesktopDevelopmentSynchronization on _DesktopRuntimeSupervisor {
  Future<void> _restartForDevelopmentDirectoryChange() async {
    await _runLifecycleTransition(() async {
      await _restartForDevelopmentDirectoryChangeCore();
    });
  }

  Future<void> _restartForDevelopmentDirectoryChangeCore() async {
    final connection = _connection;
    if (connection != null) {
      try {
        await connection
            .request(
              method: 'runtime.shutdown',
              params: const <String, Object?>{},
              idempotencyKey: 'development-directory-change',
            )
            .timeout(_startupTimeout);
      } on Object {
        // The Job Object remains the authoritative bounded cleanup path.
      }
      await connection.close();
      _connection = null;
    }
    await _terminateOwnedProcessTree();
    await _disposeMonitor();
    _startup = null;
    _recordDiagnostic(
      const RuntimeDiagnostic(
        code: 'runtime_development_directory_rebound',
        level: RuntimeDiagnosticLevel.info,
        message: 'The Windows development source directory was rebound.',
      ),
    );
  }
}
