import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late ConfirmPasswordResetUseCase useCase;

  setUp(() {
    repository = FakeAuthRepository();
    useCase = ConfirmPasswordResetUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test('rejects an empty oobCode without calling the repository', () async {
    final result = await useCase(oobCode: '', newPassword: 'Abcd1234');
    expect(result.fold((_) => null, (f) => f), isA<InvalidResetCodeFailure>());
    expect(repository.lastConfirmPasswordReset, isNull);
  });

  test(
    'rejects a password that fails policy without calling the repository',
    () async {
      final result = await useCase(oobCode: 'code123', newPassword: 'short');
      expect(result.fold((_) => null, (f) => f), isA<WeakPasswordFailure>());
      expect(repository.lastConfirmPasswordReset, isNull);
    },
  );

  test('forwards a valid request', () async {
    final result = await useCase(oobCode: 'code123', newPassword: 'Abcd1234');
    expect(result.isOk, isTrue);
    expect(repository.lastConfirmPasswordReset, (
      oobCode: 'code123',
      newPassword: 'Abcd1234',
    ));
  });
}
