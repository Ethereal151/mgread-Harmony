/// Source-backed manga shelf prewarming.
///
/// The app composition injects this reader-owned operation into discovery so
/// adding a shelf item can persist configured manifests and images without a
/// discovery-to-reader feature dependency. Chapters are processed in order;
/// the first persisted image is the reader readiness boundary.
library;

import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

import 'package:mg_read/core/content_library/content_library.dart';
import 'package:mg_read/features/discovery/application/source_content_gateway.dart';
import 'package:mg_read/features/reader/data/content_library_source_comic_reader.dart';

final class ContentLibrarySourceMangaPrewarmer {
  const ContentLibrarySourceMangaPrewarmer({required this.library, required this.gateway, this.imageFetcher, this.httpClientFactory});

  final ContentLibrary library;
  final SourceContentGateway gateway;
  final ComicImageFetcher? imageFetcher;
  final ComicHttpClientFactory? httpClientFactory;

  Future<int> warm({
    required LibraryItem item,
    required List<PluginChapterSummary> chapters,
    required int followingChapterCount,
    required void Function() onFirstImagePersisted,
  }) async {
    final source = ContentLibraryComicReaderDataSource(
      library: library,
      gateway: gateway,
      item: item,
      fetcher: imageFetcher,
      httpClientFactory: httpClientFactory,
    );
    var cached = 0;
    try {
      final int end = (1 + followingChapterCount).clamp(1, chapters.length);
      for (var index = 0; index < end; index++) {
        try {
          final chapter = await source.loadChapterAtIndex(item.id.value, index);
          final content = await source.loadChapterContent(item.id.value, chapter.id);
          if (content.images.isEmpty) continue;
          for (var imageIndex = 0; imageIndex < content.images.length; imageIndex++) {
            final image = content.images[imageIndex];
            await source.loadImageBytes(item.id.value, chapter.id, image.id);
            final persisted = await source.isImagePersistentlyCached(item.id.value, chapter.id, image.id);
            if (!persisted) {
              throw StateError('Manga image cache write did not persist.');
            }
            if (index == 0 && imageIndex == 0) onFirstImagePersisted();
          }
          cached++;
        } on Object {
          if (index == 0) rethrow;
          // Preserve earlier chapters and continue after an isolated later
          // chapter failure. Reader-visible retry remains independent.
        }
      }
      return cached;
    } finally {
      await source.dispose();
    }
  }
}
