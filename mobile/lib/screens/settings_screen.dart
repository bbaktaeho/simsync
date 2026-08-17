import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../settings/app_settings_controller.dart';
import '../storage/github/repo_cache.dart';
import '../storage/sync_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_text_styles.dart';

class SettingsScreen extends StatelessWidget {
  final AppSettingsController settingsController;
  final String? avatarUrl;
  final RepoEntry? activeRepo;
  final VoidCallback? onLogout;
  final SyncEngine? syncEngine;
  final ValueChanged<bool>? onSyncEnabledChanged;

  const SettingsScreen({
    super.key,
    required this.settingsController,
    this.avatarUrl,
    this.activeRepo,
    this.onLogout,
    this.syncEngine,
    this.onSyncEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.scaffold,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '설정',
          style: AppTextStyles.sectionHeading.copyWith(color: c.textPrimary),
        ),
      ),
      body: ListenableBuilder(
        listenable: settingsController,
        builder: (context, _) {
          final settings = settingsController.value;
          return ListView(
            padding: const EdgeInsets.symmetric(
              vertical: AppDimensions.spacingLg,
            ),
            children: [
              _buildSection(
                context,
                c,
                title: 'Storage',
                children: [
                  _buildInfoTile(
                    context,
                    c,
                    icon: Icons.folder_outlined,
                    title: '로컬 경로',
                    subtitle: settings.localNotePath.isEmpty
                        ? '설정되지 않음'
                        : settings.localNotePath,
                  ),
                  _buildDivider(c),
                  _buildInfoTile(
                    context,
                    c,
                    icon: Icons.cloud_outlined,
                    title: '동기화 리포지토리',
                    subtitle: activeRepo != null
                        ? '${activeRepo!.owner}/${activeRepo!.repo}'
                        : '연결되지 않음',
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              _buildSection(
                context,
                c,
                title: 'Appearance',
                children: [
                  _buildThemeTile(context, c, settings),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              _buildSection(
                context,
                c,
                title: 'Editor & Preview',
                children: [
                  _buildStepperTile(
                    context,
                    c,
                    icon: Icons.text_fields_rounded,
                    title: '콘텐츠 배율',
                    value: settings.contentScale.toStringAsFixed(1),
                    onDecrease: settings.contentScale > AppSettings.minContentScale
                        ? () => settingsController.setContentScale(
                              settings.contentScale - 0.1,
                            )
                        : null,
                    onIncrease: settings.contentScale < AppSettings.maxContentScale
                        ? () => settingsController.setContentScale(
                              settings.contentScale + 0.1,
                            )
                        : null,
                  ),
                  _buildDivider(c),
                  _buildStepperTile(
                    context,
                    c,
                    icon: Icons.format_line_spacing_rounded,
                    title: '검색 컨텍스트 줄 수',
                    value: '${settings.searchContextLines}',
                    onDecrease: settings.searchContextLines >
                            AppSettings.minSearchContextLines
                        ? () => settingsController.setSearchContextLines(
                              settings.searchContextLines - 1,
                            )
                        : null,
                    onIncrease: settings.searchContextLines <
                            AppSettings.maxSearchContextLines
                        ? () => settingsController.setSearchContextLines(
                              settings.searchContextLines + 1,
                            )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              _buildSection(
                context,
                c,
                title: 'Sync',
                children: [
                  _buildSwitchTile(
                    context,
                    c,
                    icon: Icons.sync_rounded,
                    title: '자동 동기화',
                    value: settings.syncEnabled,
                    onChanged: (value) {
                      settingsController.setSyncEnabled(value);
                      onSyncEnabledChanged?.call(value);
                    },
                  ),
                  _buildDivider(c),
                  _buildStepperTile(
                    context,
                    c,
                    icon: Icons.timer_outlined,
                    title: '동기화 간격 (초)',
                    value: '${settings.syncIntervalSeconds}',
                    onDecrease: settings.syncIntervalSeconds >
                            AppSettings.minSyncIntervalSeconds
                        ? () {
                            final newVal = settings.syncIntervalSeconds - 5;
                            settingsController.setSyncIntervalSeconds(
                              newVal.clamp(
                                AppSettings.minSyncIntervalSeconds,
                                AppSettings.maxSyncIntervalSeconds,
                              ),
                            );
                          }
                        : null,
                    onIncrease: settings.syncIntervalSeconds <
                            AppSettings.maxSyncIntervalSeconds
                        ? () {
                            final newVal = settings.syncIntervalSeconds + 5;
                            settingsController.setSyncIntervalSeconds(
                              newVal.clamp(
                                AppSettings.minSyncIntervalSeconds,
                                AppSettings.maxSyncIntervalSeconds,
                              ),
                            );
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              _buildSection(
                context,
                c,
                title: 'Account',
                children: [
                  _buildAccountTile(context, c),
                  _buildDivider(c),
                  _buildLogoutTile(context, c),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingLg),
              _buildSection(
                context,
                c,
                title: 'App',
                children: [
                  _buildInfoTile(
                    context,
                    c,
                    icon: Icons.info_outline_rounded,
                    title: '버전',
                    subtitle: '1.0.0',
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spacingXxl),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    AppColorsExtension c, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingLg,
          ),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
              color: c.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingLg,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius:
                BorderRadius.circular(AppDimensions.radiusComfortable),
            border: Border.all(color: c.borderSubtle),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDivider(AppColorsExtension c) {
    return Divider(
      height: 1,
      thickness: 1,
      color: c.borderSubtle,
      indent: AppDimensions.spacingLg,
    );
  }

  Widget _buildInfoTile(
    BuildContext context,
    AppColorsExtension c, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingMd,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.textSecondary),
          const SizedBox(width: AppDimensions.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: c.textMuted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperTile(
    BuildContext context,
    AppColorsExtension c, {
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onDecrease,
    VoidCallback? onIncrease,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.textSecondary),
          const SizedBox(width: AppDimensions.spacingMd),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: c.textPrimary,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius:
                  BorderRadius.circular(AppDimensions.radiusStandard),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StepperButton(
                  icon: Icons.remove_rounded,
                  onTap: onDecrease,
                  colors: c,
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 40),
                  alignment: Alignment.center,
                  child: Text(
                    value,
                    style: AppTextStyles.captionSemibold.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                ),
                _StepperButton(
                  icon: Icons.add_rounded,
                  onTap: onIncrease,
                  colors: c,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 테마 모드 선택. 데스크탑과 같은 3단(시스템/라이트/다크).
  Widget _buildThemeTile(
    BuildContext context,
    AppColorsExtension c,
    AppSettings settings,
  ) {
    const labels = {
      AppThemeMode.system: '시스템',
      AppThemeMode.light: '라이트',
      AppThemeMode.dark: '다크',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingMd,
      ),
      child: Row(
        children: [
          Icon(Icons.brightness_6_outlined, size: 20, color: c.textSecondary),
          const SizedBox(width: AppDimensions.spacingMd),
          Expanded(
            child: Text(
              '테마',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium!
                  .copyWith(color: c.textPrimary),
            ),
          ),
          SegmentedButton<AppThemeMode>(
            segments: [
              for (final entry in labels.entries)
                ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {settings.themeMode},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(AppTextStyles.micro),
            ),
            onSelectionChanged: (v) =>
                settingsController.setThemeMode(v.first),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    AppColorsExtension c, {
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingSm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.textSecondary),
          const SizedBox(width: AppDimensions.spacingMd),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: c.textPrimary,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: c.accent,
            activeThumbColor: c.textOnAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile(BuildContext context, AppColorsExtension c) {
    final url = avatarUrl?.trim();
    final hasAvatar = url != null && url.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingLg,
        vertical: AppDimensions.spacingMd,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: hasAvatar ? NetworkImage(url) : null,
            backgroundColor: c.surfaceHover,
            child: !hasAvatar
                ? Icon(Icons.person, size: 20, color: c.textMuted)
                : null,
          ),
          const SizedBox(width: AppDimensions.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeRepo?.owner ?? 'Unknown',
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  'GitHub',
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutTile(BuildContext context, AppColorsExtension c) {
    return GestureDetector(
      onTap: onLogout,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingLg,
          vertical: AppDimensions.spacingMd,
        ),
        child: Row(
          children: [
            Icon(Icons.logout_rounded, size: 20, color: c.error),
            const SizedBox(width: AppDimensions.spacingMd),
            Text(
              '로그아웃',
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                color: c.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final AppColorsExtension colors;

  const _StepperButton({
    required this.icon,
    this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingSm),
        child: Icon(
          icon,
          size: 16,
          color: isDisabled ? colors.textMuted : colors.textSecondary,
        ),
      ),
    );
  }
}
