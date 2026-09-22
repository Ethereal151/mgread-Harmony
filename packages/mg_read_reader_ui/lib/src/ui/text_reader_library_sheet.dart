part of 'text_reader_view.dart';

// ignore_for_file: invalid_use_of_protected_member

const double _catalogChapterItemExtent = 54;
const double _catalogListTopPadding = 8;
const double _catalogScrollbarThickness = 18;
const double _catalogScrollbarMinThumbLength = 52;
const double _catalogListHorizontalPadding = 8;
const double _catalogScrollbarSafetyPadding = 20;
const double _catalogTileHorizontalPadding = 6;

extension _TextReaderLibrarySheet on _TextReaderViewState {
  void _showLibrarySheet({int initialIndex = 1}) {
    _stopAutoReading();
    final int routeSession = _sessionGeneration;
    final String routeBookId = widget.bookId;
    final TextReaderStateStore routeStore = widget.stateStore;
    // Keep the last catalog location when the sheet is reopened or when the
    // user switches between its tabs. A new reader session resets this in
    // _restart, while a chapter change still recenters on the new chapter.
    _catalogCenterRetryCount = 0;
    bool sheetRefreshStarted = false;
    final ThemeData readerTheme = readerThemeData(
      _palette,
      font: _preferences.font,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: ReaderSettingsTokens.sheetBarrier(_palette),
      builder: (BuildContext sheetContext) {
        return Theme(
          data: readerTheme,
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              if (!sheetRefreshStarted) {
                sheetRefreshStarted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!_isRouteSessionCurrent(
                    routeSession,
                    routeBookId,
                    store: routeStore,
                  )) {
                    return;
                  }
                  await _refreshCommentSummaries();
                  if (sheetContext.mounted &&
                      _isRouteSessionCurrent(
                        routeSession,
                        routeBookId,
                        store: routeStore,
                      )) {
                    setSheetState(() {});
                  }
                });
              }
              final MediaQueryData mediaQuery = MediaQuery.of(context);
              final double sheetHeight = (mediaQuery.size.height * 0.74)
                  .clamp(0, 640)
                  .toDouble();
              return MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: mediaQuery.textScaler.clamp(maxScaleFactor: 1.3),
                ),
                // Limit the route child to the visible panel so the uncovered
                // reader area remains the tappable modal barrier.
                child: SizedBox(
                  width: double.infinity,
                  height: sheetHeight,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: SizedBox(
                        height: sheetHeight,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20),
                          ),
                          child: Material(
                            color: _palette.panel,
                            child: SafeArea(
                              top: false,
                              child: DefaultTabController(
                                length: 3,
                                initialIndex: initialIndex,
                                child: Column(
                                  children: <Widget>[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: 34,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: _palette.divider,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const TabBar(
                                      dividerHeight: 1,
                                      labelStyle: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      tabs: <Widget>[
                                        Tab(text: ReaderStrings.bookDetails),
                                        Tab(text: ReaderStrings.catalog),
                                        Tab(text: ReaderStrings.bookmarks),
                                      ],
                                    ),
                                    Expanded(
                                      child: PageStorage(
                                        bucket: _catalogPageStorageBucket,
                                        child: TabBarView(
                                          children: <Widget>[
                                            _buildBookDetailTab(
                                              routeSession,
                                              routeBookId,
                                            ),
                                            _buildCatalogList(
                                              sheetContext,
                                              routeSession,
                                              routeBookId,
                                              routeStore,
                                            ),
                                            _buildBookmarkList(
                                              sheetContext,
                                              routeSession,
                                              routeBookId,
                                              routeStore,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBookDetailTab(int routeSession, String routeBookId) {
    final ReaderBookInfo? book = _book;
    final List<String> labels = book == null
        ? const <String>[]
        : book.labels
              .map((String label) => label.trim())
              .where((String label) => label.isNotEmpty)
              .toSet()
              .take(8)
              .toList(growable: false);
    final int chapterCount = book?.chapterCount ?? _catalogTotal;
    final String? description = book?.description?.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildDetailHero(book, labels, routeSession, routeBookId),
                const SizedBox(height: 14),
                _buildDetailStats(book, chapterCount),
                if (description?.isNotEmpty == true) ...<Widget>[
                  const SizedBox(height: 14),
                  _buildDetailSection(
                    icon: Icons.notes_rounded,
                    title: '作品简介',
                    child: Text(
                      description!,
                      style: TextStyle(
                        color: _palette.secondaryText,
                        fontSize: 14,
                        height: 1.7,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _buildDetailExternalRow(
                  icon: Icons.language_rounded,
                  title: '内容来源',
                  label: book?.sourceName ?? ReaderStrings.sourceUnavailable,
                  url: _sourceDisplayUri,
                ),
                if (book?.latestChapterTitle?.isNotEmpty == true) ...<Widget>[
                  const SizedBox(height: 10),
                  _buildDetailExternalRow(
                    icon: Icons.auto_stories_outlined,
                    title: '最新章节',
                    label: book!.latestChapterTitle!,
                    url: book.latestChapterUrl,
                  ),
                ],
                if (widget.extensions.commentFeed != null &&
                    _preferences.showBookComments) ...<Widget>[
                  const SizedBox(height: 16),
                  _buildBookCommentSummary(
                    target: ReaderCommentTarget.book(routeBookId),
                    onPressed: () {
                      if (!_isRouteSessionCurrent(routeSession, routeBookId)) {
                        return;
                      }
                      _showComments(
                        ReaderCommentTarget.book(routeBookId),
                        title: ReaderCommentStrings.bookTitle,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailHero(
    ReaderBookInfo? book,
    List<String> labels,
    int routeSession,
    String routeBookId,
  ) => Container(
    key: const ValueKey<String>('reader-book-detail-hero'),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _palette.accent.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _palette.accent.withValues(alpha: .18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _palette.accent.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.local_library_outlined,
                size: 17,
                color: _palette.accent,
              ),
            ),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                '作品信息',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            _buildDetailRefreshButton(routeSession, routeBookId),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget metadata = _buildDetailMetadata(book, labels);
            if (constraints.maxWidth < 280) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(child: _buildDetailCover(book)),
                  const SizedBox(height: 16),
                  metadata,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildDetailCover(book),
                const SizedBox(width: 16),
                Expanded(child: metadata),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _buildDetailMetadata(ReaderBookInfo? book, List<String> labels) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            book?.title ?? ReaderStrings.bookPreview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: _palette.secondaryText,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  book?.author?.trim().isNotEmpty == true
                      ? book!.author!.trim()
                      : '作者未知',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _palette.secondaryText, fontSize: 14),
                ),
              ),
            ],
          ),
          if (labels.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: labels.map(_buildDetailTag).toList(growable: false),
            ),
          ],
        ],
      );

  Widget _buildDetailCover(ReaderBookInfo? book) => Semantics(
    image: true,
    label: '${book?.title ?? ReaderStrings.bookPreview}的封面',
    child: Container(
      key: const ValueKey<String>('reader-book-detail-cover'),
      width: 104,
      height: 156,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _bookCoverImage == null
            ? _buildDetailCoverFallback(book)
            : Image(
                key: const ValueKey<String>('reader-book-detail-cover-image'),
                image: _bookCoverImage!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                errorBuilder:
                    (BuildContext context, Object error, StackTrace? stack) =>
                        _buildDetailCoverFallback(book),
              ),
      ),
    ),
  );

  Widget _buildDetailCoverFallback(ReaderBookInfo? book) => Container(
    key: const ValueKey<String>('reader-book-detail-cover-placeholder'),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          _palette.accent.withValues(alpha: .94),
          Color.lerp(_palette.accent, _palette.text, .58)!,
        ],
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.menu_book_rounded, size: 30, color: Colors.white),
        const SizedBox(height: 8),
        Text(
          book?.title ?? ReaderStrings.bookPreview,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ],
    ),
  );

  Widget _buildDetailTag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _palette.panel.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _palette.accent.withValues(alpha: .18)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: _palette.accent,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _buildDetailStats(ReaderBookInfo? book, int chapterCount) {
    final String wordCount = _formatDetailWordCount(book?.wordCount);
    return Container(
      key: const ValueKey<String>('reader-book-detail-stats'),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _palette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _palette.divider),
      ),
      child: Row(
        children: <Widget>[
          _buildDetailStat(wordCount, '字数'),
          SizedBox(
            height: 30,
            child: VerticalDivider(color: _palette.divider, width: 1),
          ),
          _buildDetailStat(chapterCount > 0 ? '$chapterCount' : '—', '章节'),
          SizedBox(
            height: 30,
            child: VerticalDivider(color: _palette.divider, width: 1),
          ),
          _buildDetailStat(
            book?.statusLabel?.trim().isNotEmpty == true
                ? book!.statusLabel!.trim()
                : '—',
            '状态',
          ),
        ],
      ),
    );
  }

  String _formatDetailWordCount(int? count) {
    if (count == null || count <= 0) return '—';
    if (count < 10000) return '$count';
    final double value = count / 10000;
    return '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}万';
  }

  Widget _buildDetailStat(String value, String label) => Expanded(
    child: Column(
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(color: _palette.secondaryText, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _buildDetailSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _palette.panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _palette.divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 18, color: _palette.accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );

  Widget _buildDetailExternalRow({
    required IconData icon,
    required String title,
    required String label,
    required Uri? url,
  }) {
    final VoidCallback? openSourceAction = url == null
        ? null
        : () => unawaited(_openSourceUrl(url));
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: _palette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _palette.divider),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _palette.accent.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: _palette.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(color: _palette.secondaryText, fontSize: 11),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (url != null)
            ReaderAccessibleTooltip(
              label: ReaderStrings.openSourceUrl,
              onTap: openSourceAction!,
              child: IconButton(
                onPressed: openSourceAction,
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 20,
                  color: _palette.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRefreshButton(int routeSession, String routeBookId) {
    if (widget.extensions.bookRefreshCapability == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: _catalogRevision,
      builder: (BuildContext context, int revision, Widget? child) {
        final bool enabled =
            !_bookRefreshLoading &&
            _isRouteSessionCurrent(routeSession, routeBookId);
        return ReaderAccessibleTooltip(
          label: ReaderStrings.refreshBook,
          onTap: () {
            if (enabled) unawaited(_refreshBookFromHost());
          },
          child: IconButton(
            key: const ValueKey<String>('reader-refresh-book-detail'),
            visualDensity: VisualDensity.compact,
            onPressed: enabled ? () => unawaited(_refreshBookFromHost()) : null,
            icon: _bookRefreshLoading
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 19),
          ),
        );
      },
    );
  }

  Widget _buildCatalogList(
    BuildContext sheetContext,
    int routeSession,
    String routeBookId,
    TextReaderStateStore routeStore,
  ) => Column(
    children: <Widget>[
      _buildBookRefreshAction(
        routeSession,
        routeBookId,
        title: ReaderStrings.catalog,
      ),
      Expanded(
        child: _buildCatalogListBody(
          sheetContext,
          routeSession,
          routeBookId,
          routeStore,
        ),
      ),
    ],
  );

  Widget _buildCatalogListBody(
    BuildContext sheetContext,
    int routeSession,
    String routeBookId,
    TextReaderStateStore routeStore,
  ) {
    bool catalogCompletionStarted = false;
    Widget buildList() => ValueListenableBuilder<int>(
      valueListenable: _catalogRevision,
      builder: (BuildContext context, int revision, Widget? child) {
        final String? currentChapterId = _content?.chapterId;
        if (!catalogCompletionStarted) {
          catalogCompletionStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!_isRouteSessionCurrent(
              routeSession,
              routeBookId,
              store: routeStore,
            )) {
              return;
            }
            final Future<void> catalogCompletion = _loadCompleteCatalog(
              notify: false,
            );
            await catalogCompletion;
            if (!context.mounted ||
                !_isRouteSessionCurrent(
                  routeSession,
                  routeBookId,
                  store: routeStore,
                )) {
              return;
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _centerCurrentCatalogChapterInView(
                sheetContext: sheetContext,
                routeSession: routeSession,
                routeBookId: routeBookId,
                routeStore: routeStore,
              );
            });
          });
        }
        if (_catalog.isEmpty && !_catalogHasMore && !_catalogLoading) {
          return _ReaderEmptyState(
            icon: Icons.menu_book_outlined,
            message: ReaderStrings.noChapters,
            color: _palette.secondaryText,
          );
        }
        if (currentChapterId != null &&
            _centeredCatalogChapterId != currentChapterId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _centerCurrentCatalogChapterInView(
              sheetContext: sheetContext,
              routeSession: routeSession,
              routeBookId: routeBookId,
              routeStore: routeStore,
            );
          });
        }
        return RawScrollbar(
          key: const ValueKey<String>('reader-catalog-scrollbar'),
          controller: _catalogScrollController,
          thumbVisibility: true,
          interactive: true,
          thickness: _catalogScrollbarThickness,
          radius: const Radius.circular(_catalogScrollbarThickness / 2),
          minThumbLength: _catalogScrollbarMinThumbLength,
          minOverscrollLength: _catalogScrollbarMinThumbLength,
          mainAxisMargin: 8,
          crossAxisMargin: 2,
          thumbColor: _palette.secondaryText.withValues(alpha: .82),
          // Reserve only enough gutter to keep trailing metadata off the thumb.
          child: ScrollConfiguration(
            // Rebuild stale sliver geometry without changing book PageStorage.
            key: ValueKey<(int, bool)>((_catalog.length, _catalogHasMore)),
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              key: PageStorageKey<String>('reader-catalog-scroll-$routeBookId'),
              controller: _catalogScrollController,
              padding: const EdgeInsets.fromLTRB(
                _catalogListHorizontalPadding,
                _catalogListTopPadding,
                _catalogScrollbarSafetyPadding,
                20,
              ),
              itemExtent: _catalogChapterItemExtent,
              itemCount: _catalog.length + (_catalogHasMore ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index == _catalog.length) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                      onPressed: _catalogLoading
                          ? null
                          : () async {
                              if (!_isRouteSessionCurrent(
                                routeSession,
                                routeBookId,
                                store: routeStore,
                              )) {
                                return;
                              }
                              await _loadCompleteCatalog(notify: false);
                              if (!sheetContext.mounted ||
                                  !_isRouteSessionCurrent(
                                    routeSession,
                                    routeBookId,
                                    store: routeStore,
                                  )) {
                                return;
                              }
                            },
                      child: Text(
                        _catalogLoading
                            ? ReaderStrings.loading
                            : ReaderStrings.loadMoreChapters,
                      ),
                    ),
                  );
                }
                final ReaderChapterInfo chapter = _catalog[index];
                final bool isCurrentChapter = chapter.id == currentChapterId;
                final ReaderChapterState? refreshedState =
                    _chapterAccessCoordinator?.snapshot.states[chapter.id];
                final ReaderChapterAvailability availability =
                    refreshedState == null
                    ? chapter.availability
                    : refreshedState.availability;
                final int? wordCount = refreshedState == null
                    ? chapter.wordCount
                    : refreshedState.wordCount;
                final bool hasBeenRead = refreshedState == null
                    ? chapter.hasBeenRead
                    : refreshedState.hasBeenRead;
                final bool stateLoading =
                    _chapterAccessCoordinator?.snapshot.loading == true;
                final Color? chapterBackground = isCurrentChapter
                    ? _palette.accent.withValues(alpha: .14)
                    : null;
                final Color chapterTextColor = isCurrentChapter
                    ? _palette.accent
                    : hasBeenRead
                    ? _palette.secondaryText
                    : _palette.text;
                return Material(
                  type: MaterialType.transparency,
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: ValueKey<String>(
                      'reader-catalog-chapter-${chapter.id}',
                    ),
                    dense: true,
                    visualDensity: const VisualDensity(vertical: -2),
                    minTileHeight: _catalogChapterItemExtent,
                    minVerticalPadding: 0,
                    titleAlignment: ListTileTitleAlignment.center,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: _catalogTileHorizontalPadding,
                      vertical: 2,
                    ),
                    tileColor: chapterBackground,
                    hoverColor: _palette.accent.withValues(alpha: .08),
                    selected: isCurrentChapter,
                    selectedColor: _palette.accent,
                    selectedTileColor: _palette.accent.withValues(alpha: .15),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    leading: SizedBox(
                      width: 30,
                      child: Text(
                        '${chapter.index + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: chapterTextColor,
                          fontSize: isCurrentChapter ? 12.5 : 12,
                          fontWeight: isCurrentChapter || !hasBeenRead
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    title: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            chapter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isCurrentChapter ? 14.5 : 14,
                              fontWeight: isCurrentChapter
                                  ? FontWeight.w700
                                  : hasBeenRead
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                              color: chapterTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ReaderChapterStateBadge(
                          availability: availability,
                          wordCount: wordCount,
                          hasBeenRead: hasBeenRead,
                          loading: stateLoading && refreshedState == null,
                          palette: _palette,
                          onRetry:
                              availability == ReaderChapterAvailability.failed
                              ? () => unawaited(
                                  _refreshLoadedChapterStates(
                                    chapterId: chapter.id,
                                    force: true,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                    // Keep word counts aligned independently of title length.
                    trailing: SizedBox(
                      width: 54,
                      child: Text(
                        wordCount != null && wordCount >= 0
                            ? ReaderChapterStateStrings.wordCount(wordCount)
                            : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: isCurrentChapter
                              ? chapterTextColor
                              : _palette.secondaryText,
                          fontSize: 11.5,
                          fontWeight: isCurrentChapter
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    onTap: () {
                      if (!_isRouteSessionCurrent(
                        routeSession,
                        routeBookId,
                        store: routeStore,
                      )) {
                        return;
                      }
                      Navigator.of(sheetContext).pop();
                      unawaited(
                        _openChapter(
                          chapter.id,
                          dismissControls: true,
                          showLoadingOverlay: true,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
    final ReaderChapterAccessCoordinator? coordinator =
        _chapterAccessCoordinator;
    if (coordinator == null) return buildList();
    return AnimatedBuilder(
      animation: coordinator,
      builder: (BuildContext context, Widget? child) => buildList(),
    );
  }

  Widget _buildBookRefreshAction(
    int routeSession,
    String routeBookId, {
    String title = ReaderStrings.bookDetails,
  }) {
    if (widget.extensions.bookRefreshCapability == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<int>(
      valueListenable: _catalogRevision,
      builder: (BuildContext context, int revision, Widget? child) {
        final bool enabled =
            !_bookRefreshLoading &&
            _isRouteSessionCurrent(routeSession, routeBookId);
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 12, 2),
          child: Row(
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton.icon(
                key: ValueKey<String>('reader-refresh-book-$title'),
                onPressed: enabled
                    ? () => unawaited(_refreshBookFromHost())
                    : null,
                icon: _bookRefreshLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  _bookRefreshLoading ? '更新中' : ReaderStrings.refreshBook,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _centerCurrentCatalogChapterInView({
    required BuildContext sheetContext,
    required int routeSession,
    required String routeBookId,
    required TextReaderStateStore routeStore,
  }) {
    if (!_isRouteSessionCurrent(routeSession, routeBookId, store: routeStore)) {
      return;
    }
    final String? chapterId = _content?.chapterId;
    if (chapterId == null || chapterId == _centeredCatalogChapterId) {
      return;
    }
    final int chapterIndex = _catalog.indexWhere(
      (ReaderChapterInfo chapter) => chapter.id == chapterId,
    );
    if (_catalogLoading ||
        chapterIndex < 0 ||
        !sheetContext.mounted ||
        !_catalogScrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _catalogScrollController.position;
    final double minimumVisibleOffset =
        (_catalogListTopPadding +
                (chapterIndex + 1) * _catalogChapterItemExtent -
                position.viewportDimension)
            .clamp(0, double.infinity);
    if (position.maxScrollExtent + 1 < minimumVisibleOffset) {
      // Retry after layout catches up with the completed catalog.
      if (_catalogCenterRetryCount >= 3) return;
      _catalogCenterRetryCount++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerCurrentCatalogChapterInView(
          sheetContext: sheetContext,
          routeSession: routeSession,
          routeBookId: routeBookId,
          routeStore: routeStore,
        );
      });
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _catalogCenterRetryCount = 0;
    final double centeredOffset =
        _catalogListTopPadding +
        chapterIndex * _catalogChapterItemExtent -
        (position.viewportDimension - _catalogChapterItemExtent) / 2;
    _catalogScrollController.jumpTo(
      centeredOffset.clamp(0, position.maxScrollExtent),
    );
    _centeredCatalogChapterId = chapterId;
  }

  Widget _buildBookmarkList(
    BuildContext sheetContext,
    int routeSession,
    String routeBookId,
    TextReaderStateStore routeStore,
  ) {
    if (_bookmarks.isEmpty) {
      return _ReaderEmptyState(
        icon: Icons.bookmark_border_rounded,
        message: ReaderStrings.noBookmarks,
        color: _palette.secondaryText,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: _bookmarks.length,
      itemBuilder: (BuildContext context, int index) {
        final ReaderBookmark bookmark = _bookmarks[index];
        Future<void> removeBookmark() async {
          await _queueBookmarkMutation(() async {
            if (!_isRouteSessionCurrent(
                  routeSession,
                  routeBookId,
                  store: routeStore,
                ) ||
                _bookmarks.every((item) => item.id != bookmark.id)) {
              return;
            }
            try {
              await routeStore.removeBookmark(routeBookId, bookmark.id);
            } catch (error) {
              if (_isRouteSessionCurrent(
                routeSession,
                routeBookId,
                store: routeStore,
              )) {
                await _reportFailure(
                  _asFailure(error, ReaderFailureKind.persistence),
                );
              }
              return;
            }
            if (!sheetContext.mounted ||
                !_isRouteSessionCurrent(
                  routeSession,
                  routeBookId,
                  store: routeStore,
                )) {
              return;
            }
            setState(() {
              _bookmarks = List.unmodifiable(
                _bookmarks.where((item) => item.id != bookmark.id),
              );
            });
            Navigator.of(sheetContext).pop();
          });
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Icon(
                Icons.bookmark_outline_rounded,
                size: 20,
                color: _palette.accent,
              ),
              title: Text(bookmark.chapterTitle),
              subtitle: Text(
                bookmark.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ReaderAccessibleTooltip(
                label: ReaderStrings.removeBookmark,
                onTap: removeBookmark,
                child: IconButton(
                  key: ValueKey<String>(
                    'reader-bookmark-remove-${bookmark.id}',
                  ),
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: removeBookmark,
                ),
              ),
              onTap: () {
                if (!_isRouteSessionCurrent(
                      routeSession,
                      routeBookId,
                      store: routeStore,
                    ) ||
                    bookmark.bookId != routeBookId) {
                  return;
                }
                final ReaderProgress restoreProgress = ReaderProgress(
                  chapterId: bookmark.chapterId,
                  paragraphId: bookmark.paragraphId,
                  characterOffset: bookmark.characterOffset,
                );
                Navigator.of(sheetContext).pop();
                unawaited(
                  _openChapter(
                    bookmark.chapterId,
                    dismissControls: true,
                    showLoadingOverlay: true,
                    restoreProgress: restoreProgress,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
