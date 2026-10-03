part of mgread_plugin_runtime;

/// OHOS embedded Node lifecycle admission.
///
/// Stable-generation invocations may remain concurrent. A Runtime restart or
/// disposal transition is admitted behind already admitted calls, stops new
/// calls from entering the old generation, and only then touches the single
/// process-scoped Node VM.
// The transfer and management invocations currently have a two-minute
// budget; the transition must not enter the replacement VM before that
// budget has had a chance to release its invocation lease.
const _ohosLifecycleDrainTimeout = Duration(minutes: 2);

extension _OhosRuntimeLifecycleGate on _OhosRuntimeSupervisor {
  Future<_OhosInvocationLease> _acquireInvocationLease() async {
    while (true) {
      final tail = _lifecycleAdmissionTail;
      await tail;
      if (!identical(tail, _lifecycleAdmissionTail)) continue;
      if (_disposed) {
        throw const PluginRuntimeException(
          'runtime_unavailable',
          'The OHOS Runtime has been closed.',
        );
      }
      _activeInvocationLeases += 1;
      return _OhosInvocationLease(() {
        _activeInvocationLeases -= 1;
        if (_activeInvocationLeases == 0 &&
            _inFlightDrained != null &&
            !_inFlightDrained!.isCompleted) {
          _inFlightDrained!.complete();
        }
      });
    }
  }

  Future<T> _runLifecycleTransition<T>(Future<T> Function() action) async {
    final previous = _lifecycleAdmissionTail;
    final finished = Completer<void>();
    _lifecycleAdmissionTail = finished.future;
    await previous;
    try {
      if (_activeInvocationLeases > 0) {
        _inFlightDrained ??= Completer<void>();
        await _inFlightDrained!.future.timeout(_ohosLifecycleDrainTimeout);
      }
      return await action();
    } finally {
      _inFlightDrained = null;
      if (!finished.isCompleted) finished.complete();
    }
  }
}

final class _OhosInvocationLease {
  _OhosInvocationLease(this._release);

  final VoidCallback _release;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}
