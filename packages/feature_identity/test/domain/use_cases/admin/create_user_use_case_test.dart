import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_user_admin_repository.dart';

void main() {
  late FakeUserAdminRepository repository;
  late CreateUserUseCase useCase;

  setUp(() {
    repository = FakeUserAdminRepository();
    useCase = CreateUserUseCase(repository);
  });

  tearDown(() => repository.dispose());

  for (final role in [UserRole.editor, UserRole.publisher]) {
    test(
      'rejects $role acting role without calling the repository (SRS §3: only Super Admin manages users)',
      () async {
        final result = await useCase(
          actingRole: role,
          email: 'new@example.com',
          displayName: 'New',
          role: UserRole.editor,
        );
        expect(result.isFailure, isTrue);
        expect(result.fold((_) => null, (f) => f), isA<PermissionFailure>());
        expect(repository.lastCreateUser, isNull);
      },
    );
  }

  test('rejects an invalid email for a Super Admin caller', () async {
    final result = await useCase(
      actingRole: UserRole.superAdmin,
      email: 'not-an-email',
      displayName: 'New',
      role: UserRole.editor,
    );
    expect(result.isFailure, isTrue);
    expect(result.fold((_) => null, (f) => f), isA<ValidationFailure>());
    expect(repository.lastCreateUser, isNull);
  });

  test('rejects an empty display name for a Super Admin caller', () async {
    final result = await useCase(
      actingRole: UserRole.superAdmin,
      email: 'a@example.com',
      displayName: '  ',
      role: UserRole.editor,
    );
    expect(result.isFailure, isTrue);
    expect(repository.lastCreateUser, isNull);
  });

  test('forwards a valid request from a Super Admin caller', () async {
    repository.nextCreateUserResult = const Result.ok(
      CreateUserResult(uid: 'u1', temporaryPassword: 'Abcd1234'),
    );
    final result = await useCase(
      actingRole: UserRole.superAdmin,
      email: '  New@Example.com  ',
      displayName: '  New User  ',
      role: UserRole.publisher,
    );
    expect(result.isOk, isTrue);
    expect(repository.lastCreateUser, (
      email: 'New@Example.com',
      displayName: 'New User',
      role: UserRole.publisher,
    ));
  });
}
