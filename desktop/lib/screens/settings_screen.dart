import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/anthropic_api_service.dart';
import '../services/claude_code_service.dart';
import '../settings/app_settings.dart';
import '../settings/app_settings_controller.dart';
import '../settings/shortcut_binding.dart';
import '../storage/github/repo_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

enum _SettingsPane { storage, editor, weekly, sync, shortcuts }

/// Outcome of a Claude Code CLI availability probe shown in the Weekly pane.
enum _ClaudeProbe { idle, checking, available, unavailable }

String? resolveDirectoryPickerInitialPath(String currentPath) {
  final normalized = currentPath.trim();
  if (normalized.isEmpty) return null;

  final directory = Directory(normalized);
  if (!directory.existsSync()) {
    return null;
  }

  return normalized;
}

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
    this.onSyncEnabledChanged,
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
  final ValueChanged<bool>? onSyncEnabledChanged;
  final ValueChanged<int>? onSyncIntervalChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<int> _syncIntervals = [5, 10, 15, 30, 60, 120, 300];

  final TextEditingController _connectController = TextEditingController();
  final TextEditingController _createController = TextEditingController();
  late final TextEditingController _weeklyInstructionController;
  late final TextEditingController _claudeCliPathController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  final ClaudeCodeService _claudeService = ClaudeCodeService();
  final AnthropicApiService _anthropicService = AnthropicApiService();

  _SettingsPane _selectedPane = _SettingsPane.storage;
  List<RepoEntry> _cachedRepos = [];
  bool _isRepoLoading = false;
  bool _isRepoMutating = false;
  String? _repoError;
  _ClaudeProbe _claudeProbe = _ClaudeProbe.idle;

  @override
  void initState() {
    super.initState();
    final settings = widget.settingsController.value;
    _weeklyInstructionController =
        TextEditingController(text: settings.weeklyInstruction);
    _claudeCliPathController =
        TextEditingController(text: settings.claudeCliPath);
    _apiKeyController = TextEditingController(text: settings.anthropicApiKey);
    _modelController = TextEditingController(text: settings.anthropicModel);
    _loadCachedRepos();
  }

  @override
  void dispose() {
    _connectController.dispose();
    _createController.dispose();
    _weeklyInstructionController.dispose();
    _claudeCliPathController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
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
      initialDirectory: resolveDirectoryPickerInitialPath(currentPath),
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
      insetPadding: const EdgeInsets.all(AppDimensions.spacingLg),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
          border: Border.all(color: c.borderSubtle),
          boxShadow: AppShadows.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
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
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            'Workspace and editor preferences',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.textSecondary, height: 1.5),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: AppDimensions.spacingXl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NavigationItem(
                    selectionKey: 'storage',
                    label: 'Storage',
                    description: 'Paths and repositories',
                    icon: Icons.storage_rounded,
                    isSelected: _selectedPane == _SettingsPane.storage,
                    onTap: () =>
                        setState(() => _selectedPane = _SettingsPane.storage),
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  _NavigationItem(
                    selectionKey: 'editor',
                    label: 'Editor & Preview',
                    description: 'Zoom and reading comfort',
                    icon: Icons.text_fields_rounded,
                    isSelected: _selectedPane == _SettingsPane.editor,
                    onTap: () =>
                        setState(() => _selectedPane = _SettingsPane.editor),
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  _NavigationItem(
                    selectionKey: 'weekly',
                    label: 'Weekly',
                    description: 'Summary instruction & Claude Code',
                    icon: Icons.auto_awesome_rounded,
                    isSelected: _selectedPane == _SettingsPane.weekly,
                    onTap: () =>
                        setState(() => _selectedPane = _SettingsPane.weekly),
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  _NavigationItem(
                    selectionKey: 'sync',
                    label: 'Sync',
                    description: 'Polling and cadence',
                    icon: Icons.sync_rounded,
                    isSelected: _selectedPane == _SettingsPane.sync,
                    onTap: () =>
                        setState(() => _selectedPane = _SettingsPane.sync),
                  ),
                  const SizedBox(height: AppDimensions.spacingSm),
                  _NavigationItem(
                    selectionKey: 'shortcuts',
                    label: 'Shortcuts',
                    description: 'Keyboard bindings',
                    icon: Icons.keyboard_rounded,
                    isSelected: _selectedPane == _SettingsPane.shortcuts,
                    onTap: () =>
                        setState(() => _selectedPane = _SettingsPane.shortcuts),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: c.textSecondary,
              padding: EdgeInsets.zero,
            ),
            child: Text(
              'Done',
              style: Theme.of(context).textTheme.labelMedium,
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
      case _SettingsPane.weekly:
        return _buildWeeklyPane(c, settings);
      case _SettingsPane.sync:
        return _buildSyncPane(c, settings);
      case _SettingsPane.shortcuts:
        return _buildShortcutsPane(c);
    }
  }

  Widget _buildWeeklyPane(AppColorsExtension c, AppSettings settings) {
    return SingleChildScrollView(
      key: const ValueKey(_SettingsPane.weekly),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, AppDimensions.spacingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneHeader(
            title: 'Weekly summary',
            description:
                '캘린더 아래 Weekly 버튼을 누르면 이번 주 노트를 아래 지침대로 '
                '요약합니다. 연동 방식은 Anthropic API(API 키) 또는 Claude Code CLI '
                '중 선택할 수 있습니다.',
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: '위클리 지침',
            description:
                '요약 생성 시 모델에 전달되는 지침입니다. 이번 주 노트가 컨텍스트로 함께 전달됩니다.',
            action: _ActionButton(
              label: 'Reset',
              onTap: () {
                _weeklyInstructionController.text =
                    AppSettings.defaultWeeklyInstruction;
                widget.settingsController.setWeeklyInstruction(
                  AppSettings.defaultWeeklyInstruction,
                );
              },
            ),
            child: TextField(
              controller: _weeklyInstructionController,
              minLines: 3,
              maxLines: 8,
              style: AppTextStyles.caption.copyWith(color: c.textPrimary, height: 1.5),
              decoration: const InputDecoration(
                hintText: '이번 주에 한 일을 정리해 주세요...',
              ),
              onChanged: (value) =>
                  widget.settingsController.setWeeklyInstruction(value),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: 'AI 요약 연동',
            description: 'Weekly 버튼을 눌렀을 때 어떤 방식으로 요약을 생성할지 설정합니다.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        settings.claudeCodeEnabled ? 'Enabled' : 'Disabled',
                        style: AppTextStyles.captionBold.copyWith(color: c.textPrimary),
                      ),
                    ),
                    Switch.adaptive(
                      value: settings.claudeCodeEnabled,
                      onChanged: (value) {
                        widget.settingsController.setClaudeCodeEnabled(value);
                        setState(() => _claudeProbe = _ClaudeProbe.idle);
                      },
                    ),
                  ],
                ),
                if (settings.claudeCodeEnabled) ...[
                  const SizedBox(height: AppDimensions.spacingLg),
                  _SectionLabel(label: '연동 방식'),
                  const SizedBox(height: AppDimensions.spacingSm),
                  Wrap(
                    spacing: AppDimensions.spacingSm,
                    children: [
                      ChoiceChip(
                        label: const Text('Anthropic API'),
                        selected:
                            settings.weeklyProvider == AppSettings.providerApi,
                        onSelected: (_) {
                          widget.settingsController
                              .setWeeklyProvider(AppSettings.providerApi);
                          setState(() => _claudeProbe = _ClaudeProbe.idle);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Claude Code CLI'),
                        selected:
                            settings.weeklyProvider == AppSettings.providerCli,
                        onSelected: (_) {
                          widget.settingsController
                              .setWeeklyProvider(AppSettings.providerCli);
                          setState(() => _claudeProbe = _ClaudeProbe.idle);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimensions.spacingLg),
                  if (settings.weeklyProvider == AppSettings.providerApi)
                    ..._buildApiProviderFields(c)
                  else
                    ..._buildCliProviderFields(c),
                  if (_claudeProbe == _ClaudeProbe.available ||
                      _claudeProbe == _ClaudeProbe.unavailable)
                    _buildProbeResult(c, settings),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildApiProviderFields(AppColorsExtension c) {
    return [
      Text(
        'console.anthropic.com에서 발급한 API 키(sk-ant-...)를 입력하세요. '
        '결제 설정이 필요하며 Claude.ai 구독과 별개로 사용량만큼 과금됩니다.',
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: c.textSecondary, height: 1.5),
      ),
      const SizedBox(height: AppDimensions.spacingSm),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _apiKeyController,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTextStyles.codeMono(size: 12).copyWith(color: c.textPrimary),
              decoration: const InputDecoration(hintText: 'sk-ant-...'),
              onChanged: (value) {
                widget.settingsController.setAnthropicApiKey(value);
                setState(() => _claudeProbe = _ClaudeProbe.idle);
              },
            ),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          _ActionButton(
            label: _claudeProbe == _ClaudeProbe.checking ? 'Checking...' : 'Test',
            onTap: _claudeProbe == _ClaudeProbe.checking ? null : _probe,
          ),
        ],
      ),
      const SizedBox(height: AppDimensions.spacingLg),
      _SectionLabel(label: '모델'),
      const SizedBox(height: AppDimensions.spacingSm),
      Text(
        '기본값은 claude-opus-4-8 입니다. claude-sonnet-4-6 등으로 바꾸면 비용을 낮출 수 있습니다.',
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: c.textSecondary, height: 1.5),
      ),
      const SizedBox(height: AppDimensions.spacingSm),
      TextField(
        controller: _modelController,
        style: AppTextStyles.codeMono(size: 12).copyWith(color: c.textPrimary),
        decoration: const InputDecoration(hintText: AppSettings.defaultAnthropicModel),
        onChanged: (value) =>
            widget.settingsController.setAnthropicModel(value),
      ),
    ];
  }

  List<Widget> _buildCliProviderFields(AppColorsExtension c) {
    return [
      Text(
        'Claude Code CLI(claude --print)로 요약을 생성합니다. CLI가 구독 계정으로 '
        '로그인되어 있으면 구독을 사용합니다. 비워두면 일반 설치 경로를 자동으로 찾고, '
        'macOS GUI 앱에서 찾지 못하면 절대 경로를 입력하세요 (예: /opt/homebrew/bin/claude).',
        style: Theme.of(context)
            .textTheme
            .labelSmall!
            .copyWith(color: c.textSecondary, height: 1.5),
      ),
      const SizedBox(height: AppDimensions.spacingSm),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _claudeCliPathController,
              style: AppTextStyles.codeMono(size: 12).copyWith(color: c.textPrimary),
              decoration: const InputDecoration(hintText: 'claude'),
              onChanged: (value) {
                widget.settingsController.setClaudeCliPath(value);
                setState(() => _claudeProbe = _ClaudeProbe.idle);
              },
            ),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          _ActionButton(
            label: _claudeProbe == _ClaudeProbe.checking ? 'Checking...' : 'Test',
            onTap: _claudeProbe == _ClaudeProbe.checking ? null : _probe,
          ),
        ],
      ),
    ];
  }

  Widget _buildProbeResult(AppColorsExtension c, AppSettings settings) {
    final ok = _claudeProbe == _ClaudeProbe.available;
    final isApi = settings.weeklyProvider == AppSettings.providerApi;
    final message = ok
        ? (isApi ? 'API 키가 확인되었습니다.' : 'Claude Code를 찾았습니다.')
        : (isApi
            ? 'API 키를 확인하지 못했습니다. 키와 네트워크를 확인하세요.'
            : 'Claude Code를 찾지 못했습니다. 경로를 확인하세요.');
    return Padding(
      padding: const EdgeInsets.only(top: AppDimensions.spacingSm),
      child: Row(
        children: [
          Icon(
            ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 14,
            color: ok ? c.success : c.error,
          ),
          const SizedBox(width: AppDimensions.spacingXs),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.micro.copyWith(color: ok ? c.success : c.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _probe() async {
    setState(() => _claudeProbe = _ClaudeProbe.checking);
    final settings = widget.settingsController.value;
    // Defense-in-depth: the probe must never crash the app, whatever a provider
    // call does. Any unexpected error simply reports "unavailable".
    var ok = false;
    try {
      if (settings.weeklyProvider == AppSettings.providerApi) {
        ok = await _anthropicService.validateKey(apiKey: _apiKeyController.text);
      } else {
        ok =
            await _claudeService.isAvailable(cliPath: _claudeCliPathController.text);
      }
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() =>
        _claudeProbe = ok ? _ClaudeProbe.available : _ClaudeProbe.unavailable);
  }

  Widget _buildStoragePane(
    AppColorsExtension c,
    AppSettings settings,
    List<RepoEntry> recentRepos,
  ) {
    return SingleChildScrollView(
      key: const ValueKey(_SettingsPane.storage),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, AppDimensions.spacingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PaneHeader(
            title: 'Workspace storage',
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
            title: 'GitHub background sync',
            description:
                'Turn periodic remote polling on or off without disconnecting the repository.',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    settings.syncEnabled ? 'Enabled' : 'Disabled',
                    style: AppTextStyles.captionBold.copyWith(color: c.textPrimary),
                  ),
                ),
                Switch.adaptive(
                  value: settings.syncEnabled,
                  onChanged: (value) async {
                    await widget.settingsController.setSyncEnabled(value);
                    widget.onSyncEnabledChanged?.call(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: 'Synced repository',
            description:
                'Recent repositories stay one click away so switching sync targets feels lightweight.',
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
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.textMuted),
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
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.error),
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
      padding: const EdgeInsets.fromLTRB(28, 28, 28, AppDimensions.spacingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneHeader(
            title: 'Reading & zoom',
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
                      style: AppTextStyles.sectionHeading.copyWith(color: c.textPrimary),
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
                  style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: AppDimensions.spacingLg),
                _ZoomPreviewCard(contentScale: settings.contentScale),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          _DetailCard(
            title: 'Search context lines',
            description:
                'Number of lines shown above and below each search match.',
            child: Row(
              children: [
                _IconStepButton(
                  icon: Icons.remove_rounded,
                  onTap: () => widget.settingsController.setSearchContextLines(
                    settings.searchContextLines - 1,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingMd),
                Text(
                  '${settings.searchContextLines}',
                  style: AppTextStyles.sectionHeading.copyWith(color: c.textPrimary),
                ),
                const SizedBox(width: AppDimensions.spacingMd),
                _IconStepButton(
                  icon: Icons.add_rounded,
                  onTap: () => widget.settingsController.setSearchContextLines(
                    settings.searchContextLines + 1,
                  ),
                ),
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
      padding: const EdgeInsets.fromLTRB(28, 28, 28, AppDimensions.spacingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneHeader(
            title: 'Background sync',
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
                  onSelected: settings.syncEnabled
                      ? (_) async {
                          await widget.settingsController
                              .setSyncIntervalSeconds(seconds);
                          widget.onSyncIntervalChanged?.call(seconds);
                        }
                      : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutsPane(AppColorsExtension c) {
    final bindings = widget.settingsController.bindings;

    return SingleChildScrollView(
      key: const ValueKey(_SettingsPane.shortcuts),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, AppDimensions.spacingXl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PaneHeader(
            title: 'Keyboard shortcuts',
            description:
                'View and customise the key combinations used across the app.',
          ),
          const SizedBox(height: AppDimensions.spacingLg),
          ...bindings.map((binding) => Padding(
                padding: const EdgeInsets.only(bottom: AppDimensions.spacingSm),
                child: _ShortcutCard(
                  binding: binding,
                  onEdit: binding.isFixed
                      ? null
                      : () => _showShortcutCaptureDialog(binding),
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _showShortcutCaptureDialog(ShortcutBinding binding) async {
    final c = context.colors;
    ShortcutBinding? captured;

    final result = await showDialog<ShortcutBinding>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
                side: BorderSide(color: c.border),
              ),
              title: Text(
                '${binding.action.label} 단축키 변경',
                style: Theme.of(context).textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w700, color: c.textPrimary),
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '새 키 조합을 입력하세요',
                      style: AppTextStyles.caption.copyWith(color: c.textSecondary),
                    ),
                    const SizedBox(height: AppDimensions.spacingLg),
                    Focus(
                      autofocus: true,
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        // Ignore bare modifier keys.
                        if (event.logicalKey == LogicalKeyboardKey.metaLeft ||
                            event.logicalKey == LogicalKeyboardKey.metaRight ||
                            event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                            event.logicalKey == LogicalKeyboardKey.shiftRight) {
                          return KeyEventResult.handled;
                        }
                        final hw = HardwareKeyboard.instance;
                        setDialogState(() {
                          captured = binding.copyWith(
                            key: event.logicalKey,
                            shift: hw.isShiftPressed,
                          );
                        });
                        return KeyEventResult.handled;
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimensions.spacingLg,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceLight,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
                          border: Border.all(color: c.accent),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          captured?.displayLabel ?? binding.displayLabel,
                          style: AppTextStyles.codeMono(
                            size: 16,
                            weight: FontWeight.w700,
                          ).copyWith(color: c.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    '취소',
                    style: TextStyle(color: c.textMuted),
                  ),
                ),
                FilledButton(
                  onPressed: captured == null
                      ? null
                      : () => Navigator.of(ctx).pop(captured),
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await widget.settingsController.setShortcutBinding(result);
    }
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.selectionKey,
    required this.label,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String selectionKey;
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
      borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
      // Plain Container (not AnimatedContainer): selection must change atomically
      // with the icon/text/bar, which switch instantly. Animating only the
      // background/border made the previously-selected item linger and read as a
      // flicker when a different item was clicked.
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingMd,
          vertical: AppDimensions.spacingMd,
        ),
        decoration: BoxDecoration(
          color: isSelected ? c.accentSubtle : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
          border: Border.all(
            color: isSelected
                ? c.accent.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSelected)
              Container(
                key: ValueKey('settings-nav-selected-$selectionKey'),
                width: 3,
                height: 32,
                margin: const EdgeInsets.only(
                  right: AppDimensions.spacingMd,
                  top: 1,
                ),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusPill),
                ),
              )
            else
              const SizedBox(width: 3 + AppDimensions.spacingMd),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
                border: Border.all(
                  color: isSelected
                      ? c.accent.withValues(alpha: 0.18)
                      : c.border,
                ),
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
                    style: AppTextStyles.captionBold.copyWith(color: isSelected ? c.textPrimary : c.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppTextStyles.micro.copyWith(color: c.textMuted, height: 1.4),
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
          style: AppTextStyles.pageTitle.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        Text(
          description,
          style: AppTextStyles.caption.copyWith(color: c.textSecondary, height: 1.6),
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
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
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(color: c.textPrimary),
                    ),
                    const SizedBox(height: AppDimensions.spacingXs),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.textSecondary, height: 1.6),
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
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.borderSubtle),
        backgroundColor: c.surface,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd, vertical: AppDimensions.spacingSm),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusStandard)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w700, color: c.textPrimary),
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        border: Border.all(color: c.border),
      ),
      child: SelectableText(
        path,
        style: AppTextStyles.codeMono(size: 12, height: 1.6).copyWith(color: c.textPrimary),
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current source',
            style: AppTextStyles.microBold.copyWith(letterSpacing: 0.4, color: c.textMuted),
          ),
          const SizedBox(height: AppDimensions.spacingXs),
          Text(
            activeRepo?.fullName ?? 'Not connected',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(color: c.textPrimary),
          ),
          if (activeRepo != null) ...[
            const SizedBox(height: 2),
            Text(
              'Branch ${activeRepo!.branch}',
              style: AppTextStyles.codeMono(size: 11).copyWith(color: c.textSecondary),
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
      style: AppTextStyles.microBold.copyWith(letterSpacing: 0.5, color: c.textMuted),
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
      borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
      child: AnimatedContainer(
        duration: AppDimensions.animFast,
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? c.accentSubtle : c.surface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
          border: Border.all(color: isActive ? c.accent : c.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.codeMono(size: 12).copyWith(
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
      borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
          border: Border.all(color: c.border),
        ),
        child: Icon(icon, size: 16, color: c.textSecondary),
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.binding, required this.onEdit});

  final ShortcutBinding binding;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  binding.action.label,
                  style: AppTextStyles.captionBold.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppDimensions.spacingSm, vertical: AppDimensions.spacingXs),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSubtle),
                    border: Border.all(color: c.borderSubtle),
                  ),
                  child: Text(
                    binding.displayLabel,
                    style: AppTextStyles.codeMono(size: 12).copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          if (binding.isFixed)
            Text(
              'Fixed',
              style: AppTextStyles.micro.copyWith(color: c.textMuted),
            )
          else
            _ActionButton(
              label: 'Edit',
              onTap: onEdit,
            ),
        ],
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: AppTextStyles.microBold.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: AppDimensions.spacingMd),
          Text(
            'Daily Note',
            style: AppTextStyles.scaledHeadline(contentScale).copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: AppDimensions.spacingSm),
          Text(
            'A compact preview makes zoom changes feel immediate even before you close settings.',
            style: AppTextStyles.scaledCaption(contentScale).copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}
