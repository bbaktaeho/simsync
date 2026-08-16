import 'package:flutter_test/flutter_test.dart';
import 'package:simsync_mobile/auth/session_policy.dart';

void main() {
  test('calculateExpiry adds max age to issue time', () {
    final policy = SessionPolicy(maxAge: const Duration(hours: 24));
    final issuedAt = DateTime.utc(2026, 3, 10, 12);

    final expiresAt = policy.calculateExpiry(issuedAt);

    expect(expiresAt, DateTime.utc(2026, 3, 11, 12));
  });

  test('isExpired returns true when current time is on or past expiry', () {
    final policy = SessionPolicy(maxAge: const Duration(hours: 24));
    final expiresAt = DateTime.utc(2026, 3, 11, 12);

    expect(
      policy.isExpired(expiresAt: expiresAt, now: DateTime.utc(2026, 3, 11, 11)),
      isFalse,
    );
    expect(
      policy.isExpired(expiresAt: expiresAt, now: DateTime.utc(2026, 3, 11, 12)),
      isTrue,
    );
    expect(
      policy.isExpired(expiresAt: expiresAt, now: DateTime.utc(2026, 3, 11, 13)),
      isTrue,
    );
  });
}
