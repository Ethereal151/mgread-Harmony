import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

/// Keeps native ArkWeb pages alive for Runtime browser.session.v1 requests.
///
/// The surface is intentionally mounted at the application shell. Hidden
/// sessions remain mounted so their Cookie/Profile state survives between
/// Runtime calls; the native host controls visibility through its event
/// channel. On non-OHOS platforms this is an empty widget.
final class OhosBrowserSessionSurface extends StatefulWidget {
  const OhosBrowserSessionSurface({super.key, this.prewarm = false});

  /// Creates one hidden native ArkWeb view before the first session event.
  /// This is useful for integration harnesses whose first frame is otherwise
  /// occupied waiting for the Runtime request to return.
  final bool prewarm;

  @override
  State<OhosBrowserSessionSurface> createState() =>
      _OhosBrowserSessionSurfaceState();
}

final class _OhosBrowserSessionSurfaceState
    extends State<OhosBrowserSessionSurface> {
  StreamSubscription<Object?>? _events;
  final Map<String, bool> _sessions = <String, bool>{};

  @override
  void initState() {
    super.initState();
    if (Platform.operatingSystem == 'ohos') {
      _events = const EventChannel(
        'mgread_plugin_runtime/ohos_browser_session/events',
      ).receiveBroadcastStream().listen(_onEvent);
    }
  }

  void _onEvent(Object? value) {
    if (value is! Map) return;
    final pluginId = value['pluginId'];
    final action = value['action'];
    if (pluginId is! String || pluginId.isEmpty || action is! String) return;
    if (action == 'remove') {
      if (!mounted) return;
      setState(() => _sessions.remove(pluginId));
      return;
    }
    if (action == 'upsert' || action == 'visibility') {
      final visible = value['visible'];
      if (visible is! bool || !mounted) return;
      setState(() => _sessions[pluginId] = visible);
    }
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.operatingSystem != 'ohos' ||
        (_sessions.isEmpty && !widget.prewarm)) {
      return const SizedBox.shrink();
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (widget.prewarm)
          const Opacity(
            opacity: 0.001,
            child: OhosView(
              key: ValueKey<String>('mgread_ohos_arkweb_prewarm'),
              viewType: 'mgread_ohos_arkweb',
              creationParams: <String, Object?>{},
              creationParamsCodec: StandardMessageCodec(),
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            ),
          ),
        for (final entry in _sessions.entries)
          Opacity(
            // OHOS may skip creating a platform view whose opacity is exactly
            // zero. Keep hidden ArkWeb sessions mounted with a negligible
            // alpha so cookie/profile state and the native controller remain
            // available for the next Runtime request.
            opacity: entry.value ? 1 : 0.001,
            child: IgnorePointer(
              ignoring: !entry.value,
              child: OhosView(
                key: ValueKey<String>(entry.key),
                viewType: 'mgread_ohos_arkweb',
                creationParams: <String, Object?>{'pluginId': entry.key},
                creationParamsCodec: const StandardMessageCodec(),
                hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              ),
            ),
          ),
      ],
    );
  }
}
