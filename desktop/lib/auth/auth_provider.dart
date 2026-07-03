import 'auth_models.dart';

enum SessionValidationResult {
  valid,
  invalid,
  unknown,
}

/// The device-flow verification prompt: what the user must do on GitHub to
/// approve this sign-in. Surfaced to the UI so it can display [userCode] and
/// open [verificationUri].
class DeviceAuthorization {
  const DeviceAuthorization({
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
  });

  /// Short code (e.g. `ABCD-1234`) the user enters on GitHub.
  final String userCode;

  /// Where the user enters the code (`https://github.com/login/device`).
  final Uri verificationUri;

  /// When the code stops being accepted; the sign-in fails after this.
  final DateTime expiresAt;
}

/// Called once per [AuthProvider.signIn] as soon as the verification code is
/// issued, before polling for the user's approval begins.
typedef DeviceAuthorizationPrompt = void Function(
  DeviceAuthorization authorization,
);

abstract class AuthProvider {
  /// Runs the provider's sign-in flow and resolves with the granted token.
  ///
  /// Device-flow providers invoke [onAuthorizationPrompt] with the code the
  /// user must enter, then poll until approval, denial, expiry, or
  /// [cancelSignIn].
  Future<AuthGrant> signIn({DeviceAuthorizationPrompt? onAuthorizationPrompt});

  /// Aborts an in-progress [signIn] (e.g. the user dismissed the code dialog).
  /// No-op when nothing is in progress.
  void cancelSignIn();

  Future<SessionValidationResult> validateAccessToken(String accessToken);
}
