import 'dart:async';
import 'dart:math';

/// Session-level scheduler for failed comic images.
///
/// Automatic retries are deliberately separated from the image byte cache:
/// Failed work normally waits for a jittered 3-6 second delay. A failed image
/// that is (or becomes) near the viewport gets one immediate background retry
/// first. Only one retry is in flight for the whole reader, which prevents a
/// source outage from turning every failed tile into a synchronized request
/// burst while preserving explicit manual retry.
class ComicImageRetryCoordinator {
  ComicImageRetryCoordinator({
    Duration Function()? retryDelay,
    this.scanDebounce = const Duration(milliseconds: 120),
    this.maxConcurrentRetries = 1,
    this.maxAutomaticRetries = 2,
  }) : _retryDelay = retryDelay ?? _randomRetryDelay;

  final Duration Function() _retryDelay;
  final Duration scanDebounce;
  final int maxConcurrentRetries;
  final int maxAutomaticRetries;
  final Map<String, _ComicImageRetryEntry> _entries =
      <String, _ComicImageRetryEntry>{};
  Timer? _scanTimer;
  DateTime? _scanScheduledAt;
  int _activeRetries = 0;
  bool _viewportDirty = false;
  bool _disposed = false;

  void register({
    required String key,
    required bool Function() isNearViewport,
    required Future<void> Function() retry,
  }) {
    if (_disposed || maxAutomaticRetries <= 0) return;
    final previous = _entries[key];
    // The callback may report its failure while the previous retry is still
    // completing. Keep the new failure, but never create a second retry for it.
    final int attempts = previous?.attempts ?? 0;
    if (attempts >= maxAutomaticRetries) {
      _entries.remove(key);
      _scheduleNextScan();
      return;
    }
    final bool near = _safeNearViewport(isNearViewport);
    final bool nearViewportImmediateUsed =
        previous?.nearViewportImmediateUsed ?? false;
    final DateTime now = DateTime.now();
    _entries[key] = _ComicImageRetryEntry(
      isNearViewport: isNearViewport,
      retry: retry,
      attempts: attempts,
      nearViewportImmediateUsed: near ? true : nearViewportImmediateUsed,
      notBefore: near && !nearViewportImmediateUsed
          ? now
          : now.add(_retryDelay()),
    );
    if (_entries.length > 64) {
      final String oldestKey = _entries.keys.firstWhere(
        (String entryKey) => entryKey != key && !_entries[entryKey]!.running,
        orElse: () => '',
      );
      if (oldestKey.isNotEmpty) _entries.remove(oldestKey);
    }
    _scheduleNextScan(preferDebounce: near);
  }

  void markResolved(String key) {
    _entries.remove(key);
    _scheduleNextScan();
  }

  void remove(String key) {
    _entries.remove(key);
    _scheduleNextScan();
  }

  /// Coalesces scroll notifications into at most one eligibility scan per
  /// debounce window. The scan itself does not rebuild the reader.
  void onViewportChanged() {
    if (_disposed) return;
    _viewportDirty = true;
    _scheduleAt(DateTime.now().add(scanDebounce));
  }

  void clear() {
    _entries.clear();
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanScheduledAt = null;
    _viewportDirty = false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
  }

  void _scan() {
    if (_disposed) return;
    _scanTimer = null;
    _scanScheduledAt = null;
    if (_activeRetries >= maxConcurrentRetries) return;

    final DateTime now = DateTime.now();
    if (_viewportDirty) {
      _viewportDirty = false;
      for (final entry in _entries.values) {
        if (entry.running || entry.nearViewportImmediateUsed) continue;
        if (_safeNearViewport(entry.isNearViewport)) {
          entry.nearViewportImmediateUsed = true;
          entry.notBefore = now;
        }
      }
    }
    _ComicImageRetryEntry? selected;
    String? selectedKey;
    for (final MapEntry<String, _ComicImageRetryEntry> item
        in _entries.entries) {
      final entry = item.value;
      if (entry.running || entry.notBefore.isAfter(now)) continue;
      selected = entry;
      selectedKey = item.key;
      break;
    }
    if (selected == null || selectedKey == null) {
      _scheduleNextScan();
      return;
    }

    selected.running = true;
    selected.attempts++;
    _activeRetries++;
    Future<void> retryFuture;
    try {
      retryFuture = selected.retry();
    } on Object {
      if (identical(_entries[selectedKey], selected)) {
        _entries.remove(selectedKey);
      }
      retryFuture = Future<void>.value();
    }
    retryFuture.whenComplete(() {
      _activeRetries--;
      if (!_disposed) _scheduleNextScan();
    }).ignore();
    _scheduleNextScan();
  }

  void _scheduleNextScan({bool preferDebounce = false}) {
    if (_disposed || _activeRetries >= maxConcurrentRetries) return;
    DateTime? target;
    final DateTime now = DateTime.now();
    for (final entry in _entries.values) {
      if (entry.running) continue;
      final DateTime candidate = entry.notBefore.isAfter(now)
          ? entry.notBefore
          : now.add(preferDebounce ? scanDebounce : Duration.zero);
      if (target == null || candidate.isBefore(target)) target = candidate;
    }
    if (target != null) _scheduleAt(target);
  }

  void _scheduleAt(DateTime target) {
    if (_disposed) return;
    final DateTime? scheduled = _scanScheduledAt;
    if (scheduled != null && !target.isBefore(scheduled)) return;
    _scanTimer?.cancel();
    final Duration delay = target.difference(DateTime.now());
    _scanScheduledAt = target;
    _scanTimer = Timer(delay.isNegative ? Duration.zero : delay, _scan);
  }

  bool _safeNearViewport(bool Function() callback) {
    try {
      return callback();
    } on Object {
      return false;
    }
  }

  static Duration _randomRetryDelay() =>
      Duration(milliseconds: 3000 + Random().nextInt(3001));
}

final class _ComicImageRetryEntry {
  _ComicImageRetryEntry({
    required this.isNearViewport,
    required this.retry,
    required this.attempts,
    required this.nearViewportImmediateUsed,
    required this.notBefore,
  });

  final bool Function() isNearViewport;
  final Future<void> Function() retry;
  DateTime notBefore;
  int attempts;
  bool nearViewportImmediateUsed;
  bool running = false;
}
