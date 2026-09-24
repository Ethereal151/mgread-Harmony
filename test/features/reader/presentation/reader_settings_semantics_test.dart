import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader_ui/novel_reader_ui.dart';

void main() {
  testWidgets('reader controls and settings lock content interactions', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextReaderView(
            bookId: 'settings-interaction-book',
            dataSource: const _SettingsSemanticsDataSource(),
            stateStore: const _SettingsSemanticsStateStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextReaderView));
    await tester.pumpAndSettle();

    final Finder settings = find.byKey(const Key('reader-toolbar-settings'));
    final Finder readerSurface = find.byKey(const ValueKey<String>('reader-content-surface'));
    final Finder readerScrollable = find.descendant(of: readerSurface, matching: find.byType(Scrollable));
    expect(readerScrollable, findsOneWidget);
    final Finder controlsLock = find.byKey(const ValueKey<String>('reader-controls-interaction-lock'));
    expect(controlsLock, findsOneWidget);
    final ScrollableState locked = tester.state<ScrollableState>(readerScrollable);
    expect(locked.position.physics.shouldAcceptUserOffset(locked.position), isFalse);
    final double offsetBeforeDrag = locked.position.pixels;
    await tester.drag(controlsLock, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(locked.position.pixels, offsetBeforeDrag);

    await tester.tapAt(tester.getCenter(readerSurface));
    await tester.pumpAndSettle();
    expect(controlsLock, findsNothing);

    await tester.tapAt(tester.getCenter(readerSurface));
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('reader-settings-interaction-lock')), findsOneWidget);

    final Finder settingsSheet = find.byWidgetPredicate((Widget widget) => widget.runtimeType.toString() == 'ReaderSettingsSheet');
    final double sheetTop = tester.getTopLeft(settingsSheet).dy;
    await tester.tapAt(Offset(20, sheetTop - 8));
    await tester.pumpAndSettle();
    expect(settingsSheet, findsNothing);

    await tester.tap(settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('自动阅读速度'), findsOneWidget);

    final Finder layoutDebugMode = find.ancestor(of: find.text('排版调试模式'), matching: find.byType(SwitchListTile));
    expect(layoutDebugMode, findsOneWidget);
    await tester.tap(find.descendant(of: layoutDebugMode, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('reader-layout-debug-overlay')), findsOneWidget);
    expect(find.textContaining('顶部空白'), findsOneWidget);

    final double subpageTop = tester.getTopLeft(settingsSheet).dy;
    await tester.tapAt(Offset(20, subpageTop - 8));
    await tester.pumpAndSettle();
    expect(settingsSheet, findsNothing);
    expect(find.text('自动阅读速度'), findsNothing);
  });

  testWidgets('single-hand mode keeps the centre tap available for controls', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextReaderView(
            bookId: 'single-hand-mode-book',
            dataSource: const _SettingsSemanticsDataSource(),
            stateStore: const _SettingsSemanticsStateStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextReaderView));
    await tester.pumpAndSettle();
    final Finder settings = find.byKey(const Key('reader-toolbar-settings'));
    await tester.tap(settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();

    final Finder singleHandMode = find.ancestor(of: find.text('单手模式'), matching: find.byType(SwitchListTile));
    await tester.tap(find.descendant(of: singleHandMode, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    final Finder singleHandSwitch = find.descendant(of: singleHandMode, matching: find.byType(Switch));
    expect(tester.widget<Switch>(singleHandSwitch).value, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final Finder readerSurface = find.byKey(const ValueKey<String>('reader-content-surface'));
    final Finder controlsGate = find.ancestor(of: settings, matching: find.byType(IgnorePointer));
    await tester.tapAt(tester.getCenter(readerSurface));
    await tester.pumpAndSettle();
    expect(tester.widgetList<IgnorePointer>(controlsGate).map((IgnorePointer widget) => widget.ignoring), contains(isTrue));

    await tester.tapAt(tester.getCenter(readerSurface));
    await tester.pumpAndSettle();
    expect(tester.widgetList<IgnorePointer>(controlsGate).map((IgnorePointer widget) => widget.ignoring), isNot(contains(isTrue)));
  });

  testWidgets('repeatedly opening and dismissing reader settings keeps semantics valid', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(padding: const EdgeInsets.only(bottom: 20), viewPadding: const EdgeInsets.only(bottom: 20)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: Scaffold(
            body: TextReaderView(
              bookId: 'settings-semantics-book',
              dataSource: const _SettingsSemanticsDataSource(),
              stateStore: const _SettingsSemanticsStateStore(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextReaderView));
      await tester.pumpAndSettle();

      final Finder settings = find.byKey(const Key('reader-toolbar-settings'));
      expect(settings, findsOneWidget);

      double? expectedSheetTop;
      double? expectedBrightnessOffset;
      for (int cycle = 0; cycle < 4; cycle += 1) {
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(find.text('亮度'), findsOneWidget);

        final Finder settingsSheet = find.byWidgetPredicate((Widget widget) => widget.runtimeType.toString() == 'ReaderSettingsSheet');
        final double sheetTop = tester.getTopLeft(settingsSheet).dy;
        final double brightnessOffset = tester.getTopLeft(find.text('亮度')).dy - sheetTop;
        expectedSheetTop ??= sheetTop;
        expectedBrightnessOffset ??= brightnessOffset;
        expect(sheetTop, closeTo(expectedSheetTop, 0.01), reason: 'sheet cycle $cycle');
        expect(brightnessOffset, closeTo(expectedBrightnessOffset, 0.01), reason: 'main page cycle $cycle');

        final Finder bottomNavigation = find.byWidgetPredicate(
          (Widget widget) => widget.runtimeType.toString() == 'ReaderSettingsBottomNavigation',
        );
        final double viewHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
        expect(tester.getBottomRight(bottomNavigation).dy, closeTo(viewHeight - 20, 0.01));

        if (cycle == 0) {
          await tester.tap(find.text('更多'));
          await tester.pumpAndSettle();
          expect(find.text('自动阅读速度'), findsOneWidget);
          final Finder subpageHeader = find.byWidgetPredicate(
            (Widget widget) => widget.runtimeType.toString() == 'ReaderSettingsSubpageHeader',
          );
          final Finder autoReadingTile = find.ancestor(of: find.text('自动阅读'), matching: find.byType(SwitchListTile));
          final Offset moreTitle = tester.getTopLeft(find.text('更多').last);
          final Offset autoTitle = tester.getTopLeft(find.text('自动阅读速度'));
          final Rect headerRect = tester.getRect(subpageHeader);
          final Rect autoReadingRect = tester.getRect(autoReadingTile);
          // Keep the subpage anchored to the sheet while preserving the full
          // 48dp switch touch target and placing the following row directly
          // after it. This detects real route drift without assuming the old
          // compressed SwitchListTile geometry.
          expect(settingsSheet, findsOneWidget);
          expect(moreTitle.dy - sheetTop, lessThan(72));
          expect(headerRect.top - sheetTop, closeTo(6, 0.01));
          expect(autoReadingRect.top - headerRect.bottom, closeTo(4, 0.01));
          expect(autoReadingRect.height, closeTo(48, 0.01));
          expect(autoTitle.dy, greaterThanOrEqualTo(autoReadingRect.bottom));
          expect(autoTitle.dy - autoReadingRect.bottom, lessThan(48));
          expect(find.text('单手模式'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.text('自动阅读速度'), findsNothing);
        }

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(settings, findsOneWidget);
        expect(settingsSheet, findsNothing);
        expect(find.text('亮度'), findsNothing);
        expect(tester.takeException(), isNull, reason: 'cycle $cycle');
      }
    } finally {
      semantics.dispose();
    }
  });
}

final class _SettingsSemanticsDataSource implements TextReaderDataSource {
  const _SettingsSemanticsDataSource();

  static const ReaderChapterInfo _chapter = ReaderChapterInfo(id: 'chapter-1', title: '第一章', index: 0);

  @override
  Future<ReaderBookInfo> loadBookInfo(String bookId) async => ReaderBookInfo(id: bookId, title: '设置语义测试书', author: '测试作者');

  @override
  Future<ChapterCatalogPage> loadChapterCatalog(String bookId, {String? cursor, int pageSize = 100}) async =>
      ChapterCatalogPage(items: <ReaderChapterInfo>[_chapter], total: 1, hasMore: false);

  @override
  Future<ReaderChapterInfo> loadChapterAtIndex(String bookId, int index) async {
    if (index != 0) throw RangeError.index(index, const <int>[0]);
    return _chapter;
  }

  @override
  Future<TextChapterContent> loadChapterContent(String bookId, String chapterId) async => TextChapterContent(
    chapterId: 'chapter-1',
    title: '第一章',
    paragraphs: <TextParagraph>[TextParagraph(id: 'paragraph-1', text: '用于验证阅读设置反复开关时的语义树。')],
  );
}

final class _SettingsSemanticsStateStore implements TextReaderStateStore {
  const _SettingsSemanticsStateStore();

  @override
  Future<List<ReaderBookmark>> loadBookmarks(String bookId) async => const <ReaderBookmark>[];

  @override
  Future<TextReaderPreferences?> loadPreferences() async => null;

  @override
  Future<ReaderProgress?> loadProgress(String bookId) async => const ReaderProgress(chapterId: 'chapter-1', paragraphId: 'paragraph-1');

  @override
  Future<void> addBookmark(ReaderBookmark bookmark) async {}

  @override
  Future<void> removeBookmark(String bookId, String bookmarkId) async {}

  @override
  Future<void> savePreferences(TextReaderPreferences preferences) async {}

  @override
  Future<void> saveProgress(String bookId, ReaderProgress progress) async {}
}
