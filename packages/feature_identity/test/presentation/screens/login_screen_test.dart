import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:feature_identity/src/presentation/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_user_admin_repository.dart';

void main() {
  late FakeAuthRepository authRepository;
  late FakeUserAdminRepository userAdminRepository;
  late AuthController controller;

  setUp(() {
    authRepository = FakeAuthRepository();
    userAdminRepository = FakeUserAdminRepository();
    controller = AuthController(authRepository);
  });

  tearDown(() async {
    controller.dispose();
    await authRepository.dispose();
    await userAdminRepository.dispose();
  });

  Future<void> pumpLoginScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityScope(
          controller: controller,
          authRepository: authRepository,
          userAdminRepository: userAdminRepository,
          child: const LoginScreen(),
        ),
      ),
    );
  }

  testWidgets(
    'shows field-level validation errors and does not call the repository',
    (tester) async {
      await pumpLoginScreen(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(authRepository.lastSignIn, isNull);
    },
  );

  testWidgets(
    'shows the failure message from the repository on a rejected sign-in',
    (tester) async {
      authRepository.nextSignInResult = const Result.failure(
        InvalidCredentialsFailure(),
      );
      await pumpLoginScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'a@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrong-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();

      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(authRepository.lastSignIn, (
        email: 'a@example.com',
        password: 'wrong-password',
      ));
    },
  );

  testWidgets('calls the repository with trimmed email on valid submission', (
    tester,
  ) async {
    await pumpLoginScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      '  a@example.com  ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(authRepository.lastSignIn, (
      email: 'a@example.com',
      password: 'correct-password',
    ));
    expect(find.textContaining('Incorrect'), findsNothing);
  });
}
