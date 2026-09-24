import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/app/app_theme.dart';

void main() {
  test('uses an OLED cool-black dark palette', () {
    final ThemeData theme = AppTheme.dark();
    final AppThemeTokens tokens = theme.extension<AppThemeTokens>()!;

    expect(tokens.pageBackground, const Color(0xFF000000));
    expect(tokens.surface, const Color(0xFF0B0E12));
    expect(tokens.featureSurface, const Color(0xFF131820));
    expect(tokens.accent, const Color(0xFF8AB4F8));
    expect(theme.colorScheme.onSurface, const Color(0xFFE8EDF3));
  });

  test('offers independent near-black dark palettes', () {
    final ThemeData theme = AppTheme.dark(color: AppDarkThemeColor.coolBlack);
    final AppThemeTokens tokens = theme.extension<AppThemeTokens>()!;

    expect(tokens.pageBackground, const Color(0xFF000000));
    expect(tokens.surface, const Color(0xFF08090B));
    expect(tokens.accent, const Color(0xFFD7DCE5));
    expect(AppDarkThemeColor.fromId('purpleBlack'), AppDarkThemeColor.purpleBlack);
  });

  test('connects Material component roles to every host palette', () {
    final themes = <ThemeData>[
      for (final color in AppThemeColor.values) AppTheme.light(color: color),
      for (final color in AppDarkThemeColor.values) AppTheme.dark(color: color),
    ];

    for (final theme in themes) {
      final AppThemeTokens tokens = theme.extension<AppThemeTokens>()!;
      final ColorScheme colors = theme.colorScheme;
      final bool isDark = colors.brightness == Brightness.dark;

      expect(colors.secondary, tokens.accent);
      expect(colors.secondaryContainer, tokens.accentSoft);
      expect(colors.error, tokens.notification);
      expect(colors.surfaceDim, isDark ? tokens.pageBackground : tokens.mutedSurface);
      expect(colors.surfaceBright, isDark ? tokens.featureSurface : tokens.surface);
      expect(colors.surfaceContainerLowest, isDark ? tokens.pageBackground : tokens.surface);
      expect(colors.surfaceContainerLow, tokens.surface);
      expect(colors.surfaceContainer, tokens.mutedSurface);
      expect(colors.surfaceContainerHigh, tokens.featureSurface);
      expect(colors.surfaceContainerHighest, tokens.featureSurface);
      expect(colors.onSurfaceVariant, tokens.mutedText);
      expect(colors.outline, tokens.mutedText);
      expect(colors.outlineVariant, tokens.divider);
      expect(colors.inversePrimary, tokens.accent);
      expect(colors.surfaceTint, Colors.transparent);
    }
  });

  test('keeps the reader-owned theme outside host palette mapping', () {
    final ThemeData theme = AppTheme.novelReader();
    final ColorScheme seeded = ColorScheme.fromSeed(seedColor: AppThemeColor.warm.accent, brightness: Brightness.light);

    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, AppThemeColor.warm.accent);
    expect(theme.colorScheme.surfaceContainerLow, seeded.surfaceContainerLow);
    expect(theme.colorScheme.surfaceContainerLow, isNot(AppTheme.light().colorScheme.surfaceContainerLow));
  });

  test('exposes the compact semantic typography scale globally', () {
    final textTheme = AppTheme.light().textTheme;

    expect(textTheme.displaySmall?.fontSize, AppTypography.display);
    expect(textTheme.titleLarge?.fontSize, AppTypography.sectionTitle);
    expect(textTheme.titleMedium?.fontSize, AppTypography.itemTitle);
    expect(textTheme.bodyLarge?.fontSize, AppTypography.body);
    expect(textTheme.bodyMedium?.fontSize, AppTypography.secondary);
    expect(textTheme.bodySmall?.fontSize, AppTypography.caption);
    expect(textTheme.labelLarge?.fontSize, AppTypography.action);
  });
}
