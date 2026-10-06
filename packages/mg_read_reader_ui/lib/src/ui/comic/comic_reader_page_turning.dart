/// 漫画阅读器的点按和按键翻页行为。
///
/// 职责：将翻页偏好和触控位置转换为视口滚动请求。
/// 注意：滚动控制器和阅读会话状态仍由 _ComicReaderViewState 持有。
part of 'comic_reader_view.dart';

// ignore_for_file: invalid_use_of_protected_member
extension _ComicReaderPageTurning on _ComicReaderViewState {
  static const double _tapTurnZoneFraction = .25;
  static const double _singleHandTurnZoneFraction = .3;

  bool get _isPageMode =>
      _preferences.readingMode != ComicReadingMode.verticalScroll;

  void _handlePageChanged(int page) {
    if (_disposed || _restoring || !_isPageMode) return;
    final List<_ComicListEntry> entries = _pageEntries();
    if (page < 0 || page >= entries.length) return;
    final _ComicListEntry entry = entries[page];
    if (entry case final _ComicImageEntry image) {
      _updateProgressFromImage(image, 0);
      _imageRetryCoordinator.onViewportChanged();
      if (page >= entries.length - 2) {
        unawaited(_loadNextAdjacent(image.chapter.info.index + 1));
      }
    } else if (entry case final _ComicBoundaryEntry boundary) {
      unawaited(_loadNextAdjacent(boundary.index));
    }
  }

  void _handleReadingSurfaceTap(TapUpDetails details) {
    if (_preferences.pageTurnShortcuts) {
      final int? direction = _tapPageTurnDirection(details);
      if (direction != null) {
        _scheduleScrollByViewport(direction);
        return;
      }
    }
    _setControlsVisible(!_controlsVisible);
  }

  int? _tapPageTurnDirection(TapUpDetails details) {
    if (_preferences.singleHandMode) {
      final double width = MediaQuery.sizeOf(context).width;
      final double edgeZone = width * _singleHandTurnZoneFraction;
      final double x = details.localPosition.dx;
      if (x <= edgeZone || x >= width - edgeZone) return 1;
      return null;
    }
    if (_preferences.pageTurnLayout == ComicPageTurnLayout.horizontal) {
      final double width = MediaQuery.sizeOf(context).width;
      final double edgeZone = width * _tapTurnZoneFraction;
      final double x = details.localPosition.dx;
      if (x <= edgeZone) {
        return _preferences.readingMode ==
                ComicReadingMode.horizontalRightToLeft
            ? 1
            : -1;
      }
      if (x >= width - edgeZone) {
        return _preferences.readingMode ==
                ComicReadingMode.horizontalRightToLeft
            ? -1
            : 1;
      }
      return null;
    }
    final double edgeZone = _viewportHeight * _tapTurnZoneFraction;
    final double y = details.localPosition.dy;
    if (y <= edgeZone) return -1;
    if (y >= _viewportHeight - edgeZone) return 1;
    return null;
  }

  void _scheduleScrollByViewport(int direction) {
    // Let the scroll view finish resolving the pointer-up gesture first. Without
    // this deferral its zero-velocity ballistic activity can cancel the tap's
    // programmatic scroll before it moves.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      // Use one more frame so the Scrollable has fully left its pointer-up
      // activity before animateTo takes ownership of the position.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) _scrollByViewport(direction);
      });
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _scrollByViewport(int direction, {bool animate = true}) {
    if (_isPageMode) {
      _turnPage(direction, animate: animate);
      return;
    }
    _scrollBy(
      direction * _viewportHeight * _preferences.pageTurnFraction,
      animate: animate,
    );
  }

  double get _pageTurnDistance =>
      _viewportHeight * _preferences.pageTurnFraction;

  void _scrollBy(double delta, {bool animate = true}) {
    if (!_preferences.pageTurnShortcuts ||
        !_foreground ||
        _settingsVisible ||
        _controlsVisible ||
        _currentChapter == null ||
        !_scrollController.hasClients) {
      return;
    }
    final double target = (_scrollController.offset + delta).clamp(
      0,
      _scrollController.position.maxScrollExtent,
    );
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _scrollController.jumpTo(target);
    } else {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _turnPage(int direction, {bool animate = true}) {
    if (!_preferences.pageTurnShortcuts ||
        !_foreground ||
        _settingsVisible ||
        _controlsVisible ||
        _currentChapter == null ||
        !_pageController.hasClients) {
      return;
    }
    final int current = _pageController.page?.round() ?? 0;
    final int target = (current + direction).clamp(
      0,
      math.max(_pageEntries().length - 1, 0),
    );
    if (target == current) return;
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(target);
    } else {
      unawaited(
        _pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }
}
