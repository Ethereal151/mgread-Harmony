import 'package:flutter/material.dart';

import 'package:mg_read/app/app_theme.dart';

/// Theme-colored surface behind a primary navigation page.
///
/// The style is retained as part of the shared page contract so each primary
/// page can keep its semantic composition, but decorative image backdrops are
/// intentionally not rendered. This keeps every theme's page background
/// faithful to its configured surface color.
enum AppPageBackdropStyle { home, search, discover, profile }

class AppPageBackdrop extends StatelessWidget {
  const AppPageBackdrop({required this.style, required this.child, super.key});

  final AppPageBackdropStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return ColoredBox(key: const Key('app-page-backdrop-surface'), color: tokens.pageBackground, child: child);
  }
}
