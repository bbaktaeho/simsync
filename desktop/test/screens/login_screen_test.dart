import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsync/auth/auth_provider.dart';
import 'package:simsync/auth/github_oauth_provider.dart';
import 'package:simsync/screens/login_screen.dart';
import 'package:simsync/theme/app_theme.dart';

DeviceAuthorization _authorization() {
  return DeviceAuthorization(
    userCode: 'ABCD-1234',
    verificationUri: Uri.parse('https://github.com/login/device'),
    expiresAt: DateTime.now().add(const Duration(minutes: 15)),
  );
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required GitHubSignIn onGitHubLogin,
  VoidCallback? onCancelLogin,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildLightTheme(),
    home: LoginScreen(
      onGitHubLogin: onGitHubLogin,
      onCancelLogin: onCancelLogin ?? () {},
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'login shows the device-code dialog, cancel aborts, dialog closes',
      (tester) async {
    var cancelCalls = 0;
    DeviceAuthorizationPrompt? capturedPrompt;
    final signIn = Completer<void>();

    await _pumpLogin(
      tester,
      onGitHubLogin: ({onAuthorizationPrompt}) {
        capturedPrompt = onAuthorizationPrompt;
        return signIn.future;
      },
      onCancelLogin: () => cancelCalls++,
    );

    await tester.tap(find.text('Continue with GitHub'));
    await tester.pump();
    expect(capturedPrompt, isNotNull);

    // Provider issued the code: the dialog must show it. (Bounded pumps: the
    // dialog's indeterminate spinner means pumpAndSettle would never settle.)
    capturedPrompt!(_authorization());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ABCD-1234'), findsOneWidget);
    expect(find.text('Enter this code on GitHub'), findsOneWidget);

    // Cancel wires through to the abort callback.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelCalls, 1);

    // The aborted sign-in future closes the dialog with no error banner
    // (cancellation is a user action, not a failure).
    signIn.completeError(const AuthCancelledException('cancelled'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ABCD-1234'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('successful sign-in closes the dialog', (tester) async {
    DeviceAuthorizationPrompt? capturedPrompt;
    final signIn = Completer<void>();

    await _pumpLogin(
      tester,
      onGitHubLogin: ({onAuthorizationPrompt}) {
        capturedPrompt = onAuthorizationPrompt;
        return signIn.future;
      },
    );

    await tester.tap(find.text('Continue with GitHub'));
    await tester.pump();
    capturedPrompt!(_authorization());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ABCD-1234'), findsOneWidget);

    signIn.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ABCD-1234'), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('auth failures surface in the error banner', (tester) async {
    await _pumpLogin(
      tester,
      onGitHubLogin: ({onAuthorizationPrompt}) async {
        throw const AuthException('The GitHub device code expired.');
      },
    );

    await tester.tap(find.text('Continue with GitHub'));
    await tester.pumpAndSettle();

    expect(find.text('The GitHub device code expired.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });
}
