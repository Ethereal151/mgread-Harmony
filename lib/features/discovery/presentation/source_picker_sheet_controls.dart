/// Header and persistent actions for the discovery source picker.
///
/// These controls own only visual and interaction state supplied by the sheet;
/// source selection and persistence stay with the parent library.
part of 'source_picker_sheet.dart';

class _SourcePickerHeader extends StatelessWidget {
  const _SourcePickerHeader({
    required this.availableCount,
    required this.recentCount,
    required this.selectedSourceLabel,
    required this.selectedFilter,
    required this.query,
    required this.searchController,
    required this.onFilterChanged,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onClose,
  });

  final int availableCount;
  final int recentCount;
  final String selectedSourceLabel;
  final _SourceFilter selectedFilter;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<_SourceFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controlSurface = isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.025), tokens.mutedSurface)
        : tokens.mutedSurface.withValues(alpha: 0.78);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? tokens.surface : theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.comfortable, AppSpacing.compact, AppSpacing.comfortable, AppSpacing.regular),
        child: Column(
          children: <Widget>[
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: tokens.divider, borderRadius: AppRadii.pill),
            ),
            const SizedBox(height: AppSpacing.compact),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '选择数据源',
                        key: const Key('discovery-source-picker-title'),
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$availableCount 个可用 · 当前：$selectedSourceLabel',
                        key: const Key('discovery-source-picker-summary'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedText),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('discovery-source-picker-close'),
                  tooltip: '关闭',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 22),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.regular),
            Container(
              key: const Key('discovery-source-picker-filters'),
              height: 44,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: controlSurface, borderRadius: AppRadii.control),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _SourceFilterButton(
                      label: '可用',
                      count: availableCount,
                      selected: selectedFilter == _SourceFilter.available,
                      onPressed: () => onFilterChanged(_SourceFilter.available),
                    ),
                  ),
                  Expanded(
                    child: _SourceFilterButton(
                      label: '最近使用',
                      count: recentCount,
                      selected: selectedFilter == _SourceFilter.recent,
                      onPressed: () => onFilterChanged(_SourceFilter.recent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.compact),
            SizedBox(
              height: 46,
              child: TextField(
                key: const Key('discovery-source-picker-search'),
                controller: searchController,
                onChanged: onQueryChanged,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.regular),
                  hintText: selectedFilter == _SourceFilter.recent ? '搜索最近使用的数据源' : '搜索数据源名称或功能',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(color: tokens.mutedText),
                  prefixIcon: Icon(Icons.search_rounded, color: tokens.mutedText, size: 20),
                  prefixIconConstraints: const BoxConstraints(minWidth: 44),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          key: const Key('discovery-source-picker-search-clear'),
                          tooltip: '清除搜索',
                          onPressed: onClearQuery,
                          icon: Icon(Icons.cancel_rounded, size: 18, color: tokens.mutedText),
                        ),
                  filled: true,
                  fillColor: controlSurface,
                  border: OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: tokens.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: tokens.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadii.control,
                    borderSide: BorderSide(color: tokens.focusRing, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceFilterButton extends StatelessWidget {
  const _SourceFilterButton({required this.label, required this.count, required this.selected, required this.onPressed});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppThemeTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '筛选数据源：$label，$count 个',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.discoveryButton,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadii.discoveryButton,
          child: AnimatedContainer(
            duration: AppMotion.navigationSelection,
            decoration: BoxDecoration(
              color: selected ? theme.colorScheme.surface : Colors.transparent,
              borderRadius: AppRadii.discoveryButton,
              border: Border.all(color: selected ? tokens.divider : Colors.transparent),
              boxShadow: selected
                  ? <BoxShadow>[BoxShadow(color: tokens.shadow.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? theme.colorScheme.onSurface : tokens.mutedText,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected ? tokens.accentSoft : tokens.divider.withValues(alpha: 0.58),
                      borderRadius: AppRadii.pill,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      child: Text(
                        '$count',
                        key: ValueKey<String>('discovery-source-picker-filter-count-$label'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected ? tokens.accent : tokens.mutedText,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourcePickerFooter extends StatelessWidget {
  const _SourcePickerFooter({required this.onManagePressed, required this.onAddPressed});

  final VoidCallback onManagePressed;
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(AppSpacing.comfortable, AppSpacing.compact, AppSpacing.comfortable, AppSpacing.compact),
        child: Row(
          children: <Widget>[
            Expanded(
              child: SizedBox(
                height: AppSpacing.minimumTouchTarget,
                child: OutlinedButton.icon(
                  key: const Key('discovery-source-picker-manage'),
                  onPressed: onManagePressed,
                  icon: const Icon(Icons.tune_rounded, size: 19),
                  label: const Text('管理数据源'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: tokens.divider),
                    shape: const RoundedRectangleBorder(borderRadius: AppRadii.control),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.compact),
            Expanded(
              child: SizedBox(
                height: AppSpacing.minimumTouchTarget,
                child: FilledButton.icon(
                  key: const Key('discovery-source-picker-add'),
                  onPressed: onAddPressed,
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('添加数据源'),
                  style: FilledButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: AppRadii.control)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
