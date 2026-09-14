/// 书架目录自动检查的时间节流与全类型遍历测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_read/core/settings/settings.dart';
import 'package:mg_read/features/library/application/library_book_refresh_operation.dart';
import 'package:mg_read/features/library/application/library_book_refresher.dart';
import 'package:mg_read/features/library/application/library_catalog_refresh_coordinator.dart';

import '../../../core/diagnostics/diagnostics_testkit.dart';
import '../../../core/settings/settings_testkit.dart';

void main() {
  test('checks every content type once and skips openings inside the interval', () async {
    final settings = AppSettingsManager(store: FakeSettingsStore(), registry: AppSettingKeys.registry);
    await settings.initialize();
    addTearDown(settings.close);
    final diagnostics = DiagnosticsTestkit();
    addTearDown(diagnostics.dispose);
    final refresher = _RecordingRefresher(failingBookId: 'audio-book');
    var now = DateTime.utc(2026, 9, 14, 8);
    final coordinator = LibraryCatalogRefreshCoordinator(
      settings: settings,
      operation: LibraryBookRefreshOperation(refresher: refresher, diagnostics: diagnostics.manager),
      now: () => now,
    );
    var reloadCount = 0;

    await coordinator.maybeRefresh(
      bookIds: const <String>['novel-book', 'manga-book', 'audio-book', 'video-book', 'novel-book'],
      onCompleted: () async => reloadCount++,
    );
    await coordinator.maybeRefresh(
      bookIds: const <String>['novel-book', 'manga-book', 'audio-book', 'video-book'],
      onCompleted: () async => reloadCount++,
    );

    expect(refresher.bookIds, containsAllInOrder(<String>['novel-book', 'manga-book', 'audio-book', 'video-book']));
    expect(refresher.bookIds, hasLength(4));
    expect(reloadCount, 1);
    expect(settings.get(AppSettingKeys.bookshelfCatalogLastCheckedAtMs), now.millisecondsSinceEpoch);

    now = now.add(const Duration(hours: 24, minutes: 1));
    await coordinator.maybeRefresh(bookIds: const <String>['novel-book'], onCompleted: () async => reloadCount++);

    expect(refresher.bookIds, <String>['novel-book', 'manga-book', 'audio-book', 'video-book', 'novel-book']);
    expect(reloadCount, 2);
  });
}

final class _RecordingRefresher implements LibraryBookRefresher {
  _RecordingRefresher({required this.failingBookId});

  final String failingBookId;
  final List<String> bookIds = <String>[];

  @override
  Future<void> refresh(String bookId) async {
    bookIds.add(bookId);
    if (bookId == failingBookId) throw StateError('source unavailable');
  }
}
