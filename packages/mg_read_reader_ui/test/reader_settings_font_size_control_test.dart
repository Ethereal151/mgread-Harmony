import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader_ui/src/api/models.dart';
import 'package:novel_reader_ui/src/ui/reader_theme.dart';
import 'package:novel_reader_ui/src/ui/settings/reader_settings_font_size_control.dart';

void main() {
  final ReaderPalette palette = ReaderPalette.fromPreset(ReaderThemePreset.day);

  testWidgets('uses read-only value with plus and minus actions', (
    WidgetTester tester,
  ) async {
    final List<String> changes = <String>[];
    await tester.pumpWidget(
      _host(
        ReaderSettingsFontSizeControl(
          value: 18,
          min: 16,
          max: 32,
          palette: palette,
          onDecrease: () => changes.add('decrease'),
          onIncrease: () => changes.add('increase'),
        ),
      ),
    );

    expect(find.byType(Slider), findsNothing);
    expect(find.text('18'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('reader-settings-font-size-decrease')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('reader-settings-font-size-increase')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('reader-settings-font-size-value')),
    );

    expect(changes, <String>['decrease', 'increase']);
  });

  testWidgets('keeps the progress bar on the typography subpage', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReaderSettingsFontSizeControl(
          value: 18,
          min: 16,
          max: 32,
          palette: palette,
          showProgress: true,
          onDecrease: () {},
          onIncrease: () {},
          onProgressChanged: (_) {},
          onProgressChangeEnd: (_) {},
        ),
      ),
    );

    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
  });
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 260, child: child)),
  ),
);
