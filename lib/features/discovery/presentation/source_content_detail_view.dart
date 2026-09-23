/// 数据源内容详情页的交互状态层。
///
/// 职责：
/// - 持有详情页书架操作、目录分页和异步刷新期间的局部交互状态。
/// - 将稳定的数据展示交给同一 library 的 `_SourceDetailBody`。
///
/// 注意：
/// - 本文件是 `source_content_detail_sheet.dart` 的 part，不单独声明 library。
/// - 不在 build() 中执行 Runtime、网络或磁盘 IO。
part of 'source_content_detail_sheet.dart';

class _SourceDetailView extends StatefulWidget {
  const _SourceDetailView({
    required this.bundle,
    required this.gateway,
    required this.relatedContents,
    required this.sourceVariants,
    required this.onSourceVariantRequested,
    required this.isRefreshing,
    required this.onTextChapterRequested,
    required this.onComicChapterRequested,
    required this.onAudioChapterRequested,
    required this.onVideoEpisodeRequested,
    required this.onAddToShelf,
    required this.onRemoveFromShelf,
    required this.shelfState,
    required this.onShelfAction,
    required this.onStartReading,
    required this.onRecommendationRequested,
    required this.onExternalUrlRequested,
    this.isCoverBlurred = false,
    super.key,
  });
  final _SourceDetailBundle bundle;
  final SourceContentGateway gateway;
  final Iterable<PluginContentSummary> relatedContents;
  final List<SourceSearchHit> sourceVariants;
  final SourceSearchVariantRequested? onSourceVariantRequested;
  final bool isRefreshing;
  final SourceTextChapterRequested? onTextChapterRequested;
  final SourceComicChapterRequested? onComicChapterRequested;
  final SourceAudioChapterRequested? onAudioChapterRequested;
  final SourceVideoEpisodeRequested? onVideoEpisodeRequested;
  final SourceShelfSaveRequested? onAddToShelf;
  final SourceShelfRemoveRequested? onRemoveFromShelf;
  final SourceDetailShelfState shelfState;
  final SourceShelfActionRequested? onShelfAction;
  final SourceStartReadingRequested? onStartReading;
  final SourceRecommendationRequested? onRecommendationRequested;
  final bool isCoverBlurred;
  final SourceExternalUrlLauncher onExternalUrlRequested;

  @override
  State<_SourceDetailView> createState() => _SourceDetailViewState();
}

class _SourceDetailViewState extends State<_SourceDetailView> {
  late final List<PluginChapterSummary> _chapters;
  late SourceDetailShelfState _shelfState;
  var _visibleChapterCount = 20;
  bool _isSavingToShelf = false;
  bool _isRemovingFromShelf = false;

  @override
  void initState() {
    super.initState();
    _chapters = List<PluginChapterSummary>.of(widget.bundle.chapters.items);
    _shelfState = widget.shelfState;
  }

  @override
  void didUpdateWidget(covariant _SourceDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSavingToShelf &&
        !_isRemovingFromShelf &&
        oldWidget.shelfState != widget.shelfState &&
        widget.shelfState != SourceDetailShelfState.canAdd) {
      _shelfState = widget.shelfState;
    }
  }

  Future<void> _saveToShelf(PluginContentDetail detail) async {
    final save = widget.onAddToShelf;
    if (save == null || _isSavingToShelf || _shelfState != SourceDetailShelfState.canAdd) {
      return;
    }
    setState(() => _isSavingToShelf = true);
    try {
      await save(detail, widget.bundle.chapters);
      if (!mounted) return;
      setState(() {
        _isSavingToShelf = false;
        _shelfState = SourceDetailShelfState.alreadyAdded;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入书架。')));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _isSavingToShelf = false);
      final message = error is BookshelfCapacityExceededException ? '书架已满，请先清理书籍。' : '暂时无法加入书架，请稍后重试。';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _removeFromShelf(PluginContentSummary content) async {
    final remove = widget.onRemoveFromShelf;
    if (remove == null || _isSavingToShelf || _isRemovingFromShelf || _shelfState == SourceDetailShelfState.canAdd) return;
    final confirmed = await showBookshelfRemovalConfirmation(context, title: content.title);
    if (!mounted || !confirmed) return;
    setState(() => _isRemovingFromShelf = true);
    try {
      await remove();
      if (!mounted) return;
      setState(() {
        _isRemovingFromShelf = false;
        _shelfState = SourceDetailShelfState.canAdd;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已从书架移出《${content.title}》')));
    } on Object {
      if (!mounted) return;
      setState(() => _isRemovingFromShelf = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('移出书架失败，请稍后重试。')));
    }
  }

  void _loadMore() {
    setState(() {
      _visibleChapterCount = math.min(_visibleChapterCount + 20, _chapters.length);
    });
  }

  @override
  Widget build(BuildContext context) => _SourceDetailBody(
    bundle: _SourceDetailBundle(
      detail: widget.bundle.detail,
      chapters: PluginChaptersResult(
        pluginId: widget.bundle.chapters.pluginId,
        sourceName: widget.bundle.chapters.sourceName,
        items: _chapters,
        groups: widget.bundle.chapters.groups,
      ),
    ),
    gateway: widget.gateway,
    relatedContents: widget.relatedContents,
    sourceVariants: widget.sourceVariants,
    onSourceVariantRequested: widget.onSourceVariantRequested,
    isRefreshing: widget.isRefreshing,
    onTextChapterRequested: widget.onTextChapterRequested,
    onComicChapterRequested: widget.onComicChapterRequested,
    onAudioChapterRequested: widget.onAudioChapterRequested,
    onVideoEpisodeRequested: widget.onVideoEpisodeRequested,
    onAddToShelf: widget.onAddToShelf,
    onRemoveFromShelf: widget.onRemoveFromShelf,
    shelfState: _shelfState,
    onShelfAction: widget.onShelfAction,
    onStartReading: widget.onStartReading,
    isCoverBlurred: widget.isCoverBlurred,
    onRecommendationRequested: widget.onRecommendationRequested,
    isSavingToShelf: _isSavingToShelf,
    isRemovingFromShelf: _isRemovingFromShelf,
    onSaveToShelf: _saveToShelf,
    onRemoveFromShelfRequested: _removeFromShelf,
    onExternalUrlRequested: widget.onExternalUrlRequested,
    visibleChapterCount: _visibleChapterCount,
    onLoadMore: _visibleChapterCount < _chapters.length ? _loadMore : null,
  );
}
