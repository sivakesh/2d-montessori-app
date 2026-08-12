import 'package:admin_web/main.dart';
import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  Stream<AuthState> observeAuthState() =>
      Stream.value(const AuthStateSignedOut());

  @override
  Future<Result<void>> changeOwnPassword(String newPassword) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> completeFirstLogin() async => const Result.ok(null);

  @override
  Future<Result<void>> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> refreshOwnClaims() async => const Result.ok(null);

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async =>
      const Result.ok(null);

  @override
  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async => const Result.ok(null);

  @override
  Future<Result<void>> signOut() async => const Result.ok(null);
}

class _FakeUserAdminRepository implements UserAdminRepository {
  @override
  Future<Result<CreateUserResult>> createUser({
    required String email,
    required String displayName,
    required UserRole role,
  }) async => const Result.failure(ValidationFailure('not used in this test'));

  @override
  Stream<Result<List<UserAccount>>> observeUsers() =>
      Stream.value(const Result.ok([]));

  @override
  Future<Result<ResetPasswordResult>> resetUserPassword(String uid) async =>
      const Result.failure(ValidationFailure('not used in this test'));

  @override
  Future<Result<void>> setUserRole({
    required String uid,
    required UserRole role,
  }) async => const Result.failure(ValidationFailure('not used in this test'));

  @override
  Future<Result<void>> setUserStatus({
    required String uid,
    required AccountStatus status,
  }) async => const Result.failure(ValidationFailure('not used in this test'));
}

void main() {
  testWidgets('AdminWebApp shows the sign-in screen when signed out', (
    WidgetTester tester,
  ) async {
    // No Firebase bootstrap here — main.dart's Firebase.initializeApp()
    // call requires platform channels unavailable under `flutter test`.
    // This pumps AdminWebApp directly with fake repositories instead, the
    // same pattern as apps/public_web/test/widget_test.dart.
    final authRepository = _FakeAuthRepository();
    final controller = AuthController(authRepository);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AdminWebApp(
        authController: controller,
        authRepository: authRepository,
        userAdminRepository: _FakeUserAdminRepository(),
      ),
    );
    await tester.pump();

    expect(find.text('2D Montessori Admin'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
