part of 'profile_general_setting_page.dart';

/// Appearance-only controls for the independently persisted day and night palettes.

class _AppearancePreviewCard extends StatelessWidget {
  const _AppearancePreviewCard({required this.lightColor, required this.darkColor});

  final AppThemeColor lightColor;
  final AppDarkThemeColor darkColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    final AppThemeTokens lightTokens = AppTheme.light(color: lightColor).extension<AppThemeTokens>()!;
    final AppThemeTokens darkTokens = AppTheme.dark(color: darkColor).extension<AppThemeTokens>()!;
    return DecoratedBox(
      key: const Key('appearance-settings-preview'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.comfortable),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('主题预览', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.unit),
            Text('日间与夜间主题分别保存', style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
            const SizedBox(height: AppSpacing.regular),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ThemePreviewStrip(label: '日间 · ${lightColor.label}', tokens: lightTokens),
                ),
                const SizedBox(width: AppSpacing.regular),
                Expanded(
                  child: _ThemePreviewStrip(label: '夜间 · ${darkColor.label}', tokens: darkTokens),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePreviewStrip extends StatelessWidget {
  const _ThemePreviewStrip({required this.label, required this.tokens});

  final String label;
  final AppThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.unit),
        Row(
          children: <Widget>[
            for (final Color color in <Color>[tokens.pageBackground, tokens.featureSurface, tokens.accent]) ...<Widget>[
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppRadii.pill,
                    border: Border.all(color: tokens.divider),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.unit),
            ],
          ],
        ),
      ],
    );
  }
}

class _ThemeColorCard extends StatefulWidget {
  const _ThemeColorCard({required this.value, required this.onChanged});

  final AppThemeColor value;
  final ValueChanged<AppThemeColor> onChanged;

  @override
  State<_ThemeColorCard> createState() => _ThemeColorCardState();
}

class _ThemeColorCardState extends State<_ThemeColorCard> {
  late AppThemeColor _value = widget.value;

  @override
  void didUpdateWidget(covariant _ThemeColorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      key: const Key('appearance-theme-color'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.regular),
        child: Wrap(
          spacing: AppSpacing.compact,
          runSpacing: AppSpacing.compact,
          children: <Widget>[
            for (final AppThemeColor color in AppThemeColor.values)
              ChoiceChip(
                key: Key('appearance-theme-color-${color.id}'),
                avatar: CircleAvatar(backgroundColor: color.accent, radius: 9),
                label: Text(color.label),
                selected: color == _value,
                onSelected: (_) {
                  setState(() => _value = color);
                  widget.onChanged(color);
                },
                selectedColor: tokens.accentSoft,
                side: BorderSide(color: color == _value ? tokens.accent : tokens.divider),
              ),
          ],
        ),
      ),
    );
  }
}

class _DarkThemeColorCard extends StatefulWidget {
  const _DarkThemeColorCard({required this.value, required this.onChanged});

  final AppDarkThemeColor value;
  final ValueChanged<AppDarkThemeColor> onChanged;

  @override
  State<_DarkThemeColorCard> createState() => _DarkThemeColorCardState();
}

class _DarkThemeColorCardState extends State<_DarkThemeColorCard> {
  late AppDarkThemeColor _value = widget.value;

  @override
  void didUpdateWidget(covariant _DarkThemeColorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      key: const Key('appearance-dark-theme-color'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.regular),
        child: Wrap(
          spacing: AppSpacing.compact,
          runSpacing: AppSpacing.compact,
          children: <Widget>[
            for (final AppDarkThemeColor color in AppDarkThemeColor.values)
              ChoiceChip(
                key: Key('appearance-dark-theme-color-${color.id}'),
                avatar: CircleAvatar(backgroundColor: color.accent, radius: 9),
                label: Text(color.label),
                selected: color == _value,
                onSelected: (_) {
                  setState(() => _value = color);
                  widget.onChanged(color);
                },
                selectedColor: tokens.accentSoft,
                side: BorderSide(color: color == _value ? color.accent : tokens.divider),
              ),
          ],
        ),
      ),
    );
  }
}
