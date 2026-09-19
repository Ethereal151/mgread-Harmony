/// Session-owned ordered preloading. Four asynchronous workers share the image
/// cache's global concurrency limit with visible work. The current chapter is
/// completed first, then the configured following chapters are resolved and
/// cached one by one; cancellation stops replenishment and queued work.
library;

import 'dart:async';

import '../../api/comic_contracts.dart';
import '../../api/comic_models.dart';
import 'comic_image_cache.dart';

class ComicChapterPreloader {
  ComicChapterPreloader(this.cache, {this.onProgress});

  final ComicImageByteCache cache;
  final void Function(
    ComicChapterContent chapter,
    int cachedImageCount,
    int failedImageCount,
  )?
  onProgress;
  ComicChapterContent? _current;
  int _followingChapterCount = 0;
  int _generation = 0;

  void start(
    ComicChapterContent chapter, {
    required int followingChapterCount,
    required Future<ComicChapterContent?> Function(int offset) followingChapter,
  }) {
    assert(followingChapterCount >= 0);
    if (identical(_current, chapter) &&
        _followingChapterCount == followingChapterCount) {
      return;
    }
    cancel();
    _current = chapter;
    _followingChapterCount = followingChapterCount;
    final int generation = _generation;
    unawaited(
      _run(chapter, followingChapterCount, followingChapter, generation),
    );
  }

  Future<void> _run(
    ComicChapterContent chapter,
    int followingChapterCount,
    Future<ComicChapterContent?> Function(int offset) followingChapter,
    int generation,
  ) async {
    await _loadChapter(chapter, generation);
    if (generation != _generation) return;
    for (var offset = 1; offset <= followingChapterCount; offset++) {
      if (generation != _generation) return;
      try {
        final next = await followingChapter(offset);
        if (next == null || generation != _generation) return;
        await _loadChapter(next, generation);
      } on Object {
        // One following chapter failing does not prevent later configured
        // chapters from being cached. Visible boundary retry remains separate.
      }
    }
  }

  Future<void> _loadChapter(ComicChapterContent chapter, int generation) async {
    var cursor = 0;
    var cachedImageCount = 0;
    var failedImageCount = 0;
    if (generation == _generation) {
      onProgress?.call(chapter, cachedImageCount, failedImageCount);
    }
    Future<void> worker() async {
      while (generation == _generation && cursor < chapter.images.length) {
        final image = chapter.images[cursor++];
        try {
          await cache.load(chapter.chapterId, image, visiblePriority: false);
          final source = cache.dataSource;
          var persisted = true;
          if (source is ComicReaderImageCacheStateDataSource) {
            persisted = await (source as ComicReaderImageCacheStateDataSource)
                .isImagePersistentlyCached(
                  cache.bookId,
                  chapter.chapterId,
                  image.id,
                );
          }
          if (persisted) {
            cachedImageCount++;
          } else {
            failedImageCount++;
          }
        } on Object {
          failedImageCount++;
          // A failed page never prevents later pages from loading. Transport
          // retries belong to the host; the visible tile retains manual retry.
        }
        if (generation == _generation) {
          onProgress?.call(chapter, cachedImageCount, failedImageCount);
        }
      }
    }

    await Future.wait<void>([
      for (
        var workerIndex = 0;
        workerIndex < cache.maxConcurrentLoads;
        workerIndex++
      )
        worker(),
    ]);
    if (generation != _generation) return;
    final source = cache.dataSource;
    if (source is ComicReaderImageCacheStateDataSource) {
      cachedImageCount = 0;
      failedImageCount = 0;
      for (final image in chapter.images) {
        try {
          final persisted =
              await (source as ComicReaderImageCacheStateDataSource)
                  .isImagePersistentlyCached(
                    cache.bookId,
                    chapter.chapterId,
                    image.id,
                  );
          persisted ? cachedImageCount++ : failedImageCount++;
        } on Object {
          failedImageCount++;
        }
      }
      if (generation == _generation) {
        onProgress?.call(chapter, cachedImageCount, failedImageCount);
      }
    }
  }

  void cancel() {
    _generation++;
    _current = null;
    _followingChapterCount = 0;
    cache.cancelPrefetch();
  }
}
