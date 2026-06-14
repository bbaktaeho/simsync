import 'package:flutter/material.dart';

import '../storage/github/github_api_client.dart';
import '../storage/github/repo_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

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
  }

  Future<void> _loadCache() async {
    final entries = await widget.repoCache.load();
    if (mounted) {
      setState(() => _cachedRepos = entries);
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
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '네트워크 오류: $e');
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
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '네트워크 오류: $e');
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
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: _buildCard(c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.spacingXxl),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius:
                BorderRadius.circular(AppDimensions.borderRadiusLg),
            border: Border.all(color: c.border),
            boxShadow: AppShadows.card,
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
              ],
            ),
          ),
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
          style: AppTextStyles.sectionHeading.copyWith(
            color: c.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingXs),
        Text(
          '저장소를 선택하세요',
          style: AppTextStyles.caption.copyWith(color: c.textSecondary),
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
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
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
                        style: AppTextStyles.captionMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: AppTextStyles.micro.copyWith(color: c.textMuted),
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
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: c.textPrimary,
                  ),
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
                        style: AppTextStyles.captionMedium.copyWith(
                          color: c.textPrimary,
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
          style: AppTextStyles.caption.copyWith(color: c.textPrimary),
          decoration: InputDecoration(
            hintText: '저장소 이름',
            hintStyle: AppTextStyles.caption.copyWith(color: c.textMuted),
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
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleCreateRepo,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.textOnAccent,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSm),
              ),
              textStyle: AppTextStyles.captionSemibold,
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
          style: AppTextStyles.caption.copyWith(color: c.textPrimary),
          decoration: InputDecoration(
            hintText: 'owner/repo',
            hintStyle: AppTextStyles.caption.copyWith(color: c.textMuted),
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
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleConnectRepo,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: c.textOnAccent,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadiusSm),
              ),
              textStyle: AppTextStyles.captionSemibold,
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
}
