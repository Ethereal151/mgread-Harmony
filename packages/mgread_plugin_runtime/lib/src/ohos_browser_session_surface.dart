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
          _buildSessionView(
            pluginId: 'mgread_ohos_arkweb_prewarm',
            visible: false,
            creationParams: const <String, Object?>{},
          ),
        for (final entry in _sessions.entries)
          _buildSessionView(
            pluginId: entry.key,
            visible: entry.value,
            creationParams: <String, Object?>{'pluginId': entry.key},
          ),
      ],
    );
  }

  Widget _buildSessionView({
    required String pluginId,
    required bool visible,
    required Map<String, Object?> creationParams,
  }) {
    final Widget view = Opacity(
      // OHOS may skip creating a platform view whose opacity is exactly zero.
      // Keep hidden ArkWeb sessions mounted with a negligible alpha so their
      // Cookie/Profile state and native controller survive between requests.
      opacity: visible ? 1 : 0.001,
      child: IgnorePointer(
        ignoring: !visible,
        child: OhosView(
          key: ValueKey<String>(pluginId),
          viewType: 'mgread_ohos_arkweb',
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
      ),
    );
    if (visible) return Positioned.fill(child: view);

    // A hidden platform view must stay mounted for the browser session, but a
    // full-screen transparent ArkWeb surface still participates in OHOS
    // composition and can make Flutter reject later SurfaceFrames. Keep its
    // native state alive in a tiny footprint until it is shown.
    return Positioned(left: 0, top: 0, width: 1, height: 1, child: view);
  }
}
