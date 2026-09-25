/// 应用页面的系统栏视觉同步层。
///
/// 职责：
/// - 将 Flutter 页面实际使用的上下背景色声明给系统栏。
/// - 在鸿蒙上同步原生窗口属性，避免媒体窗口退出后残留系统默认颜色。
/// - 在应用进入/离开最近任务时重新同步原生窗口属性，避免系统栏回退到默认色。
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
  Brightness? _lastBrightness;

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
    if (state != AppLifecycleState.detached) {
      unawaited(_syncNative());
    }
  }

  @override
  void didUpdateWidget(covariant AppSystemUiStyle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statusBarColor != widget.statusBarColor || oldWidget.navigationBarColor != widget.navigationBarColor) {
      unawaited(_syncNative());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_lastBrightness != brightness) {
      _lastBrightness = brightness;
      unawaited(_syncNative());
    }
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
