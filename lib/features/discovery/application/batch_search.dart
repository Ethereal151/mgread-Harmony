/// Cross-source search projection owned by the Flutter application.
///
/// Source plugins continue to return their normal single-source search result.
/// This file only preserves source identity while merging those results for
/// the search page.
library;

import 'dart:async';

import 'package:mgread_plugin_runtime/mgread_plugin_runtime.dart';

import 'package:mg_read/core/errors/app_error.dart';
import 'package:mg_read/features/discovery/application/source_content_gateway.dart';

const int batchSearchPageSize = 20;
const int batchSearchMaximumConcurrency = 6;

enum BatchSearchSourceStatus { pending, loading, success, failure }

final class SourceSearchHit {
  const SourceSearchHit({required this.source, required this.content, required this.sourceIndex, required this.sourceRank});

  final PluginSourceDescriptor source;
  final PluginContentSummary content;
  final int sourceIndex;
  final int sourceRank;

  String get pluginId => source.id;
}

final class BatchSearchSourceState {
  const BatchSearchSourceState({
    required this.source,
    required this.status,
    required this.hits,
    required this.nextCursor,
    required this.totalCount,
    this.error,
  });

  factory BatchSearchSourceState.pending(PluginSourceDescriptor source) => BatchSearchSourceState(
    source: source,
    status: BatchSearchSourceStatus.pending,
    hits: const <SourceSearchHit>[],
    nextCursor: null,
    totalCount: null,
  );

  final PluginSourceDescriptor source;
  final BatchSearchSourceStatus status;
  final List<SourceSearchHit> hits;
  final String? nextCursor;
  final int? totalCount;
  final AppError? error;

  BatchSearchSourceState copyWith({
    BatchSearchSourceStatus? status,
    Iterable<SourceSearchHit>? hits,
    Object? nextCursor = _unset,
    Object? totalCount = _unset,
    Object? error = _unset,
  }) => BatchSearchSourceState(
    source: source,
    status: status ?? this.status,
    hits: hits == null ? this.hits : List<SourceSearchHit>.unmodifiable(hits),
    nextCursor: identical(nextCursor, _unset) ? this.nextCursor : nextCursor as String?,
    totalCount: identical(totalCount, _unset) ? this.totalCount : totalCount as int?,
    error: identical(error, _unset) ? this.error : error as AppError?,
  );
}

const Object _unset = Object();

final class AggregatedSearchItem {
  const AggregatedSearchItem({required this.key, required this.primary, required this.variants, required this.score});

  final String key;
  final SourceSearchHit primary;
  final List<SourceSearchHit> variants;
  final int score;

  PluginContentSummary get content => primary.content;

  int get sourceCount => variants.length;
}

final class AggregatedSearchResult {
  const AggregatedSearchResult({required this.query, required this.items, required this.sourceStates});

  final String query;
  final List<AggregatedSearchItem> items;
  final List<BatchSearchSourceState> sourceStates;

  int get totalSourceCount => sourceStates.length;

  int get completedSourceCount => sourceStates
      .where((state) => state.status == BatchSearchSourceStatus.success || state.status == BatchSearchSourceStatus.failure)
      .length;

  List<BatchSearchSourceState> get failedSources =>
      sourceStates.where((state) => state.status == BatchSearchSourceStatus.failure).toList(growable: false);

  List<BatchSearchSourceState> get loadingSources => sourceStates
      .where((state) => state.status == BatchSearchSourceStatus.loading || state.status == BatchSearchSourceStatus.pending)
      .toList(growable: false);

  bool get isComplete => loadingSources.isEmpty;

  bool get allFailed => sourceStates.isNotEmpty && failedSources.length == sourceStates.length;

  bool get hasMore => sourceStates.any((state) => state.nextCursor != null);

  BatchSearchSourceState? sourceState(String pluginId) {
    for (final state in sourceStates) {
      if (state.source.id == pluginId) return state;
    }
    return null;
  }
}

final class _SearchGroup {
  _SearchGroup(this.titleKey, SourceSearchHit firstHit) : hits = <SourceSearchHit>[firstHit];

  final String titleKey;
  final List<SourceSearchHit> hits;
}

final class BatchSearchCoordinator {
  const BatchSearchCoordinator(this._gateway);

  final SourceContentGateway _gateway;

