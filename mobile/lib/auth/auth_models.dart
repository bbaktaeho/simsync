class AuthUser {
  const AuthUser({
    required this.id,
    required this.login,
    required this.name,
    required this.avatarUrl,
  });

  final String id;
  final String login;
  final String? name;
  final String avatarUrl;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      login: json['login'] as String,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'login': login,
      'name': name,
      'avatarUrl': avatarUrl,
    };
  }
}

class AuthGrant {
  const AuthGrant({
    required this.provider,
    required this.accessToken,
    required this.tokenType,
    required this.scope,
    required this.user,
  });

  final String provider;
  final String accessToken;
  final String tokenType;
  final String scope;
  final AuthUser user;

  factory AuthGrant.fromJson(Map<String, dynamic> json) {
    return AuthGrant(
      provider: json['provider'] as String,
      accessToken: json['accessToken'] as String,
      tokenType: json['tokenType'] as String,
      scope: json['scope'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'accessToken': accessToken,
      'tokenType': tokenType,
      'scope': scope,
      'user': user.toJson(),
    };
  }
}

class AuthSession {
  const AuthSession({
    required this.provider,
    required this.accessToken,
    required this.tokenType,
    required this.scope,
    required this.issuedAt,
    required this.expiresAt,
    required this.user,
  });

  final String provider;
  final String accessToken;
  final String tokenType;
  final String scope;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      provider: json['provider'] as String,
      accessToken: json['accessToken'] as String,
      tokenType: json['tokenType'] as String,
      scope: json['scope'] as String,
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'accessToken': accessToken,
      'tokenType': tokenType,
      'scope': scope,
      'issuedAt': issuedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'user': user.toJson(),
    };
  }
}
