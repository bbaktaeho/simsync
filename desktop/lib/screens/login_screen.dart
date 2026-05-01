import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/github_oauth_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_shadows.dart';

class LoginScreen extends StatefulWidget {
  final Future<void> Function() onGitHubLogin;

  const LoginScreen({super.key, required this.onGitHubLogin});

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

  Future<void> _handleLogin() async {
    setState(() => _isLoading = true);

    try {
      setState(() => _errorMessage = null);
      await widget.onGitHubLogin();
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'GitHub 로그인 중 오류가 발생했습니다.');
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
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: c.accentMuted,
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
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
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: AppDimensions.spacingXs),
        Text(
          'Sign in to continue',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildDescription(AppColorsExtension c) {
    return Text(
      'Use your GitHub account to access SimSync on this desktop device.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: c.textSecondary,
        fontSize: 13,
        height: 1.5,
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
          Icon(Icons.error_outline_rounded, size: 18, color: c.accent),
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
