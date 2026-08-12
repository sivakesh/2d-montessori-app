import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_user_admin_repository.dart';

void main() {
  late FakeUserAdminRepository repository;
  late ResetUserPasswordUseCase useCase;

  setUp(() {
    repository = FakeUserAdminRepository();
    useCase = ResetUserPasswordUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test('rejects a non-Super-Admin acting role', () async {
    final result = await useCase(actingRole: UserRole.publisher, uid: 'u1');
    expect(result.fold((_) => null, (f) => f), isA<PermissionFailure>());
    expect(repository.lastResetUserPasswordUid, isNull);
  });

  test('forwards a valid request and returns the temporary password', () async {
    repository.nextResetUserPasswordResult = const Result.ok(
      ResetPasswordResult(temporaryPassword: 'Abcd1234'),
    );
    final result = await useCase(actingRole: UserRole.superAdmin, uid: 'u1');
    expect(result.isOk, isTrue);
    expect(result.fold((s) => s.temporaryPassword, (_) => null), 'Abcd1234');
    expect(repository.lastResetUserPasswordUid, 'u1');
  });
}
