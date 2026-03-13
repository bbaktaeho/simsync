import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../settings/app_settings.dart';
import '../settings/app_settings_controller.dart';
import '../storage/github/repo_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

enum _SettingsPane { storage, editor, sync }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsController,
    this.activeRepo,
    this.loadCachedRepos,
    this.onLocalNotePathChanged,
    this.onRepoSelected,
    this.onCreateRepo,
    this.onConnectRepo,
    this.onPickLocalNotePath,
    this.onSyncIntervalChanged,
  });

  final AppSettingsController settingsController;
  final RepoEntry? activeRepo;
  final Future<List<RepoEntry>> Function()? loadCachedRepos;
  final Future<void> Function(String path)? onLocalNotePathChanged;
  final Future<void> Function(RepoEntry entry)? onRepoSelected;
  final Future<RepoEntry> Function(String name)? onCreateRepo;
  final Future<RepoEntry> Function(String owner, String repo)? onConnectRepo;
  final Future<String?> Function(String currentPath)? onPickLocalNotePath;
  final ValueChanged<int>? onSyncIntervalChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<int> _syncIntervals = [5, 10, 15, 30, 60, 120, 300];

  final TextEditingController _connectController = TextEditingController();
  final TextEditingController _createController = TextEditingController();

  _SettingsPane _selectedPane = _SettingsPane.storage;
  List<RepoEntry> _cachedRepos = [];
  bool _isRepoLoading = false;
  bool _isRepoMutating = false;
  String? _repoError;

  @override
  void initState() {
    super.initState();
    _loadCachedRepos();
  }

  @override
  void dispose() {
    _connectController.dispose();
    _createController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedRepos() async {
    final loader = widget.loadCachedRepos;
    if (loader == null) return;

    setState(() {
      _isRepoLoading = true;
      _repoError = null;
    });

    try {
      final repos = await loader();
      if (!mounted) return;
      setState(() => _cachedRepos = repos);
    } catch (_) {
      if (!mounted) return;
      setState(() => _repoError = '최근 저장소 목록을 불러오지 못했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isRepoLoading = false);
      }
    }
  }

  Future<void> _changeLocalPath() async {
    final currentPath = widget.settingsController.value.localNotePath;
    final picker = widget.onPickLocalNotePath ?? _defaultDirectoryPicker;
    final pickedPath = await picker(currentPath);
    if (pickedPath == null || pickedPath.isEmpty) return;

    final callback = widget.onLocalNotePathChanged;
    if (callback != null) {
      await callback(pickedPath);
    } else {
      await widget.settingsController.setLocalNotePath(pickedPath);
    }
  }

  Future<String?> _defaultDirectoryPicker(String currentPath) {
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: '로컬 노트 저장 경로 선택',
      initialDirectory: currentPath,
    );
  }

  Future<void> _selectRepo(RepoEntry entry) async {
    final callback = widget.onRepoSelected;
    if (callback == null) return;

    setState(() {
      _isRepoMutating = true;
      _repoError = null;
    });
    try {
      await callback(entry);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _repoError = '저장소 전환 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isRepoMutating = false);
      }
    }
  }

  Future<void> _createRepo() async {
    final name = _createController.text.trim();
    if (name.isEmpty || widget.onCreateRepo == null) return;

    setState(() {
      _isRepoMutating = true;
      _repoError = null;
    });
    try {
      final entry = await widget.onCreateRepo!(name);
      _createController.clear();
      await _selectRepo(entry);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _repoError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isRepoMutating = false);
      }
    }
  }

  Future<void> _connectRepo() async {
    final input = _connectController.text.trim();
    final parts = input.split('/');
    if (parts.length != 2 ||
        parts[0].trim().isEmpty ||
        parts[1].trim().isEmpty ||
        widget.onConnectRepo == null) {
      setState(() => _repoError = 'owner/repo 형식으로 입력하세요.');
      return;
    }

    setState(() {
      _isRepoMutating = true;
      _repoError = null;
    });
    try {
      final entry = await widget.onConnectRepo!(
        parts[0].trim(),
        parts[1].trim(),
      );
      await _selectRepo(entry);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _repoError = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isRepoMutating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = viewport.width < 760
        ? viewport.width - 16
        : math.min(980.0, viewport.width - 32);
    final dialogHeight = viewport.height < 560
        ? viewport.height - 16
        : math.min(640.0, viewport.height - 32);
    final recentRepos = _cachedRepos
        .where((entry) => entry.fullName != widget.activeRepo?.fullName)
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Row(
            children: [
              _buildNavigationRail(c),
              VerticalDivider(width: 1, thickness: 1, color: c.border),
              Expanded(
                child: AnimatedBuilder(
                  animation: widget.settingsController,
                  builder: (context, _) {
                    final settings = widget.settingsController.value;
                    return AnimatedSwitcher(
                      duration: AppDimensions.animFast,
                      child: _buildPane(c, settings, recentRepos),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationRail(AppColorsExtension c) {
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        border: Border(right: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            'Workspace and editor preferences',
            style: GoogleFonts.manrope(
              fontSize: 12,
              height: 1.5,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingXl),
          _NavigationItem(
            label: 'Storage',
            description: 'Paths and repositories',
            icon: Icons.storage_rounded,
            isSelected: _selectedPane == _SettingsPane.storage,
            onTap: () => setState(() => _selectedPane = _SettingsPane.storage),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          _NavigationItem(
            label: 'Editor & Preview',
            description: 'Zoom and reading comfort',
            icon: Icons.text_fields_rounded,
            isSelected: _selectedPane == _SettingsPane.editor,
            onTap: () => setState(() => _selectedPane = _SettingsPane.editor),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          _NavigationItem(
            label: 'Sync',
            description: 'Polling and cadence',
            icon: Icons.sync_rounded,
            isSelected: _selectedPane == _SettingsPane.sync,
            onTap: () => setState(() => _selectedPane = _SettingsPane.sync),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: c.textSecondary,
              padding: EdgeInsets.zero,
            ),
            child: Text(
              'Done',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPane(
    AppColorsExtension c,
    AppSettings settings,
    List<RepoEntry> recentRepos,
  ) {
    switch (_selectedPane) {
      case _SettingsPane.storage:
        return _buildStoragePane(c, settings, recentRepos);
      case _SettingsPane.editor:
        return _buildEditorPane(c, settings);
      case _SettingsPane.sync:
        return _buildSyncPane(c, settings);
    }
  }

  Widget _buildStoragePane(
    AppColorsExtension c,
    AppSettings settings,
    List<RepoEntry> recentRepos,
  ) {
    return SingleChildScrollView(
      key: const ValueKey(_SettingsPane.storage),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PaneHeader(
            title: 'Storage',
            description:
                'Control where local notes live and which GitHub repository is connected.',
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: 'Local note path',
            description: 'The directory used for local-only markdown notes.',
            action: _ActionButton(label: 'Change...', onTap: _changeLocalPath),
            child: _PathPreview(path: settings.localNotePath),
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: 'Synced repository',
            description:
                'Recent repositories stay one click away so switching sync targets feels lightweight.',
            action: _ActionButton(label: 'Change Repository...', onTap: () {}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CurrentRepoCard(activeRepo: widget.activeRepo),
                const SizedBox(height: AppDimensions.spacingLg),
                _SectionLabel(label: 'Recent repositories'),
                const SizedBox(height: AppDimensions.spacingSm),
                if (_isRepoLoading)
                  const LinearProgressIndicator(minHeight: 2)
                else if (recentRepos.isEmpty)
                  Text(
                    'No recent repositories',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: c.textMuted,
                    ),
                  )
                else
                  Wrap(
                    spacing: AppDimensions.spacingSm,
                    runSpacing: AppDimensions.spacingSm,
                    children: recentRepos
                        .map(
                          (entry) => _RepoChip(
                            label: entry.fullName,
                            isActive:
                                entry.fullName == widget.activeRepo?.fullName,
                            onTap: _isRepoMutating
                                ? null
                                : () => _selectRepo(entry),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: AppDimensions.spacingLg),
                _SectionLabel(label: 'Connect existing repository'),
                const SizedBox(height: AppDimensions.spacingSm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _connectController,
                        decoration: const InputDecoration(
                          hintText: 'owner/repo',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingSm),
                    _ActionButton(
                      label: 'Connect',
                      onTap: _isRepoMutating ? null : _connectRepo,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spacingLg),
                _SectionLabel(label: 'Create new repository'),
                const SizedBox(height: AppDimensions.spacingSm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _createController,
                        decoration: const InputDecoration(
                          hintText: 'notes-archive',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingSm),
                    _ActionButton(
                      label: 'Create',
                      onTap: _isRepoMutating ? null : _createRepo,
                    ),
                  ],
                ),
                if (_repoError != null) ...[
                  const SizedBox(height: AppDimensions.spacingSm),
                  Text(
                    _repoError!,
                    style: GoogleFonts.manrope(fontSize: 12, color: c.error),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPane(AppColorsExtension c, AppSettings settings) {
    return SingleChildScrollView(
      key: const ValueKey(_SettingsPane.editor),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneHeader(
            title: 'Editor & Preview',
            description:
                'Tune reading density and make sure zoom interactions feel immediate.',
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: 'Content zoom',
            description:
                'Applies only to the markdown editor and preview surfaces.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _IconStepButton(
                      icon: Icons.remove_rounded,
                      onTap: widget.settingsController.decreaseContentScale,
                    ),
                    const SizedBox(width: AppDimensions.spacingMd),
                    Text(
                      '${(settings.contentScale * 100).round()}%',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingMd),
                    _IconStepButton(
                      icon: Icons.add_rounded,
                      onTap: widget.settingsController.increaseContentScale,
                    ),
                  ],
                ),
                Slider(
                  min: AppSettings.minContentScale,
                  max: AppSettings.maxContentScale,
                  value: settings.contentScale,
                  onChanged: (value) {
                    widget.settingsController.setContentScale(value);
                  },
                ),
                Text(
                  'Shortcuts: cmd + +, cmd + -, cmd + wheel, trackpad pinch',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingLg),
                _ZoomPreviewCard(contentScale: settings.contentScale),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncPane(AppColorsExtension c, AppSettings settings) {
    return SingleChildScrollView(
      key: const ValueKey(_SettingsPane.sync),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneHeader(
            title: 'Sync',
            description:
                'Control how frequently GitHub commit state is checked while you are working.',
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: 'GitHub sync interval',
            description:
                'A shorter cadence feels snappier. A longer cadence is quieter.',
            child: Wrap(
              spacing: AppDimensions.spacingSm,
              runSpacing: AppDimensions.spacingSm,
              children: _syncIntervals.map((seconds) {
                final selected = settings.syncIntervalSeconds == seconds;
                return ChoiceChip(
                  label: Text('${seconds}s'),
                  selected: selected,
                  onSelected: (_) async {
                    await widget.settingsController.setSyncIntervalSeconds(
                      seconds,
                    );
                    widget.onSyncIntervalChanged?.call(seconds);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: AppDimensions.animFast,
        padding: const EdgeInsets.all(AppDimensions.spacingMd),
        decoration: BoxDecoration(
          color: isSelected ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? c.borderSubtle : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? c.accentSubtle : c.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 16,
                color: isSelected ? c.accent : c.textSecondary,
              ),
            ),
            const SizedBox(width: AppDimensions.spacingMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      height: 1.4,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        Text(
          description,
          style: GoogleFonts.manrope(
            fontSize: 13,
            height: 1.6,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.description,
    required this.child,
    this.action,
  });

  final String title;
  final String description;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingXs),
                    Text(
                      description,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        height: 1.6,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: AppDimensions.spacingMd),
                action!,
              ],
            ],
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          child,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.borderSubtle),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PathPreview extends StatelessWidget {
  const _PathPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: SelectableText(
        path,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          color: c.textPrimary,
          height: 1.6,
        ),
      ),
    );
  }
}

class _CurrentRepoCard extends StatelessWidget {
  const _CurrentRepoCard({required this.activeRepo});

  final RepoEntry? activeRepo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current source',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            activeRepo?.fullName ?? 'Not connected',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          if (activeRepo != null) ...[
            const SizedBox(height: 2),
            Text(
              'Branch ${activeRepo!.branch}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: c.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      label,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: c.textMuted,
      ),
    );
  }
}

class _RepoChip extends StatelessWidget {
  const _RepoChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: AppDimensions.animFast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? c.accentSubtle : c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isActive ? c.accent : c.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            color: isActive ? c.accent : c.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _IconStepButton extends StatelessWidget {
  const _IconStepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: 16, color: c.textSecondary),
      ),
    );
  }
}

class _ZoomPreviewCard extends StatelessWidget {
  const _ZoomPreviewCard({required this.contentScale});

  final double contentScale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.surface, c.surfaceHover],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            'Daily Note',
            style: GoogleFonts.manrope(
              fontSize: 22 * contentScale,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            'A compact preview makes zoom changes feel immediate even before you close settings.',
            style: GoogleFonts.manrope(
              fontSize: 13 * contentScale,
              height: 1.6,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
