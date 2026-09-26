/// 应用页面的系统栏视觉同步层。
///
/// 职责：
/// - 将 Flutter 页面实际使用的上下背景色声明给系统栏。
/// - 在鸿蒙上同步原生窗口属性，避免媒体窗口退出后残留系统默认颜色。
/// - 在应用恢复前台时重新同步当前页面的原生窗口属性，避免系统栏回退到默认色。
/// - 保留播放器等更深层 [AnnotatedRegion] 对沉浸式页面的覆盖能力。
///
/// 注意：
/// - 不改变窗口尺寸、方向或沉浸式生命周期；这些仍由媒体/阅读器 owner 管理。
/// - 原生同步失败不得影响页面渲染，Flutter 的 [AnnotatedRegion] 仍然生效。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:novel_reader_ui/novel_reader_ui.dart';

/// Supplies page-owned colors for both Flutter and native system bars.
final class AppSystemUiStyle extends StatefulWidget {
  const AppSystemUiStyle({required this.statusBarColor, required this.navigationBarColor, required this.child, super.key});

  final Color statusBarColor;
  final Color navigationBarColor;
  final Widget child;

  @override
  State<AppSystemUiStyle> createState() => _AppSystemUiStyleState();
}

final class _AppSystemUiStyleState extends State<AppSystemUiStyle> with WidgetsBindingObserver {
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleNativeSync();
    }
  }

  @override
  void didUpdateWidget(covariant AppSystemUiStyle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statusBarColor != widget.statusBarColor || oldWidget.navigationBarColor != widget.navigationBarColor) {
      _scheduleNativeSync();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route and tab visibility as well as theme changes. A page
    // kept alive behind a reader/player must not change the foreground bars.
    ModalRoute.of(context);
    TickerMode.of(context);
    Theme.of(context);
    _scheduleNativeSync();
  }

  void _scheduleNativeSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted || !TickerMode.of(context) || ModalRoute.of(context)?.isCurrent == false) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
      unawaited(_syncNative());
    });
  }

  Future<void> _syncNative() async {
    try {
      final contentColor = Theme.of(context).colorScheme.onSurface;
      await ReaderPlatform.instance.setApplicationSystemUiStyle(
        statusBarColor: _colorHex(widget.statusBarColor),
        navigationBarColor: _colorHex(widget.navigationBarColor),
        statusBarContentColor: _colorHex(contentColor),
        navigationBarContentColor: _colorHex(contentColor),
      );
    } on Object {
      // Flutter's overlay region remains the local fallback on unsupported or
      // older hosts.
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = Theme.of(context).brightness == Brightness.dark;
    final iconBrightness = darkTheme ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: widget.statusBarColor,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: darkTheme ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: widget.navigationBarColor,
        systemNavigationBarDividerColor: widget.navigationBarColor,
        systemNavigationBarIconBrightness: iconBrightness,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: widget.child,
    );
  }
}

String _colorHex(Color color) => '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
