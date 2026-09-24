/// Shared source-brand fallback theme regression coverage.
///
/// Verifies generated source marks remain legible when the host accent uses a
/// light foreground contrast pair. No network or Runtime is involved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/shared/presentation/source_branding.dart';

void main() {
  testWidgets('fallback source glyph uses the active accent foreground', (tester) async {
    final ThemeData theme = AppTheme.dark(color: AppDarkThemeColor.coolBlack);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Center(
          child: SourceIcon(sourceId: 'org.example.source', displayName: '示例源', iconUrl: null),
        ),
      ),
    );

    final Text glyph = tester.widget<Text>(find.text('示'));
    expect(glyph.style?.color, theme.colorScheme.onPrimary);
    expect(glyph.style?.color, isNot(Colors.white));
  });
}
