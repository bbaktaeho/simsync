class SessionPolicy {
  const SessionPolicy({required this.maxAge});

  final Duration maxAge;

  DateTime calculateExpiry(DateTime issuedAt) {
    return issuedAt.add(maxAge);
  }

  bool isExpired({
    required DateTime expiresAt,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    return !expiresAt.isAfter(current);
  }
}
