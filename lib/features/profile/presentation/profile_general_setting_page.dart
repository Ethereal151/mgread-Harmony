/// “我的”中尚未单独拆分路由的通用设置页面。
///
/// 职责：
/// - 以真实能力说明阅读、外观与隐私设置，不展示“功能建设中”占位。
/// - 直接持久化小说预加载、音频退出、书架布局和诊断日志设置。
/// - 将阅读器内设置和系统按需授权边界解释清楚，不伪造平台状态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mg_read/app/app_theme.dart';
import 'package:mg_read/core/settings/settings.dart';
import 'package:mg_read/features/profile/presentation/about_document_page.dart';
import 'package:mg_read/shared/presentation/widgets/app_secondary_page_chrome.dart';

part 'profile_reading_player_settings_components.dart';

class ProfileGeneralSettingPage extends ConsumerWidget {
  const ProfileGeneralSettingPage({required this.settingId, required this.onBackRequested, super.key});

  final String settingId;
  final VoidCallback onBackRequested;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appSettingsStatusProvider);
    final AppSettingsManager settings = ref.watch(appSettingsProvider);
    final _GeneralSettingSpec spec = _specFor(settingId);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AppSecondaryPageContent(
          child: Column(
            children: <Widget>[
              AppSecondaryPageTopBar(
                title: spec.title,
                onBack: onBackRequested,
                headerKey: const Key('secondary-placeholder-top-bar'),
                backButtonKey: const Key('secondary-placeholder-back'),
              ),
              Expanded(
                child: ListView(
                  key: Key('profile-general-setting-$settingId'),
                  padding: const EdgeInsets.fromLTRB(
                    AppDetailMetrics.horizontalPadding,
                    AppSpacing.regular,
                    AppDetailMetrics.horizontalPadding,
                    AppSpacing.section,
                  ),
                  children: <Widget>[
                    _SettingHero(spec: spec),
                    const SizedBox(height: AppSpacing.section),
                    ...switch (settingId) {
                      'reading-settings' => _readingSections(context, settings),
                      'theme-appearance' => _appearanceSections(context, settings),
                      'privacy-permissions' => _privacySections(context, settings),
                      _ => _fallbackSections(context),
                    },
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _readingSections(BuildContext context, AppSettingsManager settings) => <Widget>[
    const _SectionHeading(title: '小说阅读', description: '只保留影响章节加载的设置'),
    const SizedBox(height: AppSpacing.regular),
    _NovelPreloadChapterCountCard(
      value: settings.get(AppSettingKeys.novelPreloadChapterCount),
      onChanged: (int value) async {
        await settings.set(AppSettingKeys.novelPreloadChapterCount, value);
      },
    ),
    const SizedBox(height: AppSpacing.section),
    const _SectionHeading(title: '音频播放器', description: '选择离开音频播放器时的默认行为'),
    const SizedBox(height: AppSpacing.regular),
    _AudioExitBehaviorCard(
      value: settings.get(AppSettingKeys.audioExitBehavior),
      onChanged: (String value) async {
        await settings.set(AppSettingKeys.audioExitBehavior, value);
      },
    ),
    const SizedBox(height: AppSpacing.regular),
    const _InlineNotice(icon: Icons.tune_rounded, message: '字体、主题、排版、翻页和评论入口，请打开书籍后在阅读器工具栏的“设置”中调整。它们不会在这里重复显示。'),
  ];

  List<Widget> _appearanceSections(BuildContext context, AppSettingsManager settings) {
    final String layout = settings.get(AppSettingKeys.homeLayoutMode);
    final AppThemeColor themeColor = AppThemeColor.fromId(settings.get(AppSettingKeys.themeColor));
    return <Widget>[
      const _SectionHeading(title: '界面主题色', description: '只影响应用界面；小说、漫画、音频和视频阅读器独立管理主题'),
      const SizedBox(height: AppSpacing.regular),
      _ThemeColorCard(
        value: themeColor,
        onChanged: (AppThemeColor value) async {
          await settings.set(AppSettingKeys.themeColor, value.id);
        },
      ),
      const SizedBox(height: AppSpacing.regular),
      _AppearancePreviewCard(color: themeColor),
      const SizedBox(height: AppSpacing.section),
      const _SectionHeading(title: '书架布局', description: '选择书架首页的默认浏览方式'),
      const SizedBox(height: AppSpacing.regular),
      _LayoutModeCard(
        value: layout,
        onChanged: (String value) async {
          await settings.set(AppSettingKeys.homeLayoutMode, value);
        },
      ),
      const SizedBox(height: AppSpacing.comfortable),
      const _InlineNotice(icon: Icons.dark_mode_outlined, message: '浅色模式提供多种主题色；深色模式使用 OLED 冷黑主题。阅读器内主题不受此处影响。'),
    ];
  }

  List<Widget> _privacySections(BuildContext context, AppSettingsManager settings) {
    final bool diagnosticsEnabled = settings.get(AppSettingKeys.diagnosticsEnabled);
    return <Widget>[
      const _SectionHeading(title: '按需权限', description: '只在你使用对应功能时请求系统授权'),
      const SizedBox(height: AppSpacing.regular),
      const _SettingsCard(
        children: <Widget>[
          _InfoRow(icon: Icons.folder_open_outlined, title: '文件访问', description: '导入导出时由系统文件选择器授权', trailing: '按需'),
          _InfoRow(icon: Icons.camera_alt_outlined, title: '相机', description: '扫描局域网同步二维码时请求', trailing: '按需'),
          _InfoRow(icon: Icons.wifi_rounded, title: '网络', description: '用于数据源访问、媒体加载和局域网同步', trailing: '核心能力'),
        ],
      ),
      const SizedBox(height: AppSpacing.section),
      const _SectionHeading(title: '诊断与隐私', description: '由你决定是否保留本机诊断日志'),
      const SizedBox(height: AppSpacing.regular),
      _SettingsCard(
        children: <Widget>[
          _SwitchInfoRow(
            icon: Icons.analytics_outlined,
            title: '诊断日志',
            description: '仅保存在本机，用于排查应用与数据源问题',
            value: diagnosticsEnabled,
            onChanged: (bool value) async {
              await settings.set(AppSettingKeys.diagnosticsEnabled, value);
            },
          ),
          _ActionInfoRow(
            icon: Icons.policy_outlined,
            title: '隐私政策',
            description: '查看数据处理与权限使用说明',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AboutDocumentPage(kind: AboutDocumentKind.privacy, onBackRequested: () => Navigator.of(context).pop()),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.comfortable),
      const _InlineNotice(icon: Icons.lock_outline_rounded, message: '普通设置按应用功能保存；导入导出和局域网同步按对应功能处理。'),
    ];
  }

  List<Widget> _fallbackSections(BuildContext context) => const <Widget>[
    _InlineNotice(icon: Icons.info_outline_rounded, message: '当前页面没有可配置项目。'),
  ];
}

class _SettingHero extends StatelessWidget {
  const _SettingHero({required this.spec});

  final _GeneralSettingSpec spec;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.featureSurface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.accent.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.comfortable),
        child: Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(color: tokens.accent, borderRadius: AppRadii.detailControl),
                child: Icon(spec.icon, color: theme.colorScheme.onPrimary, size: 25),
              ),
            ),
            const SizedBox(width: AppSpacing.regular),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(spec.heroTitle, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.unit),
                  Text(spec.description, style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.compact),
            DecoratedBox(
              decoration: BoxDecoration(color: tokens.surface, borderRadius: AppRadii.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.regular, vertical: AppSpacing.compact),
                child: Text(
                  spec.badge,
                  style: theme.textTheme.bodySmall?.copyWith(color: tokens.accent, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.unit),
        Text(description, style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
        boxShadow: <BoxShadow>[BoxShadow(color: tokens.shadow.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: AppRadii.detailCard,
        child: Column(
          children: <Widget>[
            for (int index = 0; index < children.length; index++) ...<Widget>[
              children[index],
              if (index < children.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 64),
                  child: Divider(height: 1, color: tokens.divider),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.description, this.trailing});
  final IconData icon;
  final String title;
  final String description;
  final String? trailing;

  @override
  Widget build(BuildContext context) => _SettingsRowShell(
    icon: icon,
    title: title,
    description: description,
    trailing: trailing == null ? null : _StatusPill(label: trailing!),
  );
}

class _SwitchInfoRow extends StatelessWidget {
  const _SwitchInfoRow({required this.icon, required this.title, required this.description, required this.value, required this.onChanged});
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _SettingsRowShell(
    icon: icon,
    title: title,
    description: description,
    trailing: Switch(value: value, onChanged: onChanged),
  );
}

class _ActionInfoRow extends StatelessWidget {
  const _ActionInfoRow({required this.icon, required this.title, required this.description, required this.onTap});
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const Key('privacy-policy-action'),
      onTap: onTap,
      child: _SettingsRowShell(icon: icon, title: title, description: description, trailing: const Icon(Icons.chevron_right_rounded)),
    ),
  );
}

class _SettingsRowShell extends StatelessWidget {
  const _SettingsRowShell({required this.icon, required this.title, required this.description, this.trailing});
  final IconData icon;
  final String title;
  final String description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.regular, AppSpacing.regular, AppSpacing.compact, AppSpacing.regular),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(color: tokens.accentSoft, borderRadius: AppRadii.discoveryTile),
              child: Icon(icon, size: 19, color: tokens.accent),
            ),
          ),
          const SizedBox(width: AppSpacing.regular),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: AppSpacing.compact), trailing!],
        ],
      ),
    );
  }
}

