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
import '../widgets/app_logo_mark.dart';

/// Runs the device-flow sign-in; [onAuthorizationPrompt] fires with the code
/// the user must enter on GitHub while approval is polled.
typedef GitHubSignIn = Future<void> Function({
  DeviceAuthorizationPrompt? onAuthorizationPrompt,
});

class LoginScreen extends StatefulWidget {
  final GitHubSignIn onGitHubLogin;

  /// Aborts the in-progress sign-in (wired to the code dialog's cancel).
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

  /// Whether the device-code dialog is currently shown, so completion of the
  /// sign-in future (success, error, or cancel) can dismiss it.
  bool _codeDialogVisible = false;

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      setState(() => _errorMessage = null);
      await widget.onGitHubLogin(
        onAuthorizationPrompt: _showDeviceCodeDialog,
      );
    } on AuthCancelledException {
      // User-initiated (dialog cancel / denied on GitHub): no error banner.
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'GitHub 로그인 중 오류가 발생했습니다.');
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
      // The only way out is the cancel button, which aborts the sign-in —
      // otherwise polling would keep running behind a dismissed dialog.
      barrierDismissible: false,
      builder: (context) => _DeviceCodeDialog(
        authorization: authorization,
        onCancel: () {
          widget.onCancelLogin();
          // The sign-in future completes with AuthCancelledException, and
          // _handleLogin's finally dismisses the dialog.
        },
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
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: _buildLoginCard(c),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard(AppColorsExtension c) {
    const cardWidth = 380.0;

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(AppDimensions.spacingXxl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusLg),
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
    );
  }

  Widget _buildLogo(AppColorsExtension c) {
    return Column(
      children: [
        const AppLogoMark(size: 48),
        const SizedBox(height: AppDimensions.spacingLg),
        Text(
          'SimSync',
          style: AppTextStyles.pageTitle.copyWith(color: c.textPrimary, letterSpacing: -0.5),
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
      'Use your GitHub account to access SimSync on this desktop device.',
      textAlign: TextAlign.center,
      style: AppTextStyles.caption.copyWith(color: c.textSecondary, height: 1.5),
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
          Icon(Icons.error_outline_rounded, size: 18, color: c.accent),
          const SizedBox(width: AppDimensions.spacingSm),
          Expanded(
            child: Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(color: c.textPrimary),
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

/// Device-flow verification dialog: shows the user code, copies it to the
/// clipboard, and opens github.com/login/device — the user pastes + approves
/// there while the app polls in the background.
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
    // Do the two chores for the user up front: code on the clipboard, GitHub
    // verification page in the browser. The dialog stays as the reference.
    _copyCode();
    _openGitHub();
  }

  void _copyCode() {
    // Fire-and-forget: a clipboard failure must not break the sign-in dialog
    // (the code is still displayed and selectable).
    unawaited(
      Clipboard.setData(ClipboardData(text: widget.authorization.userCode))
          .catchError((_) {}),
    );
    if (mounted) setState(() => _copied = true);
  }

  void _openGitHub() {
    // Fire-and-forget: if the browser can't be opened, the user can still
    // visit the displayed URL manually.
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusLg),
        side: BorderSide(color: c.border),
      ),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(AppDimensions.spacingXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter this code on GitHub',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontWeight: FontWeight.w600, color: c.textPrimary),
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppDimensions.spacingMd,
              ),
              decoration: BoxDecoration(
                color: c.surfaceLight,
                borderRadius:
                    BorderRadius.circular(AppDimensions.borderRadius),
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
                    label: Text(_copied ? 'Copied' : 'Copy code'),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openGitHub,
                    icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                    label: const Text('Open GitHub'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingLg),
            Text(
              'The code was copied and GitHub was opened in your browser. '
              'Approve the request there to finish signing in. '
              'This code expires in about $minutesLeft minutes.',
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
                    'Waiting for authorization…',
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
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
