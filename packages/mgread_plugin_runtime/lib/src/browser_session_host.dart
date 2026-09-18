/// Shared private contract for Runtime-owned browser session hosts.
library;

abstract interface class BrowserSessionHostException implements Exception {
  String get code;
}

abstract interface class BrowserSessionHost {
  Future<Map<String, Object?>> request({
    required String jobId,
    required int deadlineUnixMs,
    required Map<String, Object?> raw,
  });

  Future<void> cancel(String jobId);

  Future<void> dispose();
}
