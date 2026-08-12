import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_user_admin_repository.dart';

void main() {
  late FakeUserAdminRepository repository;
  late SetUserStatusUseCase useCase;

  setUp(() {
    repository = FakeUserAdminRepository();
    useCase = SetUserStatusUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test('rejects a non-Super-Admin acting role', () async {
    final result = await useCase(
      actingRole: UserRole.editor,
      uid: 'u1',
      status: AccountStatus.suspended,
    );
    expect(result.fold((_) => null, (f) => f), isA<PermissionFailure>());
    expect(repository.lastSetUserStatus, isNull);
  });

  test('forwards a valid suspend request', () async {
    final result = await useCase(
      actingRole: UserRole.superAdmin,
      uid: 'u1',
      status: AccountStatus.suspended,
    );
    expect(result.isOk, isTrue);
    expect(repository.lastSetUserStatus, (
      uid: 'u1',
      status: AccountStatus.suspended,
    ));
  });

  test(
    'propagates a LastSuperAdminFailure from the repository unchanged',
    () async {
      repository.nextSetUserStatusResult = const Result.failure(
        LastSuperAdminFailure(),
      );
      final result = await useCase(
        actingRole: UserRole.superAdmin,
        uid: 'sole-admin',
        status: AccountStatus.suspended,
      );
      expect(result.fold((_) => null, (f) => f), isA<LastSuperAdminFailure>());
    },
  );
}
