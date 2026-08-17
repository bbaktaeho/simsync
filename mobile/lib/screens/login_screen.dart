import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/auth_provider.dart';
import '../auth/github_oauth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text_styles.dart';

/// device flow 로그인. [onAuthorizationPrompt]로 사용자가 GitHub에 입력할
/// 코드를 받아 화면에 띄우고, 승인될 때까지 폴링한다.
typedef GitHubSignIn = Future<void> Function({
  DeviceAuthorizationPrompt? onAuthorizationPrompt,
});

class LoginScreen extends StatefulWidget {
  final GitHubSignIn onGitHubLogin;

  /// 진행 중인 로그인을 중단한다 (코드 다이얼로그의 취소 버튼과 연결).
  final VoidCallback onCancelLogin;

  const LoginScreen({
    super.key,
    required this.onGitHubLogin,
    required this.onCancelLogin,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;
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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  /// 코드 다이얼로그가 떠 있는지. 로그인 future가 끝나면(성공/실패/취소)
  /// 이 값을 보고 닫는다.
  bool _codeDialogVisible = false;

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      setState(() => _errorMessage = null);
      await widget.onGitHubLogin(onAuthorizationPrompt: _showDeviceCodeDialog);
    } on AuthCancelledException {
      // 사용자가 취소했거나 GitHub에서 거부한 경우 — 에러 배너를 띄우지 않는다.
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'GitHub 로그인 중 오류: $e');
      }
    } finally {
      _dismissDeviceCodeDialog();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showDeviceCodeDialog(DeviceAuthorization authorization) {
    if (!mounted) return;
    _codeDialogVisible = true;
    showDialog<void>(
      context: context,
      // 유일한 출구는 취소 버튼이다. 그냥 닫히면 폴링만 남는다.
      barrierDismissible: false,
      builder: (context) => _DeviceCodeDialog(
        authorization: authorization,
        onCancel: widget.onCancelLogin,
      ),
    ).whenComplete(() => _codeDialogVisible = false);
  }

  void _dismissDeviceCodeDialog() {
    if (!_codeDialogVisible || !mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
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
              child: _buildLoginCard(c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard(AppColorsExtension c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          padding: const EdgeInsets.all(AppDimensions.spacingXxl),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius:
                BorderRadius.circular(AppDimensions.radiusComfortable),
            border: Border.all(color: c.border),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLogo(c),
              const SizedBox(height: AppDimensions.spacingXxl),
              _buildDescription(c),
              const SizedBox(height: AppDimensions.spacingXl),
              if (_errorMessage != null) ...[
                _buildErrorMessage(c),
                const SizedBox(height: AppDimensions.spacingLg),
              ],
              _buildLoginButton(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(AppColorsExtension c) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c.accentMuted,
            borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
          ),
          child: Icon(
            Icons.edit_note_rounded,
            color: c.accent,
            size: 28,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingLg),
        Text(
          'SimSync',
          style: AppTextStyles.pageTitle.copyWith(
            color: c.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingXs),
        Text(
          'Sign in to continue',
          style: AppTextStyles.caption.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }

  Widget _buildDescription(AppColorsExtension c) {
    return Text(
      'Use your GitHub account to access SimSync on this mobile device.',
      textAlign: TextAlign.center,
      style: AppTextStyles.caption.copyWith(
        color: c.textSecondary,
        height: 1.5,
      ),
    );
  }

  Widget _buildErrorMessage(AppColorsExtension c) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingMd),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusStandard),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: c.accent),
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

  Widget _buildLoginButton(AppColorsExtension c) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        child: _isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.textOnAccent,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.code_rounded, color: c.textOnAccent, size: 18),
                    const SizedBox(width: AppDimensions.spacingSm),
                    const Text('Continue with GitHub'),
                  ],
                ),
              ),
      ),
    );
  }
}

/// device flow 코드 다이얼로그. 코드를 클립보드에 넣고 GitHub 인증 페이지를
/// 열어 준다 — 사용자는 그쪽에서 붙여넣고 승인하고, 앱은 뒤에서 폴링한다.
class _DeviceCodeDialog extends StatefulWidget {
  const _DeviceCodeDialog({
    required this.authorization,
    required this.onCancel,
  });

  final DeviceAuthorization authorization;
  final VoidCallback onCancel;

  @override
  State<_DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<_DeviceCodeDialog> {
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _copyCode();
    _openGitHub();
  }

  void _copyCode() {
    // 실패해도 다이얼로그는 살아 있어야 한다 (코드는 화면에 보인다).
    unawaited(
      Clipboard.setData(ClipboardData(text: widget.authorization.userCode))
          .catchError((_) {}),
    );
    if (mounted) setState(() => _copied = true);
  }

  void _openGitHub() {
    unawaited(
      launchUrl(
        widget.authorization.verificationUri,
        mode: LaunchMode.externalApplication,
      ).catchError((_) => false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final minutesLeft = widget.authorization.expiresAt
        .difference(DateTime.now())
        .inMinutes
        .clamp(1, 60);

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(AppDimensions.spacingLg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusComfortable),
        side: BorderSide(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'GitHub에 이 코드를 입력하세요',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.spacingMd,
              ),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusStandard),
                border: Border.all(color: c.border),
              ),
              child: SelectableText(
                widget.authorization.userCode,
                textAlign: TextAlign.center,
                style: AppTextStyles.pageTitle.copyWith(
                  color: c.textPrimary,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: Text(
                      _copied ? '복사됨' : '코드 복사',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openGitHub,
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: const Text(
                      'GitHub 열기',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Text(
              '코드를 복사하고 브라우저에서 GitHub를 열었습니다. '
              '그곳에서 승인하면 로그인이 끝납니다. '
              '이 코드는 약 $minutesLeft분 뒤 만료됩니다.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption
                  .copyWith(color: c.textSecondary, height: 1.5),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                Flexible(
                  child: Text(
                    '승인을 기다리는 중…',
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppTextStyles.caption.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingMd),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    );
  }
}
