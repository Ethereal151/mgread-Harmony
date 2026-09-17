/// 阅读器与播放器设置页的真实可修改控件。
///
/// 本文件只承载章节预加载和音频退出行为两个应用级设置；书内字体、
/// 主题、排版等偏好仍由阅读器自己的设置面板负责。
part of 'profile_general_setting_page.dart';

class _NovelPreloadChapterCountCard extends StatefulWidget {
  const _NovelPreloadChapterCountCard({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_NovelPreloadChapterCountCard> createState() => _NovelPreloadChapterCountCardState();
}

class _NovelPreloadChapterCountCardState extends State<_NovelPreloadChapterCountCard> {
  late int _value = widget.value;

  @override
  void didUpdateWidget(covariant _NovelPreloadChapterCountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  void _change(int next) {
    if (next == _value || next < 0 || next > 5) return;
    setState(() => _value = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      key: const Key('novel-preload-chapter-count'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.regular),
        child: Row(
          children: <Widget>[
            Icon(Icons.auto_stories_outlined, color: tokens.accent),
            const SizedBox(width: AppSpacing.regular),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('小说预加载章节数量', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    _value == 0 ? '已关闭，翻到下一章时再加载' : '提前加载当前章节之后的 $_value 章',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.mutedText),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('novel-preload-count-decrease'),
              tooltip: '减少预加载章节',
              onPressed: _value > 0 ? () => _change(_value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            Semantics(
              label: '当前预加载章节数量',
              value: '$_value 章',
              liveRegion: true,
              child: SizedBox(
                width: 42,
                child: Text(_value == 0 ? '关闭' : '$_value 章', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
              ),
            ),
            IconButton(
              key: const Key('novel-preload-count-increase'),
              tooltip: '增加预加载章节',
              onPressed: _value < 5 ? () => _change(_value + 1) : null,
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioExitBehaviorCard extends StatefulWidget {
  const _AudioExitBehaviorCard({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_AudioExitBehaviorCard> createState() => _AudioExitBehaviorCardState();
}

class _AudioExitBehaviorCardState extends State<_AudioExitBehaviorCard> {
  late String _value = widget.value;

  @override
  void didUpdateWidget(covariant _AudioExitBehaviorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    const options = <(String, String, String)>[
      ('ask', '每次询问', '返回时选择继续后台播放或停止'),
      ('continue', '继续播放', '返回后自动收起到应用内播放条'),
      ('stop', '停止播放', '返回后立即停止并释放播放器'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.detailCard,
        child: Column(
          children: <Widget>[
            for (int index = 0; index < options.length; index++) ...<Widget>[
              Semantics(
                selected: _value == options[index].$1,
                button: true,
                child: InkWell(
                  key: Key('audio-exit-behavior-${options[index].$1}'),
                  onTap: () {
                    final value = options[index].$1;
                    setState(() => _value = value);
                    widget.onChanged(value);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.regular),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          _value == options[index].$1 ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                          color: _value == options[index].$1 ? tokens.accent : tokens.mutedText,
                        ),
                        const SizedBox(width: AppSpacing.regular),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(options[index].$2, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(options[index].$3, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (index < options.length - 1) Divider(height: 1, color: tokens.divider),
            ],
          ],
        ),
      ),
    );
  }
}
