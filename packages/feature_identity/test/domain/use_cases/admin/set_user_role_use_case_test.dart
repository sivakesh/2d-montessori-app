import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_user_admin_repository.dart';

void main() {
  late FakeUserAdminRepository repository;
  late SetUserRoleUseCase useCase;

  setUp(() {
    repository = FakeUserAdminRepository();
    useCase = SetUserRoleUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test('rejects a non-Super-Admin acting role', () async {
    final result = await useCase(
      actingRole: UserRole.publisher,
      uid: 'u1',
      role: UserRole.editor,
    );
    expect(result.fold((_) => null, (f) => f), isA<PermissionFailure>());
    expect(repository.lastSetUserRole, isNull);
  });

  test('rejects an empty target uid', () async {
    final result = await useCase(
      actingRole: UserRole.superAdmin,
      uid: '',
      role: UserRole.editor,
    );
    expect(result.fold((_) => null, (f) => f), isA<ValidationFailure>());
    expect(repository.lastSetUserRole, isNull);
  });

  test('forwards a valid request', () async {
    final result = await useCase(
      actingRole: UserRole.superAdmin,
      uid: 'u1',
      role: UserRole.publisher,
    );
    expect(result.isOk, isTrue);
    expect(repository.lastSetUserRole, (uid: 'u1', role: UserRole.publisher));
  });

  test(
    'propagates a LastSuperAdminFailure from the repository unchanged',
    () async {
      repository.nextSetUserRoleResult = const Result.failure(
        LastSuperAdminFailure(),
      );
      final result = await useCase(
        actingRole: UserRole.superAdmin,
        uid: 'u1',
        role: UserRole.editor,
      );
      expect(result.fold((_) => null, (f) => f), isA<LastSuperAdminFailure>());
    },
  );
}
