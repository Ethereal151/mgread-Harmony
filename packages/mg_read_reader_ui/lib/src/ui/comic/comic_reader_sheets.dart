part of 'comic_reader_view.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ComicReaderSheetActions on _ComicReaderViewState {
  Future<void> _showSettings() async {
    if (_settingsVisible) return;
    final int session = _sessionGeneration;
    final String bookId = widget.bookId;
    final ComicReaderDataSource source = widget.dataSource;
    final ComicReaderStateStore store = widget.stateStore;
    bool isCurrent() => _isSession(session, bookId, source, store);
    final int sheetGeneration = _beginSheet();
    // The sheet needs the normal system-bar geometry. This is a session-only
    // override; the persisted immersive preference is restored on dismissal.
    await _setSettingsVisible(true);
    if (!mounted || _disposed || !isCurrent()) {
      await _setSettingsVisible(false);
      return;
    }
    _setControlsVisible(false);
    final Future<void> sheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF202326),
      builder: (BuildContext context) {
        _captureSheetContext(context, sheetGeneration);
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(VoidCallback) sheetSetState,
              ) {
                void update(
                  ComicReaderPreferences value, {
                  bool persist = true,
                }) {
                  if (!isCurrent()) {
                    Navigator.of(context).pop();
                    return;
                  }
                  final ComicReaderPreferences normalized = value.normalized();
                  final ComicReaderProgress? anchor = _progress;
                  final bool layoutChanged =
                      normalized.imageSpacing != _preferences.imageSpacing;
                  setState(() {
                    _preferences = normalized;
                    _preferencesAuthoritative = true;
                  });
                  _preferencesDirty = !persist;
                  sheetSetState(() {});
                  if (layoutChanged) {
                    _restoring = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_disposed) return;
                      _restorePosition(anchor);
                      _restoring = false;
                    });
                  }
                  unawaited(_syncAwake());
                  if (persist) {
                    unawaited(_savePreferences(normalized, store: store));
                  }
                }

                void commit() {
                  if (!isCurrent()) return;
                  _preferencesDirty = false;
                  unawaited(_savePreferences(_preferences, store: store));
                }

                return _darkSheet(
                  SafeArea(
                    child: SizedBox(
                      height: MediaQuery.sizeOf(context).height * .55,
                      child: Column(
                        children: <Widget>[
                          _sheetHeader(ComicReaderStrings.settings),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                              children: <Widget>[
                                _settingSlider(
                                  label: ComicReaderStrings.brightness,
                                  value: _preferences.brightness,
                                  min: .25,
                                  max: 1,
                                  onChanged: (double value) => update(
                                    _preferences.copyWith(brightness: value),
                                    persist: false,
                                  ),
                                  onChangeEnd: (double value) => commit(),
                                ),
                                if (_platformCapabilities.keepScreenOn)
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      ComicReaderStrings.keepAwake,
                                    ),
                                    value: _preferences.keepScreenOn,
                                    onChanged: (bool value) => update(
                                      _preferences.copyWith(
                                        keepScreenOn: value,
                                      ),
                                    ),
                                  ),
                                if (_platformCapabilities.volumeKeyPageTurning)
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      ComicReaderStrings.pageTurnShortcuts,
                                    ),
                                    value: _preferences.pageTurnShortcuts,
                                    onChanged: (bool value) => update(
                                      _preferences.copyWith(
                                        pageTurnShortcuts: value,
                                      ),
                                    ),
                                  ),
                                DropdownButtonFormField<double>(
                                  key: const ValueKey<String>(
                                    'comic-reader-page-turn-fraction',
                                  ),
                                  initialValue: _preferences.pageTurnFraction,
                                  decoration: const InputDecoration(
                                    labelText:
                                        ComicReaderStrings.pageTurnFraction,
                                  ),
                                  items: ComicReaderPreferences
                                      .pageTurnFractions
                                      .map(
                                        (double fraction) =>
                                            DropdownMenuItem<double>(
                                              value: fraction,
                                              child: Text(
                                                '${(fraction * 100).round()}%',
                                              ),
                                            ),
                                      )
                                      .toList(),
                                  onChanged: (double? value) {
                                    if (value != null) {
                                      update(
                                        _preferences.copyWith(
                                          pageTurnFraction: value,
                                        ),
                                      );
                                    }
                                  },
                                ),
                                DropdownButtonFormField<ComicPageTurnLayout>(
                                  key: const ValueKey<String>(
                                    'comic-reader-page-turn-layout',
                                  ),
                                  initialValue: _preferences.pageTurnLayout,
                                  decoration: const InputDecoration(
                                    labelText:
                                        ComicReaderStrings.pageTurnLayout,
                                  ),
                                  items:
                                      const <
                                        DropdownMenuItem<ComicPageTurnLayout>
                                      >[
                                        DropdownMenuItem<ComicPageTurnLayout>(
                                          value: ComicPageTurnLayout.vertical,
                                          child: Text(
                                            ComicReaderStrings.pageTurnVertical,
                                          ),
                                        ),
                                        DropdownMenuItem<ComicPageTurnLayout>(
                                          value: ComicPageTurnLayout.horizontal,
                                          child: Text(
                                            ComicReaderStrings
                                                .pageTurnHorizontal,
                                          ),
                                        ),
                                      ],
                                  onChanged: (ComicPageTurnLayout? value) {
                                    if (value != null) {
                                      update(
                                        _preferences.copyWith(
                                          pageTurnLayout: value,
                                        ),
                                      );
                                    }
                                  },
                                ),
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    ComicReaderStrings.singleHandMode,
                                  ),
                                  value: _preferences.singleHandMode,
                                  onChanged: (bool value) => update(
                                    _preferences.copyWith(
                                      singleHandMode: value,
                                    ),
                                  ),
                                ),
                                if (_platformCapabilities.immersiveMode)
                                  SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      ComicReaderStrings.immersive,
                                    ),
                                    value: _preferences.immersiveMode,
                                    onChanged: (bool value) => update(
                                      _preferences.copyWith(
                                        immersiveMode: value,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
        );
      },
    );
    unawaited(
      sheet.whenComplete(() {
        _finishSheet(sheetGeneration);
        if (_settingsVisible) unawaited(_setSettingsVisible(false));
        if (isCurrent()) {
          _preferencesDirty = false;
          unawaited(_savePreferences(_preferences, store: store));
        }
      }),
    );
  }

  Widget _settingSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          SizedBox(width: 76, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }

  Widget _darkSheet(Widget child) {
    final ReaderPalette palette = ReaderPalette.fromPreset(
      ReaderThemePreset.deepNight,
    );
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF202326),
        ),
        scaffoldBackgroundColor: const Color(0xFF202326),
        fontFamily: readerDefaultFontFamily,
        fontFamilyFallback: const <String>[
          'PingFang SC',
          'Microsoft YaHei',
          'Noto Sans CJK SC',
          'sans-serif',
        ],
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: palette.text,
          displayColor: palette.text,
        ),
        iconTheme: IconThemeData(color: palette.text),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: palette.text),
        child: child,
      ),
    );
  }

  Widget _sheetHeader(String title) {
    return SizedBox(
      height: 52,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }
}
