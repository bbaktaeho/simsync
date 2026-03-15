import 'auth_models.dart';

enum SessionValidationResult {
  valid,
  invalid,
  unknown,
}

abstract class AuthProvider {
  Future<AuthGrant> signIn();
  Future<SessionValidationResult> validateAccessToken(String accessToken);
}