class _AppearancePreviewCard extends StatelessWidget {
  const _AppearancePreviewCard({required this.color});

  final AppThemeColor color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      key: const Key('appearance-settings-preview'),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.comfortable),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(color.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.unit),
                  Text('柔和、清晰，适合长时间浏览', style: theme.textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
                ],
              ),
            ),
            for (final Color color in <Color>[tokens.pageBackground, tokens.featureSurface, tokens.accent]) ...<Widget>[
              const SizedBox(width: AppSpacing.compact),
              Container(
                width: 32,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: AppRadii.pill,
                  border: Border.all(color: tokens.divider),
                ),
              ),
            ],
          ],
        ),
      ),
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

class _LayoutModeCard extends StatefulWidget {
  const _LayoutModeCard({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_LayoutModeCard> createState() => _LayoutModeCardState();
}

class _LayoutModeCardState extends State<_LayoutModeCard> {
  late String _value = widget.value;

  @override
  void didUpdateWidget(covariant _LayoutModeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadii.detailCard,
        border: Border.all(color: tokens.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.regular),
        child: SegmentedButton<String>(
          key: const Key('appearance-layout-mode'),
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'list', icon: Icon(Icons.view_agenda_outlined), label: Text('列表')),
            ButtonSegment<String>(value: 'card', icon: Icon(Icons.grid_view_rounded), label: Text('卡片')),
          ],
          selected: <String>{_value},
          showSelectedIcon: false,
          onSelectionChanged: (Set<String> selected) {
            final String value = selected.single;
            setState(() => _value = value);
            widget.onChanged(value);
          },
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: tokens.mutedSurface, borderRadius: AppRadii.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.compact, vertical: AppSpacing.unit),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final AppThemeTokens tokens = AppThemeTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: tokens.mutedSurface, borderRadius: AppRadii.detailControl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.regular),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: tokens.mutedText),
            const SizedBox(width: AppSpacing.compact),
            Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens.mutedText)),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneralSettingSpec {
  const _GeneralSettingSpec({
    required this.title,
    required this.heroTitle,
    required this.description,
    required this.badge,
    required this.icon,
  });
  final String title;
  final String heroTitle;
  final String description;
  final String badge;
  final IconData icon;
}

_GeneralSettingSpec _specFor(String settingId) => switch (settingId) {
  'reading-settings' => const _GeneralSettingSpec(
    title: '阅读器与播放器',
    heroTitle: '阅读器与播放器',
    description: '管理章节预加载和离开音频播放器时的行为',
    badge: '直接生效',
    icon: Icons.menu_book_rounded,
  ),
  'theme-appearance' => const _GeneralSettingSpec(
    title: '主题与外观',
    heroTitle: '暖光视觉',
    description: '统一、克制的浅色界面，保持各页面观感一致',
    badge: '当前主题',
    icon: Icons.palette_outlined,
  ),
  'privacy-permissions' => const _GeneralSettingSpec(
    title: '隐私与权限',
    heroTitle: '本地优先',
    description: '权限按需申请，诊断和敏感数据由你掌控',
    badge: '透明可控',
    icon: Icons.shield_outlined,
  ),
  _ => const _GeneralSettingSpec(title: '设置', heroTitle: '设置', description: '当前没有可配置项目', badge: 'MgRead', icon: Icons.settings_outlined),
};
