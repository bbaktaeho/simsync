import 'auth_models.dart';

abstract class AuthProvider {
  Future<AuthGrant> signIn();
}
