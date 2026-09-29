/// Exercises visible content and gestures while chapter pagination is pending.
/// Fake time deliberately advances one batch at a time instead of settling
/// before the first interaction, as a slow device can expose these frames.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_reader_ui/novel_reader_ui.dart';

void main() {
  testWidgets(
    'restored text never flashes the chapter prefix between batches',
    (WidgetTester tester) async {
      final controller = TextReaderController();
      await _open(tester, controller, anchor: 60);
      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(
          _visibleText(tester),
          contains('锚点段60'),
          reason: 'batch $frame must preserve the restored reading location',
        );
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('pagination completion preserves an active drag controller', (
    WidgetTester tester,
  ) async {
    final controller = TextReaderController();
    await _open(tester, controller);
    final pages = tester.widget<PageView>(find.byType(PageView));
    final gesture = await tester.startGesture(const Offset(300, 250));
    await gesture.moveBy(const Offset(-30, 0));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    final double dragPosition = pages.controller!.page!;
    expect(dragPosition, greaterThan(1));
    expect(dragPosition, lessThan(2));
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller,
        same(pages.controller),
        reason: 'finishing pagination must not detach the in-flight gesture',
      );
      expect(pages.controller!.page, closeTo(dragPosition, .001));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('swiping the pending prefix does not skip to the next chapter', (
    WidgetTester tester,
  ) async {
    final controller = TextReaderController();
    final source = _Source();
    await _open(tester, controller, source: source);
    final pageView = tester.widget<PageView>(find.byType(PageView));
    final delegate = pageView.childrenDelegate as SliverChildBuilderDelegate;
    final int lastRawIndex = delegate.childCount! - 1;
    pageView.controller!.jumpToPage(lastRawIndex);
    await tester.pump();
    expect(controller.snapshot.chapter?.id, 'chapter-1');
    expect(source.loadedChapters, isNot(contains('chapter-2')));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('a next tap at the pending prefix resumes once layout is ready', (
    WidgetTester tester,
  ) async {
    final controller = TextReaderController();
    await _open(tester, controller, animation: ReaderPageAnimation.none);
    final pages = tester.widget<PageView>(find.byType(PageView));
    final delegate = pages.childrenDelegate as SliverChildBuilderDelegate;
    final int prefixEnd = delegate.childCount! - 1;
    expect(prefixEnd, greaterThan(5));
    pages.controller!.jumpToPage(prefixEnd);
    await tester.pump();
    var completed = false;
    final turn = controller.nextPage().then((_) => completed = true);
    await tester.pump();
    expect(completed, isFalse);
    // Further taps while waiting must not turn multiple pages unexpectedly.
    unawaited(controller.nextPage());
    for (var frame = 0; frame < 15; frame++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    await turn;
    expect(pages.controller!.page, prefixEnd + 1);
    expect(controller.snapshot.chapter?.id, 'chapter-1');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('disposing cancels a page turn waiting for pagination', (
    WidgetTester tester,
  ) async {
    final controller = TextReaderController();
    await _open(tester, controller, anchor: 60);
    final turn = controller.nextPage();
    await tester.pumpWidget(const SizedBox());
    await turn;
    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}

Future<void> _open(
  WidgetTester tester,
  TextReaderController controller, {
  int anchor = 0,
  _Source? source,
  ReaderPageAnimation animation = ReaderPageAnimation.slide,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TextReaderView(
        bookId: 'pending-$anchor',
        controller: controller,
        dataSource: source ?? _Source(),
        stateStore: _Store(anchor, animation),
        chapterPreloadCount: 0,
      ),
    ),
  );
  // Flush initial data futures and mount the preview/prefix without allowing
  // the eight-millisecond background timer to complete the chapter.
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump();
  }
  expect(find.byType(PageView), findsOneWidget);
}

String _visibleText(WidgetTester tester) {
  final Rect viewport = tester.getRect(find.byType(PageView));
  return find
      .descendant(of: find.byType(PageView), matching: find.byType(Text))
      .evaluate()
      .where((element) {
        final box = element.findRenderObject() as RenderBox;
        return (box.localToGlobal(Offset.zero) & box.size).overlaps(viewport);
      })
      .map((element) {
        final text = element.widget as Text;
        return text.data ?? text.textSpan!.toPlainText();
      })
      .join();
}

class _Source implements TextReaderDataSource {
  final List<String> loadedChapters = <String>[];
  static const chapters = <ReaderChapterInfo>[
    ReaderChapterInfo(id: 'chapter-1', title: '第一章', index: 0),
    ReaderChapterInfo(id: 'chapter-2', title: '第二章', index: 1),
  ];

  @override
  Future<ReaderBookInfo> loadBookInfo(String bookId) async =>
      ReaderBookInfo(id: bookId, title: '渐进分页');

  @override
  Future<ChapterCatalogPage> loadChapterCatalog(
    String bookId, {
    String? cursor,
    int pageSize = 100,
  }) async => ChapterCatalogPage(items: chapters, total: 2, hasMore: false);

  @override
  Future<ReaderChapterInfo> loadChapterAtIndex(
    String bookId,
    int index,
  ) async => chapters[index];

  @override
  Future<TextChapterContent> loadChapterContent(
    String bookId,
    String chapterId,
  ) async {
    loadedChapters.add(chapterId);
    return TextChapterContent(
      chapterId: chapterId,
      title: chapterId == 'chapter-1' ? '第一章' : '第二章',
      paragraphs: List<TextParagraph>.generate(
        80,
        (index) =>
            TextParagraph(id: 'p$index', text: '锚点段$index。${'连续阅读正文。' * 30}'),
      ),
    );
  }
}

class _Store implements TextReaderStateStore {
  _Store(this.anchor, this.animation);
  final int anchor;
  final ReaderPageAnimation animation;
  @override
  Future<TextReaderPreferences?> loadPreferences() async =>
      TextReaderPreferences(keepScreenOn: false, pageAnimation: animation);
  @override
  Future<ReaderProgress?> loadProgress(String bookId) async =>
      ReaderProgress(chapterId: 'chapter-1', paragraphId: 'p$anchor');
  @override
  Future<List<ReaderBookmark>> loadBookmarks(String bookId) async => [];
  @override
  Future<void> addBookmark(ReaderBookmark bookmark) async {}
  @override
  Future<void> removeBookmark(String bookId, String bookmarkId) async {}
  @override
  Future<void> savePreferences(TextReaderPreferences preferences) async {}
  @override
  Future<void> saveProgress(String bookId, ReaderProgress progress) async {}
}
