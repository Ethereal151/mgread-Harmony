import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader_ui/src/api/models.dart';
import 'package:novel_reader_ui/src/core/auto_reading_coordinator.dart';
import 'package:novel_reader_ui/src/platform/reader_platform.dart';
import 'package:novel_reader_ui/src/ui/reader_strings.dart';
import 'package:novel_reader_ui/src/ui/reader_theme.dart';
import 'package:novel_reader_ui/src/ui/settings/reader_settings_controls.dart';
import 'package:novel_reader_ui/src/ui/settings/reader_settings_font_size_control.dart';
import 'package:novel_reader_ui/src/ui/settings/reader_settings_sheet.dart';

void main() {
  test('OHOS volume-key page turning uses the native reader bridge', () async {
    final platform = MethodChannelReaderPlatform(operatingSystem: 'ohos');
    final calls = <MethodCall>[];
    const channel = MethodChannel('novel_reader_ui/system');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await platform.setVolumeKeyPageTurningEnabled(true);
    await platform.setVolumeKeyPageTurningEnabled(false);

    expect(calls.map((call) => call.method), [
      'setVolumeKeyPageTurningEnabled',
      'setVolumeKeyPageTurningEnabled',
    ]);
    expect(calls.first.arguments, {'enabled': true});
    expect(calls.last.arguments, {'enabled': false});
  });

  testWidgets('font controls share one adaptive row with a section label', (
    WidgetTester tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 500));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final Finder sizeControl = find.byType(ReaderSettingsFontSizeControl);
    final Finder fontControl = find.ancestor(
      of: find.text(ReaderStrings.miSans),
      matching: find.byType(ReaderSettingsCapsule),
    );
    final Rect sizeRect = tester.getRect(sizeControl);
    final Rect fontRect = tester.getRect(fontControl);

    expect(find.text(ReaderStrings.fontSize), findsOneWidget);
    expect(sizeRect.top, fontRect.top);
    expect(sizeRect.height, fontRect.height);
    expect(sizeRect.width, closeTo(fontRect.width, 1));
    expect(fontRect.right, lessThanOrEqualTo(360));

    await tester.binding.setSurfaceSize(const Size(600, 500));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final Finder resizedFontControl = find.ancestor(
      of: find.text(ReaderStrings.miSans),
      matching: find.byType(ReaderSettingsCapsule),
    );
    expect(
      tester.getRect(resizedFontControl).width,
      greaterThan(fontRect.width),
    );

    await tester.tap(resizedFontControl);
    await tester.pumpAndSettle();
    expect(find.text(ReaderStrings.fontSize), findsOneWidget);
  });
}

Widget _host() {
  return MaterialApp(
    home: ReaderSettingsSheet(
      preferences: TextReaderPreferences.defaults,
      palette: ReaderPalette.fromPreset(ReaderThemePreset.day),
      platformCapabilities: const ReaderPlatformCapabilities(),
      commentsAvailable: false,
      autoReading: false,
      autoReadingPace: ReaderAutoReadingPace.normal,
      layoutDebugMode: false,
      fontRepository: null,
      onCustomFontSelected: (ReaderFontDescriptor _, String _) async {},
      onFontError: (_) {},
      onPreferencesPreview: (_) {},
      onPreferencesCommit: (_) {},
      onAutoReadingChanged: (_) {},
      onAutoReadingPaceChanged: (_) {},
      onLayoutDebugModeChanged: (_) {},
      onCatalogPressed: () {},
      onBookmarksPressed: () {},
    ),
  );
}
