import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_user_admin_repository.dart';

const _activeEditorSession = AuthSession(
  uid: 'u1',
  email: 'editor@example.com',
  displayName: 'Edie Editor',
  role: UserRole.editor,
  status: AccountStatus.active,
  mustChangePassword: false,
);

const _activeSuperAdminSession = AuthSession(
  uid: 'u2',
  email: 'admin@example.com',
  displayName: 'Sam SuperAdmin',
  role: UserRole.superAdmin,
  status: AccountStatus.active,
  mustChangePassword: false,
);

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

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: IdentityScope(
          controller: controller,
          authRepository: authRepository,
          userAdminRepository: userAdminRepository,
          child: const AuthGate(),
        ),
      ),
    );
  }

  testWidgets('AuthStateUnknown shows a loading indicator', (tester) async {
    await pumpGate(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('AuthStateSignedOut shows the login screen', (tester) async {
    await pumpGate(tester);
    authRepository.emit(const AuthStateSignedOut());
    await tester.pump();

    expect(find.text('2D Montessori Admin'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets(
    'AuthStateError shows the error screen with the failure message and a retry/sign-out affordance',
    (tester) async {
      await pumpGate(tester);
      authRepository.emit(const AuthStateError(NetworkFailure()));
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('Network error'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsOneWidget);
    },
  );

  testWidgets(
    'AuthStateUnprovisioned shows the unprovisioned-account screen with the email',
    (tester) async {
      await pumpGate(tester);
      authRepository.emit(
        const AuthStateUnprovisioned(uid: 'u9', email: 'ghost@example.com'),
      );
      await tester.pump();

      expect(find.text('Account not set up'), findsOneWidget);
      expect(find.textContaining('ghost@example.com'), findsOneWidget);
    },
  );

  testWidgets('AuthStateSuspended shows the suspended-account screen', (
    tester,
  ) async {
    await pumpGate(tester);
    authRepository.emit(AuthStateSuspended(_activeEditorSession));
    await tester.pump();

    expect(find.text('Account suspended'), findsOneWidget);
  });

  testWidgets(
    'AuthStateSignedIn with mustChangePassword shows the forced password-change screen, not the shell',
    (tester) async {
      await pumpGate(tester);
      authRepository.emit(
        AuthStateSignedIn(
          const AuthSession(
            uid: 'u1',
            email: 'editor@example.com',
            displayName: 'Edie',
            role: UserRole.editor,
            status: AccountStatus.active,
            mustChangePassword: true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Set a new password'), findsOneWidget);
      expect(find.text('User management'), findsNothing);
    },
  );

  testWidgets(
    'AuthStateSignedIn (provisioned, active, password set) shows the admin shell',
    (tester) async {
      await pumpGate(tester);
      authRepository.emit(AuthStateSignedIn(_activeEditorSession));
      await tester.pump();

      expect(
        find.textContaining('Signed in as editor@example.com'),
        findsOneWidget,
      );
    },
  );

  group('role-gated navigation (route protection)', () {
    testWidgets('Editor does not see the Users nav entry at all', (
      tester,
    ) async {
      await pumpGate(tester);
      authRepository.emit(AuthStateSignedIn(_activeEditorSession));
      await tester.pump();

      final scaffoldState = tester.state<ScaffoldState>(
        find.byType(Scaffold).first,
      );
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Users'), findsNothing);
    });

    testWidgets(
      'Super Admin sees the Users nav entry and can open User Management (not Access Denied)',
      (tester) async {
        await pumpGate(tester);
        authRepository.emit(AuthStateSignedIn(_activeSuperAdminSession));
        await tester.pump();

        final scaffoldState = tester.state<ScaffoldState>(
          find.byType(Scaffold).first,
        );
        scaffoldState.openDrawer();
        await tester.pumpAndSettle();

        expect(find.text('Users'), findsOneWidget);
        await tester.tap(find.text('Users'));
        // Deliberately not pumpAndSettle(): UserManagementScreen shows a
        // CircularProgressIndicator (indeterminate animation) until its
        // observeUsers() stream delivers a first event, which would time
        // pumpAndSettle out. Pump explicitly instead.
        await tester.pump();
        userAdminRepository.emitUsers(const Result.ok([]));
        await tester.pump();
        await tester.pump();

        expect(find.text('Access denied'), findsNothing);
        expect(find.widgetWithText(AppBar, 'User management'), findsOneWidget);
      },
    );
  });
}
