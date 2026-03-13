import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../settings/app_settings_controller.dart';
import '../storage/github/repo_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settingsController,
    this.activeRepo,
    this.onLocalNotePathChanged,
    this.onPickLocalNotePath,
    this.onSyncIntervalChanged,
  });

  final AppSettingsController settingsController;
  final RepoEntry? activeRepo;
  final Future<void> Function(String path)? onLocalNotePathChanged;
  final Future<String?> Function(String currentPath)? onPickLocalNotePath;
  final ValueChanged<int>? onSyncIntervalChanged;

  static const List<int> _syncIntervals = [5, 10, 15, 30, 60, 120, 300];

  Future<void> _changeLocalPath(String currentPath) async {
    final picker = onPickLocalNotePath ?? _defaultDirectoryPicker;
    final pickedPath = await picker(currentPath);
    if (pickedPath == null || pickedPath.isEmpty) return;

    final callback = onLocalNotePathChanged;
    if (callback != null) {
      await callback(pickedPath);
    } else {
      await settingsController.setLocalNotePath(pickedPath);
    }
  }

  Future<String?> _defaultDirectoryPicker(String currentPath) {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: '로컬 노트 저장 경로 선택',
      initialDirectory: currentPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      title: Text(
        'Settings',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 520,
        child: AnimatedBuilder(
          animation: settingsController,
          builder: (context, _) {
            final settings = settingsController.value;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SectionTitle(label: 'Storage'),
                  _InfoRow(
                    label: 'Local note path',
                    value: settings.localNotePath,
                    action: _ActionButton(
                      label: 'Change...',
                      onPressed: () => _changeLocalPath(settings.localNotePath),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  _InfoRow(
                    label: 'Synced repository',
                    value: activeRepo?.fullName ?? 'Not connected',
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  const _InfoRow(
                    label: 'Synced note layout',
                    value: 'notes/{YYYY-MM}/{DD}/{title}.md',
                  ),
                  const SizedBox(height: AppDimensions.spacingLg),
                  _SectionTitle(label: 'Editor & Preview'),
                  _SettingCard(
                    label: 'Content zoom',
                    hint:
                        'Shortcuts: cmd + , cmd + +, cmd + - / cmd + wheel / trackpad pinch',
                    child: Row(
                      children: [
                        _StepButton(
                          icon: Icons.remove_rounded,
                          onTap: () =>
                              settingsController.decreaseContentScale(),
                        ),
                        const SizedBox(width: AppDimensions.spacingMd),
                        Text(
                          '${(settings.contentScale * 100).round()}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppDimensions.spacingMd),
                        _StepButton(
                          icon: Icons.add_rounded,
                          onTap: () =>
                              settingsController.increaseContentScale(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingLg),
                  _SectionTitle(label: 'Sync'),
                  _SettingCard(
                    label: 'GitHub sync interval',
                    hint:
                        'Current polling interval for GitHub commit SHA checks',
                    child: Wrap(
                      spacing: AppDimensions.spacingSm,
                      runSpacing: AppDimensions.spacingSm,
                      children: _syncIntervals.map((seconds) {
                        final selected =
                            settings.syncIntervalSeconds == seconds;
                        return ChoiceChip(
                          label: Text('${seconds}s'),
                          selected: selected,
                          onSelected: (_) async {
                            await settingsController.setSyncIntervalSeconds(
                              seconds,
                            );
                            onSyncIntervalChanged?.call(seconds);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: c.textMuted,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.action});

  final String label;
  final String value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _SettingCard(
      label: label,
      action: action,
      child: SelectableText(
        value,
        style: TextStyle(fontSize: 13, color: c.textPrimary, height: 1.5),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.label,
    required this.child,
    this.hint,
    this.action,
  });

  final String label;
  final Widget child;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: AppDimensions.spacingSm),
                action!,
              ],
            ],
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          child,
          if (hint != null) ...[
            const SizedBox(height: AppDimensions.spacingSm),
            Text(hint!, style: TextStyle(fontSize: 11, color: c.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onPressed});

  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: c.accent,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppDimensions.borderRadiusSm),
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: 14, color: c.textSecondary),
      ),
    );
  }
}
