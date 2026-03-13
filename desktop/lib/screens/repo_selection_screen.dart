import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/github/github_api_client.dart';
import '../storage/github/repo_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

class RepoSelectionScreen extends StatefulWidget {
  final String accessToken;
  final String userLogin;
  final String avatarUrl;
  final Future<void> Function(RepoEntry entry) onRepoSelected;
  final RepoCache repoCache;

  const RepoSelectionScreen({
    super.key,
    required this.accessToken,
    required this.userLogin,
    required this.avatarUrl,
    required this.onRepoSelected,
    required this.repoCache,
  });

  @override
  State<RepoSelectionScreen> createState() => _RepoSelectionScreenState();
}

class _RepoSelectionScreenState extends State<RepoSelectionScreen>
    with SingleTickerProviderStateMixin {
  List<RepoEntry> _cachedRepos = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _localNotePath = '';

  bool _showCreateForm = false;
  bool _showConnectForm = false;

  final _createController = TextEditingController();
  final _connectController = TextEditingController();

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));
    _fadeController.forward();
    _loadCache();
    _loadLocalNotePath();
  }

  Future<void> _loadCache() async {
    final entries = await widget.repoCache.load();
    if (mounted) {
      setState(() => _cachedRepos = entries);
    }
  }

  Future<void> _loadLocalNotePath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('local_note_path');
    if (saved != null && saved.isNotEmpty) {
      setState(() => _localNotePath = saved);
    } else {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      setState(() => _localNotePath = '$home/Documents/SimSync');
    }
  }

  Future<void> _pickLocalPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '로컬 노트 저장 경로 선택',
      initialDirectory: _localNotePath,
    );
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_note_path', result);
      setState(() => _localNotePath = result);
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _createController.dispose();
    _connectController.dispose();
    super.dispose();
  }

  GitHubApiClient _makeClient() {
    return GitHubApiClient(
      token: widget.accessToken,
      owner: widget.userLogin,
      repo: '_',
    );
  }

  Future<void> _handleCreateRepo() async {
    final name = _createController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final client = _makeClient();
    try {
      await client.createRepo(name: name);
      final entry = RepoEntry(owner: widget.userLogin, repo: name);
      await widget.repoCache.add(entry);
      if (mounted) {
        await widget.onRepoSelected(entry);
      }
    } on GitHubApiException catch (e) {
      if (mounted) {
        setState(() {
          if (e.statusCode == 422) {
            _errorMessage = '이미 존재하는 저장소 이름입니다.';
          } else {
            _errorMessage = 'GitHub API 오류가 발생했습니다. (${e.statusCode})';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = '네트워크 오류가 발생했습니다.');
      }
    } finally {
      client.dispose();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleConnectRepo() async {
    final input = _connectController.text.trim();
    final parts = input.split('/');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      setState(() => _errorMessage = 'owner/repo 형식으로 입력하세요.');
      return;
    }

    final owner = parts[0];
    final repo = parts[1];

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final client = _makeClient();
    try {
      final exists = await client.repoExists(owner: owner, repo: repo);
      if (!exists) {
        if (mounted) {
          setState(() => _errorMessage = '저장소를 찾을 수 없습니다.');
        }
        return;
      }
      final entry = RepoEntry(owner: owner, repo: repo);
      await widget.repoCache.add(entry);
      if (mounted) {
        await widget.onRepoSelected(entry);
      }
    } on GitHubApiException catch (e) {
      if (mounted) {
        setState(
            () => _errorMessage = 'GitHub API 오류가 발생했습니다. (${e.statusCode})');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = '네트워크 오류가 발생했습니다.');
      }
    } finally {
      client.dispose();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleRemoveCached(RepoEntry entry) async {
    await widget.repoCache.remove(entry.owner, entry.repo);
    await _loadCache();
  }

  Future<void> _handleSelectCached(RepoEntry entry) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.repoCache.add(entry);
      await widget.onRepoSelected(entry);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = '연결 중 오류가 발생했습니다.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.scaffold,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: _buildCard(c),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(AppColorsExtension c) {
    const cardWidth = 420.0;

    return Container(
      width: cardWidth,
      constraints: const BoxConstraints(maxHeight: 560),
      padding: const EdgeInsets.all(AppDimensions.spacingXxl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusLg),
        border: Border.all(color: c.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x20000000),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(c),
            const SizedBox(height: AppDimensions.spacingXl),
            if (_cachedRepos.isNotEmpty) ...[
              _buildCachedSection(c),
              const SizedBox(height: AppDimensions.spacingXl),
            ],
            if (_errorMessage != null) ...[
              _buildErrorMessage(c),
              const SizedBox(height: AppDimensions.spacingLg),
            ],
            _buildActionsSection(c),
            const SizedBox(height: AppDimensions.spacingXl),
            _buildLocalPathSection(c),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppColorsExtension c) {
    final avatarUrl = widget.avatarUrl.trim();

    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: c.surfaceLight,
          backgroundImage: avatarUrl.isEmpty ? null : NetworkImage(avatarUrl),
          child: avatarUrl.isEmpty
              ? Icon(Icons.person_outline_rounded, color: c.textMuted)
              : null,
        ),
        const SizedBox(height: AppDimensions.spacingMd),
        Text(
          widget.userLogin,
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingXs),
        Text(
          '저장소를 선택하세요',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCachedSection(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '최근 연결',
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        ..._cachedRepos.map((entry) => _buildCachedItem(c, entry)),
      ],
    );
  }

  Widget _buildCachedItem(AppColorsExtension c, RepoEntry entry) {
    final dateStr =
        '${entry.connectedAt.year}-${entry.connectedAt.month.toString().padLeft(2, '0')}-${entry.connectedAt.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingXs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
          onTap: _isLoading ? null : () => _handleSelectCached(entry),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingMd,
              vertical: AppDimensions.spacingSm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
              border: Border.all(color: c.borderSubtle),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 18, color: c.textSecondary),
                const SizedBox(width: AppDimensions.spacingSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.fullName,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(color: c.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    icon: Icon(Icons.close, color: c.textMuted),
                    onPressed:
                        _isLoading ? null : () => _handleRemoveCached(entry),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage(AppColorsExtension c) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: c.error),
          const SizedBox(width: AppDimensions.spacingSm),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: c.textPrimary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsSection(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildExpandableAction(
          c,
          label: '새 저장소 만들기',
          icon: Icons.add_rounded,
          isExpanded: _showCreateForm,
          onToggle: () => setState(() {
            _showCreateForm = !_showCreateForm;
            _showConnectForm = false;
            _errorMessage = null;
          }),
          child: _buildCreateForm(c),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        _buildExpandableAction(
          c,
          label: '기존 저장소 연결',
          icon: Icons.link_rounded,
          isExpanded: _showConnectForm,
          onToggle: () => setState(() {
            _showConnectForm = !_showConnectForm;
            _showCreateForm = false;
            _errorMessage = null;
          }),
          child: _buildConnectForm(c),
        ),
      ],
    );
  }

  Widget _buildExpandableAction(
    AppColorsExtension c, {
    required String label,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: AppDimensions.animFast,
      decoration: BoxDecoration(
        color: isExpanded ? c.surfaceLight : Colors.transparent,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
        border: Border.all(color: isExpanded ? c.border : c.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
              onTap: _isLoading ? null : onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingMd,
                  vertical: AppDimensions.spacingMd,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: c.accent),
                    const SizedBox(width: AppDimensions.spacingSm),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: c.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.spacingMd,
                0,
                AppDimensions.spacingMd,
                AppDimensions.spacingMd,
              ),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _buildCreateForm(AppColorsExtension c) {
    return Column(
      children: [
        TextField(
          controller: _createController,
          enabled: !_isLoading,
          style: TextStyle(color: c.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: '저장소 이름',
            hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingMd,
              vertical: AppDimensions.spacingSm,
            ),
            border: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSm),
              borderSide: BorderSide(color: c.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSm),
              borderSide: BorderSide(color: c.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSm),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
          onSubmitted: _isLoading ? null : (_) => _handleCreateRepo(),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        SizedBox(
          width: double.infinity,
          height: 36,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleCreateRepo,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.textOnAccent,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSm),
              ),
              textStyle: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: _isLoading && _showCreateForm
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.textOnAccent,
                    ),
                  )
                : const Text('만들기'),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectForm(AppColorsExtension c) {
    return Column(
      children: [
        TextField(
          controller: _connectController,
          enabled: !_isLoading,
          style: TextStyle(color: c.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'owner/repo',
            hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.spacingMd,
              vertical: AppDimensions.spacingSm,
            ),
            border: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSm),
              borderSide: BorderSide(color: c.borderSubtle),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSm),
              borderSide: BorderSide(color: c.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius:
                  BorderRadius.circular(AppDimensions.borderRadiusSm),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
          onSubmitted: _isLoading ? null : (_) => _handleConnectRepo(),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        SizedBox(
          width: double.infinity,
          height: 36,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleConnectRepo,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.textOnAccent,
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSm),
              ),
              textStyle: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: _isLoading && _showConnectForm
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.textOnAccent,
                    ),
                  )
                : const Text('연결'),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalPathSection(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '로컬 노트 저장 경로',
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingSm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingMd,
            vertical: AppDimensions.spacingSm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
            border: Border.all(color: c.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 16, color: c.textSecondary),
              const SizedBox(width: AppDimensions.spacingSm),
              Expanded(
                child: Text(
                  _localNotePath,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppDimensions.spacingSm),
              InkWell(
                onTap: _isLoading ? null : _pickLocalPath,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSm),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.surfaceLight,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadiusSm),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    '변경',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