  Future<AggregatedSearchResult> run({
    required String query,
    required List<PluginSourceDescriptor> sources,
    required PluginInvocationCancellation cancellation,
    AggregatedSearchResult? previous,
    Set<String>? sourceIds,
    int pageSize = batchSearchPageSize,
    void Function(AggregatedSearchResult result)? onUpdate,
  }) async {
    final previousById = <String, BatchSearchSourceState>{
      for (final state in previous?.sourceStates ?? const <BatchSearchSourceState>[]) state.source.id: state,
    };
    final states = <String, BatchSearchSourceState>{
      for (var index = 0; index < sources.length; index += 1)
        sources[index].id: previousById[sources[index].id] ?? BatchSearchSourceState.pending(sources[index]),
    };
    final targetIds =
        sourceIds ??
        (previous == null
            ? sources.map((source) => source.id).toSet()
            : states.values.where((state) => state.nextCursor != null).map((state) => state.source.id).toSet());

    for (final sourceId in targetIds) {
      final state = states[sourceId];
      if (state == null) continue;
      states[sourceId] = state.copyWith(status: BatchSearchSourceStatus.loading, error: null);
    }
    _publish(query, sources, states, onUpdate);

    var nextIndex = 0;
    Future<void> worker() async {
      while (true) {
        cancellation.throwIfCancelled();
        final index = nextIndex++;
        if (index >= sources.length) return;
        final source = sources[index];
        if (!targetIds.contains(source.id)) continue;
        final current = states[source.id];
        if (current == null) continue;
        try {
          final result = await runCancellableSourceRequest(
            _gateway,
            cancellation,
            () => _gateway.search(pluginId: source.id, query: query, cursor: current.nextCursor, pageSize: pageSize),
          );
          final offset = current.hits.length;
          final hits = <SourceSearchHit>[
            ...current.hits,
            for (var itemIndex = 0; itemIndex < result.items.length; itemIndex += 1)
              SourceSearchHit(source: source, content: result.items[itemIndex], sourceIndex: index, sourceRank: offset + itemIndex),
          ];
          states[source.id] = current.copyWith(
            status: BatchSearchSourceStatus.success,
            hits: hits,
            nextCursor: result.nextCursor,
            totalCount: result.totalCount,
            error: null,
          );
        } on Object catch (error) {
          if (cancellation.isCancelled) rethrow;
          states[source.id] = current.copyWith(status: BatchSearchSourceStatus.failure, error: AppError.fromUnknown(error));
        }
        _publish(query, sources, states, onUpdate);
      }
    }

    final workerCount = targetIds.isEmpty ? 0 : targetIds.length.clamp(1, batchSearchMaximumConcurrency);
    await Future.wait<void>(List<Future<void>>.generate(workerCount, (_) => worker()));
    final result = _build(query, sources, states);
    onUpdate?.call(result);
    return result;
  }

  void _publish(
    String query,
    List<PluginSourceDescriptor> sources,
    Map<String, BatchSearchSourceState> states,
    void Function(AggregatedSearchResult result)? onUpdate,
  ) {
    onUpdate?.call(_build(query, sources, states));
  }

  AggregatedSearchResult _build(String query, List<PluginSourceDescriptor> sources, Map<String, BatchSearchSourceState> states) {
    final sourceStates = <BatchSearchSourceState>[
      for (final source in sources) states[source.id] ?? BatchSearchSourceState.pending(source),
    ];
    final groups = <_SearchGroup>[];
    for (final state in sourceStates) {
      for (final hit in state.hits) {
        final titleKey = _normalize(hit.content.title);
        if (titleKey.isEmpty) continue;
        _SearchGroup? matching;
        for (final candidate in groups) {
          if (candidate.titleKey == titleKey &&
              candidate.hits.every((existing) => _authorsCompatible(existing.content.author, hit.content.author))) {
            matching = candidate;
            break;
          }
        }
        if (matching == null) {
          groups.add(_SearchGroup(titleKey, hit));
        } else {
          matching.hits.add(hit);
        }
      }
    }

    final items = <AggregatedSearchItem>[];
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
      final group = groups[groupIndex];
      if (group.hits.isEmpty) continue;
      final variants = List<SourceSearchHit>.of(group.hits)..sort((left, right) => _compareHits(query, left, right));
      final primary = variants.first;
      items.add(
        AggregatedSearchItem(
          key: '${group.titleKey}#$groupIndex',
          primary: primary,
          variants: List<SourceSearchHit>.unmodifiable(variants),
          score: _score(query, primary),
        ),
      );
    }
    items.sort((left, right) {
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      final source = left.primary.sourceIndex.compareTo(right.primary.sourceIndex);
      if (source != 0) return source;
      final plugin = left.primary.pluginId.compareTo(right.primary.pluginId);
      return plugin != 0 ? plugin : left.primary.content.id.compareTo(right.primary.content.id);
    });
    return AggregatedSearchResult(
      query: query,
      items: List<AggregatedSearchItem>.unmodifiable(items),
      sourceStates: List<BatchSearchSourceState>.unmodifiable(sourceStates),
    );
  }
}

int _compareHits(String query, SourceSearchHit left, SourceSearchHit right) {
  final score = _score(query, right).compareTo(_score(query, left));
  if (score != 0) return score;
  final source = left.sourceIndex.compareTo(right.sourceIndex);
  if (source != 0) return source;
  final rank = left.sourceRank.compareTo(right.sourceRank);
  if (rank != 0) return rank;
  final plugin = left.pluginId.compareTo(right.pluginId);
  return plugin != 0 ? plugin : left.content.id.compareTo(right.content.id);
}

int _score(String query, SourceSearchHit hit) {
  final normalizedQuery = _normalize(query);
  final title = _normalize(hit.content.title);
  var score = switch (normalizedQuery) {
    final value when value.isEmpty => 0,
    final value when title == value => 1000,
    final value when title.startsWith(value) => 800,
    final value when title.contains(value) => 600,
    _ => 400,
  };
  final author = _normalize(hit.content.author ?? '');
  if (author.isNotEmpty && normalizedQuery.isNotEmpty && author.contains(normalizedQuery)) score += 120;
  score += (80 - hit.sourceRank).clamp(0, 80);
  if (hit.content.coverUrl != null) score += 10;
  if (hit.content.author != null && hit.content.author!.trim().isNotEmpty) score += 5;
  if (hit.content.chapterCount != null || hit.content.latestChapter != null) score += 5;
  if (hit.content.description != null && hit.content.description!.trim().isNotEmpty) score += 3;
  return score;
}

bool _authorsCompatible(String? left, String? right) {
  final leftKey = _normalize(left ?? '');
  final rightKey = _normalize(right ?? '');
  return leftKey.isEmpty || rightKey.isEmpty || leftKey == rightKey;
}

String _normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

extension on PluginInvocationCancellation {
  void throwIfCancelled() {
    if (isCancelled) throw const PluginRuntimeException('cancelled', 'The source request was cancelled.');
  }
}
