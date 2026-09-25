import 'package:flutter/material.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/shared/presentation/widgets/app_system_ui_style.dart';

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
    return AppSystemUiStyle(
      statusBarColor: style == AppPageBackdropStyle.home ? tokens.featureSurface : tokens.pageBackground,
      navigationBarColor: tokens.pageBackground,
      child: ColoredBox(key: const Key('app-page-backdrop-surface'), color: tokens.pageBackground, child: child),
    );
  }
}
