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
