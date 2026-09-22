/// 调试日志查看页面。
///
/// 职责：
/// - 默认展示当前进程的有界实时事件，并允许切换历史日志文件。
/// - 管理当前来源的有界详情捕获和按需附件读取。
/// - 集中提供数据源 Runtime 检查页开关与访问地址。
/// - 恢复并保存“标准日志 / 实时详情”偏好。
///
/// 注意：
/// - 文件列表不得加载事件；单文件损坏不能影响其他文件。
/// - 页面销毁时必须停止自己创建的捕获会话，不能在 build() 中发起 IO。
///
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/features/diagnostics/application/diagnostics_activation.dart';
import 'package:mg_read/features/diagnostics/application/diagnostics_capture_preference_store.dart';
import 'package:mg_read/shared/presentation/widgets/app_secondary_page_chrome.dart';
import 'package:mg_read/features/diagnostics/application/diagnostics_viewer_gateway.dart';
import 'package:mg_read/features/diagnostics/presentation/widgets/diagnostics_viewer_controls.dart';
import 'package:mg_read/features/diagnostics/presentation/widgets/runtime_debug_panel.dart';
import 'package:mg_read/features/profile/presentation/widgets/profile_detail_chrome.dart';
import 'package:mg_read/shared/presentation/app_navigation_destination.dart';

part 'widgets/diagnostics_viewer_log_widgets.dart';

/// Dedicated, bounded viewer for app and Runtime diagnostic TXT records.
class DiagnosticsViewerPage extends ConsumerStatefulWidget {
  const DiagnosticsViewerPage({required this.onBackRequested, required this.onDestinationRequested, super.key});

  final VoidCallback onBackRequested;
  final ValueChanged<AppNavigationDestination> onDestinationRequested;

  @override
  ConsumerState<DiagnosticsViewerPage> createState() => _DiagnosticsViewerPageState();
}

class _DiagnosticsViewerPageState extends ConsumerState<DiagnosticsViewerPage> {
  static const int _maximumRetainedEvents = 500;
  static const int _maximumRetainedPreviews = 8;

  late final DiagnosticsViewerGateway _gateway;
  late final DiagnosticsCapturePreferenceStore _capturePreferenceStore;
  DiagnosticsActivation? _activation;
  static const DiagnosticsViewerSource _source = DiagnosticsViewerSource.app;
  List<DiagnosticsViewerLogFile> _logFiles = const <DiagnosticsViewerLogFile>[];
  DiagnosticsViewerLogFile? _selectedLogFile;
  List<DiagnosticsViewerEvent> _events = const <DiagnosticsViewerEvent>[];
  final Map<String, DiagnosticsViewerEventDetails> _details = <String, DiagnosticsViewerEventDetails>{};
  final Set<String> _loadingDetails = <String>{};
  final Map<String, String> _detailErrors = <String, String>{};
  final Map<String, String> _previews = <String, String>{};
  final Set<String> _loadingPreviews = <String>{};
  String? _nextCursor;
  String? _expandedEvent;
  String? _loadError;
  String? _captureError;
  DiagnosticsViewerCapture? _capture;
  var _loading = true;
  var _loadingMore = false;
  var _captureBusy = false;
  var _diagnosticsEnabled = false;
  var _activationBusy = false;
  var _generation = 0;
  StreamSubscription<void>? _liveSubscription;
  Timer? _liveRefreshDebounce;

  @override
  void initState() {
    super.initState();
    _gateway = ref.read(diagnosticsViewerGatewayProvider);
    _capturePreferenceStore = ref.read(diagnosticsCapturePreferenceStoreProvider);
    _activation = ref.read(diagnosticsActivationProvider);
    _liveSubscription = _gateway.watchLiveEvents().listen(_onLiveEvent);
    scheduleMicrotask(() {
      unawaited(_loadLifecycle());
    });
  }

