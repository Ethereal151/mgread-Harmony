import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/features/library/presentation/library_book_list_view_data.dart';
import 'package:mg_read/features/library/presentation/library_home_view_data.dart';
import 'package:mg_read/features/library/presentation/widgets/library_book_cover.dart';
import 'package:mg_read/features/library/presentation/widgets/library_book_grid.dart';
import 'package:mg_read/features/library/presentation/widgets/library_book_list.dart';
import 'package:mg_read/features/library/presentation/widgets/library_book_removal_transition.dart';
import 'package:mg_read/features/library/presentation/widgets/library_book_swipe_actions.dart';
import 'package:mg_read/features/library/presentation/widgets/library_continue_reading_card.dart';
import 'package:mg_read/features/library/presentation/widgets/library_home_controls.dart';
import 'package:mg_read/features/library/presentation/widgets/library_home_shell.dart';
import 'package:mg_read/features/library/presentation/widgets/library_home_top_bar.dart';
import 'package:mg_read/shared/presentation/app_navigation_destination.dart';
import 'package:mg_read/shared/presentation/widgets/async_book_cover_loader.dart';
import 'package:mg_read/shared/presentation/widgets/app_bottom_navigation.dart';

part 'library_home_shell_test_helpers.dart';

part 'library_home_shell_test_part_one.dart';
part 'library_home_shell_test_part_two.dart';

void main() {
  registerLibraryHomeShellTestsPartOne();
  registerLibraryHomeShellTestsPartTwo();
}

Widget _host({
  ThemeMode themeMode = ThemeMode.light,
  LibraryHomeCallbacks callbacks = const LibraryHomeCallbacks(),
  VoidCallback? onToggleTheme,
  LibraryHomeViewData? data,
  String? preparingBookId,
  bool disableAnimations = false,
  double topInset = 0,
  TextScaler textScaler = TextScaler.noScaling,
  LibraryHomeLayoutMode initialLayoutMode = LibraryHomeLayoutMode.list,
  Future<void> Function(LibraryHomeLayoutMode mode)? onLayoutModeChanged,
  LibraryHomeCoverMetadataMode initialCoverMetadataMode = LibraryHomeCoverMetadataMode.belowCover,
  ValueNotifier<LibraryHomeCoverMetadataMode>? coverMetadataModeListenable,
  Future<void> Function()? onRefresh,
}) {
  Widget buildShell(LibraryHomeCoverMetadataMode coverMetadataMode) => MediaQuery(
    data: MediaQueryData(
      disableAnimations: disableAnimations,
      textScaler: textScaler,
      padding: EdgeInsets.only(top: topInset),
      viewPadding: EdgeInsets.only(top: topInset),
    ),
    child: LibraryHomeShell(
      data: data ?? LibraryHomeFixtures.preview,
      initialLayoutMode: initialLayoutMode,
      onLayoutModeChanged: onLayoutModeChanged,
      initialCoverMetadataMode: coverMetadataMode,
      callbacks: callbacks,
      isRefreshing: false,
      onRefresh: onRefresh ?? () async {},
      onToggleTheme: onToggleTheme,
      preparingBookId: preparingBookId,
    ),
  );

  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: themeMode,
    home: coverMetadataModeListenable == null
        ? buildShell(initialCoverMetadataMode)
        : ValueListenableBuilder<LibraryHomeCoverMetadataMode>(
            valueListenable: coverMetadataModeListenable,
            builder: (BuildContext context, LibraryHomeCoverMetadataMode coverMetadataMode, Widget? child) => buildShell(coverMetadataMode),
          ),
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pump();
}

Future<void> _openHomeBookMenu(WidgetTester tester) async {
  final Finder book = find.byWidgetPredicate(
    (Widget widget) => widget is LibraryBookListItem && widget.data.id == 'fixture-lord-of-mysteries',
  );
  final Finder content = find.byKey(const Key('library-home-content'));
  for (int attempt = 0; attempt < 8 && book.evaluate().isEmpty; attempt++) {
    await tester.drag(content, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  expect(book, findsOneWidget);
  await tester.ensureVisible(book);
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: book, matching: find.byTooltip('书籍更多操作')));
  await tester.pumpAndSettle();
}

LibraryHomeViewData _asyncCoverLibraryHomeData() {
  final requests = List<BookCoverRequest>.generate(
    3,
    (int index) => BookCoverRequest(
      pluginId: 'cover-source',
      pluginVersion: '1.0.0',
      remoteContentId: 'book-$index',
      coverUrl: Uri.parse('https://example.com/book-$index.png'),
    ),
  );
  return LibraryHomeViewData(
    isPresentationFixture: false,
    continueReading: LibraryContinueReadingViewData(
      bookId: 'book-0',
      title: '继续阅读测试',
      chapter: '第1章',
      progress: 0.5,
      lastReadLabel: '刚刚',
      coverVariant: LibraryCoverVariant.dusk,
      coverRequest: requests[0],
    ),
    books: <LibraryBookListItemViewData>[
      LibraryBookListItemViewData(
        id: 'book-1',
        title: '连载测试',
        coverVariant: LibraryCoverVariant.dawn,
        status: LibraryBookStatus.ongoing,
        coverRequest: requests[1],
      ),
      LibraryBookListItemViewData(
        id: 'book-2',
        title: '完结测试',
        coverVariant: LibraryCoverVariant.ocean,
        status: LibraryBookStatus.completed,
        coverRequest: requests[2],
      ),
    ],
  );
}

final class _CountingBookCoverBytesLoader implements BookCoverBytesLoader {
  final Map<BookCoverRequest, int> loadCounts = <BookCoverRequest, int>{};

  @override
  Future<List<int>?> resolve(BookCoverRequest request) async {
    loadCounts.update(request, (int count) => count + 1, ifAbsent: () => 1);
    return base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
  }
}
