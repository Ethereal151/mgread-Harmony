import 'package:flutter_test/flutter_test.dart';
import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

import 'package:mg_read/features/discovery/application/batch_search.dart';
import 'package:mg_read/features/discovery/application/source_content_gateway.dart';

void main() {
  test('merges compatible title and author hits and keeps the first source cover', () async {
    final sourceA = _source('source.a', '来源 A');
    final sourceB = _source('source.b', '来源 B');
    final gateway = _Gateway(
      sources: <PluginSourceDescriptor>[sourceA, sourceB],
      results: <String, Object>{
        'source.a': _result('source.a', [_summary(id: 'a-1', title: '星河之上', author: '作者', cover: 'https://a/cover')]),
        'source.b': _result('source.b', [_summary(id: 'b-1', title: '星河之上', author: '作者', cover: 'https://b/cover')]),
      },
    );
    final configured = await BatchSearchCoordinator(
      gateway,
    ).run(query: '星河之上', sources: <PluginSourceDescriptor>[sourceA, sourceB], cancellation: PluginInvocationCancellation());

    expect(configured.items, hasLength(1));
    expect(configured.items.single.sourceCount, 2);
    expect(configured.items.single.primary.pluginId, 'source.a');
    expect(configured.items.single.primary.content.coverUrl, Uri.parse('https://a/cover'));
  });

  test('does not merge same-title hits with conflicting authors', () async {
    final sources = <PluginSourceDescriptor>[_source('source.a', '来源 A'), _source('source.b', '来源 B')];
    final result = await BatchSearchCoordinator(
      _Gateway(
        sources: sources,
        results: <String, Object>{
          'source.a': _result('source.a', [_summary(id: 'a-1', title: '同名作品', author: '甲')]),
          'source.b': _result('source.b', [_summary(id: 'b-1', title: '同名作品', author: '乙')]),
        },
      ),
    ).run(query: '同名作品', sources: sources, cancellation: PluginInvocationCancellation());

    expect(result.items, hasLength(2));
  });

  test('publishes partial failures and loads source cursors independently', () async {
    final sources = <PluginSourceDescriptor>[_source('source.a', '来源 A'), _source('source.b', '来源 B')];
    final gateway = _Gateway(
      sources: sources,
      results: <String, Object>{
        'source.a': _result('source.a', [_summary(id: 'a-1', title: '第一条')], nextCursor: 'page-2'),
        'source.b': StateError('source unavailable'),
      },
      continuationResults: <String, PluginSearchResult>{
        'source.a': _result('source.a', [_summary(id: 'a-2', title: '第二条')]),
      },
    );
    final first = await BatchSearchCoordinator(gateway).run(query: '作品', sources: sources, cancellation: PluginInvocationCancellation());

    expect(first.items, hasLength(1));
    expect(first.failedSources.map((state) => state.source.id), contains('source.b'));
    expect(first.hasMore, isTrue);

    final next = await BatchSearchCoordinator(
      gateway,
    ).run(query: '作品', sources: sources, previous: first, cancellation: PluginInvocationCancellation());
    expect(next.items.map((item) => item.content.title), containsAll(<String>['第一条', '第二条']));
  });
}

final class _Gateway implements SourceContentGateway {
  const _Gateway({required this.sources, required this.results, this.continuationResults = const <String, PluginSearchResult>{}});
  final List<PluginSourceDescriptor> sources;
  final Map<String, Object> results;
  final Map<String, PluginSearchResult> continuationResults;

  @override
  Future<List<PluginSourceDescriptor>> listSources() async => sources;

  @override
  Future<PluginSearchResult> search({required String pluginId, required String query, String? cursor, int pageSize = 20}) async {
    if (cursor != null) return continuationResults[pluginId]!;
    final value = results[pluginId];
    if (value is StateError) throw value;
    return value! as PluginSearchResult;
  }

  @override
  Future<PluginSearchSuggestionsResult> searchSuggestions({required String pluginId, String? cursor, int pageSize = 20}) =>
      throw UnimplementedError();

  @override
  Future<PluginDiscoverResult> discover({
    required String pluginId,
    String? target,
    String? cursor,
    String? collectionId,
    int pageSize = 20,
  }) => throw UnimplementedError();

  @override
  Future<PluginContentDetail> getDetail({required String pluginId, required String id}) => throw UnimplementedError();

  @override
  Future<PluginChaptersResult> getChapters({required String pluginId, required String id}) => throw UnimplementedError();

  @override
  Future<PluginChapterContent> getContent({required String pluginId, required String id, required String chapterId}) =>
      throw UnimplementedError();
}

PluginSourceDescriptor _source(String id, String name) => PluginSourceDescriptor(
  id: id,
  displayName: name,
  pluginVersion: '1.0.0',
  contentKinds: const <PluginContentKind>[PluginContentKind.novel],
);

PluginSearchResult _result(String pluginId, List<PluginContentSummary> items, {String? nextCursor}) =>
    PluginSearchResult(pluginId: pluginId, sourceName: pluginId, items: items, nextCursor: nextCursor, totalCount: items.length);

PluginContentSummary _summary({required String id, required String title, String? author, String? cover}) => PluginContentSummary(
  id: id,
  title: title,
  contentKind: PluginContentKind.novel,
  author: author,
  url: null,
  coverUrl: cover == null ? null : Uri.parse(cover),
  description: null,
  language: null,
  status: PluginContentStatus.unknown,
  access: PluginAccessKind.unknown,
  wordCount: null,
  chapterCount: null,
  publishedAt: null,
  updatedAt: null,
  latestChapter: null,
  categories: const <String>[],
  tags: const <String>[],
  attributes: const <PluginContentAttribute>[],
);