  @override
  void dispose() {
    _generation += 1;
    _liveRefreshDebounce?.cancel();
    unawaited(_liveSubscription?.cancel());
    final capture = _capture;
    if (capture != null) {
      unawaited(_gateway.stopCapture(capture).catchError((_) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: AppSecondaryPageContent(
          child: Column(
            children: <Widget>[
              ProfileDetailTopBar(title: '调试中心', onBack: widget.onBackRequested),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadLogFiles,
                  child: CustomScrollView(
                    key: const Key('diagnostics-viewer-content'),
                    slivers: <Widget>[
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.comfortable,
                          AppSpacing.regular,
                          AppSpacing.comfortable,
                          AppDetailMetrics.bottomNavigationContentBottomPadding + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        sliver: SliverList.list(
                          children: <Widget>[
                            _DiagnosticsLifecyclePanel(
                              enabledPreference: _diagnosticsEnabled,
                              enabledForCurrentRun: _activation?.enabledForCurrentRun ?? _diagnosticsEnabled,
                              busy: _activationBusy,
                              onChanged: _changeDiagnosticsEnabled,
                            ),
                            const SizedBox(height: AppSpacing.regular),
                            DiagnosticsViewerCapturePanel(
                              mode: _capture?.mode ?? DiagnosticsDetailMode.off,
                              busy: _captureBusy,
                              warningCode: _capture?.warningCode,
                              errorCode: _captureError,
                              onModeSelected: _changeCaptureMode,
                            ),
                            const SizedBox(height: AppSpacing.regular),
                            _LogFilePicker(
                              files: _logFiles,
                              selectedFileId: _selectedLogFile?.fileId,
                              onSelected: _selectLogFile,
                              onDelete: _deleteSelectedLog,
                              onExport: _exportSelectedLog,
                            ),
                            const SizedBox(height: AppSpacing.regular),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.all(AppSpacing.page),
                                child: Center(child: CircularProgressIndicator(key: Key('diagnostics-viewer-loading'))),
                              )
                            else if (_loadError != null)
                              _LoadFailure(errorCode: _loadError!, onRetry: () => _loadEvents(reset: true))
                            else if (_selectedLogFile == null)
                              const _SelectLogFile()
                            else if (_events.isEmpty)
                              _EmptyEvents(isLive: _selectedLogFile?.isLive ?? false)
                            else
                              ..._events.map(_buildEventCard),
                            if (!_loading && _nextCursor != null)
                              Padding(
                                padding: const EdgeInsets.only(top: AppSpacing.compact),
                                child: OutlinedButton.icon(
                                  key: const Key('diagnostics-load-more'),
                                  onPressed: _loadingMore ? null : () => _loadEvents(reset: false),
                                  icon: _loadingMore
                                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.expand_more_rounded),
                                  label: Text(_loadingMore ? '正在读取…' : '读取更早日志'),
                                ),
                              ),
                            const SizedBox(height: AppSpacing.regular),
                            const RuntimeDebugPanel(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ProfileDetailBottomBar(onSelected: widget.onDestinationRequested),
    );
  }

  Future<void> _loadLifecycle() async {
    try {
      final enabled = await _capturePreferenceStore.loadDiagnosticsEnabled();
      if (!mounted) return;
      setState(() {
        _diagnosticsEnabled = enabled;
        _loading = false;
      });
      await _loadLogFiles();
      if (enabled || (_activation?.enabledForCurrentRun ?? false)) {
        await _restoreCaptureMode();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _viewerErrorCode(error);
        _loading = false;
      });
    }
  }

  Future<void> _changeDiagnosticsEnabled(bool enabled) async {
    if (_activationBusy) return;
    setState(() {
      _activationBusy = true;
      _loadError = null;
    });
    try {
      if (enabled) {
        final activation = _activation;
        final active = activation == null ? true : await activation.enableForCurrentRun();
        if (!active) throw StateError('diagnostics_activation_failed');
        if (activation == null) {
          await _capturePreferenceStore.saveDiagnosticsEnabled(true);
        }
        if (!mounted) return;
        setState(() {
          _diagnosticsEnabled = true;
        });
        await _loadLogFiles();
      } else {
        final activation = _activation;
        if (activation == null) {
          await _capturePreferenceStore.saveDiagnosticsEnabled(false);
        } else {
          await activation.disableOnNextLaunch();
        }
        if (!mounted) return;
        setState(() {
          _diagnosticsEnabled = false;
        });
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _viewerErrorCode(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _activationBusy = false;
        });
      }
    }
  }

  Future<void> _loadLogFiles() async {
    final files = await _gateway.listLogFiles();
    if (!mounted) return;
    final previousFileId = _selectedLogFile?.fileId;
    DiagnosticsViewerLogFile? selected;
    for (final file in files) {
      if (file.fileId == previousFileId) {
        selected = file;
        break;
      }
    }
    selected ??= files.isEmpty ? null : files.first;
    setState(() {
      _logFiles = files;
      _selectedLogFile = selected;
      _events = const <DiagnosticsViewerEvent>[];
      _nextCursor = null;
      _loading = false;
    });
    if (selected != null) await _loadEvents(reset: true);
  }

  Future<void> _selectLogFile(DiagnosticsViewerLogFile file) async {
    if (_selectedLogFile?.fileId == file.fileId) return;
    setState(() {
      _selectedLogFile = file;
    });
    await _loadEvents(reset: true);
  }

  Future<void> _deleteSelectedLog() async {
    final file = _selectedLogFile;
    if (file == null || file.isCurrent) return;
    try {
      await _gateway.deleteLogFile(file.fileId);
      await _loadLogFiles();
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = _viewerErrorCode(error));
    }
  }

  Future<void> _exportSelectedLog() async {
    final file = _selectedLogFile;
    if (file == null) return;
    try {
      final result = await _gateway.exportLogFile(file.fileId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出 ${result.byteLength} 字节')));
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = _viewerErrorCode(error));
    }
  }

  Widget _buildEventCard(DiagnosticsViewerEvent event) {
    final expanded = _expandedEvent == event.identity;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.compact),
      child: _EventCard(
        event: event,
        expanded: expanded,
        details: _details[event.identity],
        loadingDetails: _loadingDetails.contains(event.identity),
        detailError: _detailErrors[event.identity],
        previews: _previews,
        loadingPreviews: _loadingPreviews,
        onToggle: () => _toggleEvent(event),
        onPreview: _loadPreview,
      ),
    );
  }

  Future<void> _loadEvents({required bool reset, bool passive = false}) async {
    if (!mounted) return;
    final selected = _selectedLogFile;
    if (selected == null) return;
    if (!reset && (_loadingMore || _nextCursor == null)) return;
    final generation = ++_generation;
    final source = _source;
    setState(() {
      if (reset) {
        _loading = !passive;
        _loadError = null;
        if (!passive) _events = const <DiagnosticsViewerEvent>[];
        _nextCursor = null;
        if (!passive) {
          _expandedEvent = null;
          _details.clear();
          _detailErrors.clear();
          _previews.clear();
        }
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await _gateway.listEvents(source: source, logFileId: selected.fileId, cursor: reset ? null : _nextCursor);
      if (!mounted || generation != _generation || source != _source || _selectedLogFile?.fileId != selected.fileId) return;
      setState(() {
        final combined = reset ? page.items : <DiagnosticsViewerEvent>[..._events, ...page.items];
        _events = List<DiagnosticsViewerEvent>.unmodifiable(combined.take(_maximumRetainedEvents));
        _nextCursor = combined.length >= _maximumRetainedEvents ? null : page.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation || source != _source) return;
      setState(() {
        _loadError = _viewerErrorCode(error);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onLiveEvent(void _) {
    if (!mounted || _selectedLogFile?.isLive != true) return;
    _liveRefreshDebounce?.cancel();
    _liveRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _selectedLogFile?.isLive != true || _loading || _loadingMore) return;
      unawaited(_loadEvents(reset: true, passive: true));
    });
  }

  Future<void> _restoreCaptureMode() async {
    try {
      final realtimeDetailsEnabled = await _capturePreferenceStore.loadRealtimeDetailsEnabled();
      if (!mounted || !realtimeDetailsEnabled) return;
      await _changeCaptureMode(DiagnosticsDetailMode.memoryOnly, persistPreference: false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _captureError = _viewerErrorCode(error);
      });
    }
  }

  Future<void> _changeCaptureMode(DiagnosticsDetailMode mode, {bool persistPreference = true}) async {
    if (!mounted) return;
    if (_captureBusy || (_capture?.mode == mode && _capture?.source == _source)) {
      return;
    }
    if (mode != DiagnosticsDetailMode.off && !(_activation?.enabledForCurrentRun ?? _diagnosticsEnabled)) {
      setState(() {
        _captureError = 'diagnostics_disabled';
      });
      return;
    }
    setState(() {
      _captureBusy = true;
      _captureError = null;
    });
    final previous = _capture;
    if (previous != null) {
      try {
        await _gateway.stopCapture(previous);
      } on Object catch (error) {
        if (!mounted) return;
        setState(() {
          _captureBusy = false;
          _captureError = _viewerErrorCode(error);
        });
        return;
      }
      if (!mounted) return;
      _capture = null;
    }
    if (mode == DiagnosticsDetailMode.off) {
      setState(() {
        _captureBusy = false;
      });
      if (persistPreference) {
        await _saveCapturePreference(realtimeDetailsEnabled: false);
      }
      return;
    }
    try {
      final capture = await _gateway.startCapture(mode: mode, source: _source);
      if (!mounted) {
        unawaited(_gateway.stopCapture(capture).catchError((_) {}));
        return;
      }
      setState(() {
        _capture = capture;
        _captureBusy = false;
      });
      if (persistPreference && mode == DiagnosticsDetailMode.memoryOnly) {
        await _saveCapturePreference(realtimeDetailsEnabled: true);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _captureError = _viewerErrorCode(error);
        _captureBusy = false;
      });
    }
  }

  Future<void> _saveCapturePreference({required bool realtimeDetailsEnabled}) async {
    try {
      await _capturePreferenceStore.saveRealtimeDetailsEnabled(realtimeDetailsEnabled);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _captureError = _viewerErrorCode(error);
      });
    }
  }

  Future<void> _toggleEvent(DiagnosticsViewerEvent event) async {
    if (_expandedEvent == event.identity) {
      setState(() {
        _expandedEvent = null;
      });
      return;
    }
    setState(() {
      _expandedEvent = event.identity;
    });
    if (_details.containsKey(event.identity) || _loadingDetails.contains(event.identity)) {
      return;
    }
    setState(() {
      _loadingDetails.add(event.identity);
      _detailErrors.remove(event.identity);
    });
    try {
      final details = await _gateway.loadEventDetails(event);
      if (!mounted) return;
      setState(() {
        _loadingDetails.remove(event.identity);
        _details[event.identity] = details;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDetails.remove(event.identity);
        _detailErrors[event.identity] = _viewerErrorCode(error);
      });
    }
  }

  Future<void> _loadPreview(DiagnosticsViewerAttachment attachment) async {
    if (_previews.containsKey(attachment.identity) || _loadingPreviews.contains(attachment.identity)) {
      return;
    }
    setState(() {
      _loadingPreviews.add(attachment.identity);
    });
    try {
      final preview = await _gateway.readAttachmentPreview(attachment);
      if (!mounted) return;
      setState(() {
        _loadingPreviews.remove(attachment.identity);
        if (_previews.length >= _maximumRetainedPreviews) {
          _previews.remove(_previews.keys.first);
        }
        _previews[attachment.identity] = preview;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPreviews.remove(attachment.identity);
        _previews[attachment.identity] = '预览失败：${_viewerErrorCode(error)}';
      });
    }
  }
}
