part of mgread_plugin_runtime;

/// Desktop Runtime lifecycle admission and generation ownership.
///
/// Stable-generation invocations receive lightweight leases and remain
/// concurrent. Restart, rebind and dispose transitions serialize behind one
/// admission tail, stop new leases, drain admitted calls within a fixed bound
/// and advance the generation before replacing process-owned resources.
const _lifecycleDrainTimeout = Duration(seconds: 8);

extension _DesktopRuntimeLifecycleGate on _DesktopRuntimeSupervisor {
  void _assertStartupGeneration(int generation) {
    if (_disposed) {
      throw _failure('runtime_unavailable', 'The desktop Runtime is closed.');
    }
    if (generation != _generation) {
      throw _failure(
        'transport_disconnected',
        'The desktop Runtime is changing lifecycle generations.',
      );
    }
  }

  Future<_RuntimeInvocationLease> _acquireInvocationLease() {
    final completer = Completer<_RuntimeInvocationLease>();
    final previous = _lifecycleAdmissionTail;
    final operation = previous.then<void>((_) {
      if (_disposed) {
        completer.completeError(
          const PluginRuntimeException(
            'runtime_unavailable',
            'The desktop Runtime has been closed.',
          ),
        );
        return;
      }
      _activeInvocationLeases += 1;
      completer.complete(_RuntimeInvocationLease(_releaseInvocationLease));
    });
    _lifecycleAdmissionTail = operation.then<void>((_) {}, onError: (_, __) {});
    return completer.future;
  }

  Future<void> _runLifecycleTransition(
    Future<void> Function() action, {
    bool allowDisposed = false,
    bool Function()? shouldTransition,
  }) {
    final result = Completer<void>();
    final previous = _lifecycleAdmissionTail;
    final operation = previous.then<void>((_) async {
      if (!allowDisposed && _disposed) {
        result.completeError(
          const PluginRuntimeException(
            'runtime_unavailable',
            'The desktop Runtime has been closed.',
          ),
        );
        return;
      }
      if (shouldTransition != null && !shouldTransition()) {
        result.complete();
        return;
      }
      _generation += 1;
      _controlledRestarting = true;
      try {
        // Announce the new generation before draining. An admitted startup
        // therefore cannot publish a connection while this transition waits.
        await _waitForInvocationDrain();
        await action();
        result.complete();
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _controlledRestarting = false;
      }
    });
    _lifecycleAdmissionTail = operation.then<void>((_) {}, onError: (_, __) {});
    return result.future;
  }

  Future<void> _waitForInvocationDrain() async {
    if (_activeInvocationLeases == 0) return;
    final drained = _invocationsDrained ??= Completer<void>();
    try {
      await drained.future.timeout(_lifecycleDrainTimeout);
    } on TimeoutException {
      // The transition closes the connection/process and fails remaining
      // leases with an explicit transport error.
    }
  }

  void _releaseInvocationLease() {
    if (_activeInvocationLeases == 0) return;
    _activeInvocationLeases -= 1;
    if (_activeInvocationLeases == 0) {
      final drained = _invocationsDrained;
      _invocationsDrained = null;
      if (drained != null && !drained.isCompleted) drained.complete();
    }
  }
}

final class _RuntimeInvocationLease {
  _RuntimeInvocationLease(this._onRelease);

  final void Function() _onRelease;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _onRelease();
  }
}
