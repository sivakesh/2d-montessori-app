import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late CompleteForcedPasswordChangeUseCase useCase;

  setUp(() {
    repository = FakeAuthRepository();
    useCase = CompleteForcedPasswordChangeUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test(
    'rejects a weak password without calling the repository at all',
    () async {
      final result = await useCase('short');
      expect(result.fold((_) => null, (f) => f), isA<WeakPasswordFailure>());
      expect(repository.lastChangeOwnPassword, isNull);
      expect(repository.completeFirstLoginCallCount, 0);
    },
  );

  test(
    'does not call completeFirstLogin when changeOwnPassword fails',
    () async {
      repository.nextChangeOwnPasswordResult = const Result.failure(
        RequiresRecentLoginFailure(),
      );
      final result = await useCase('Abcd1234');
      expect(
        result.fold((_) => null, (f) => f),
        isA<RequiresRecentLoginFailure>(),
      );
      expect(repository.lastChangeOwnPassword, 'Abcd1234');
      expect(repository.completeFirstLoginCallCount, 0);
    },
  );

  test('calls completeFirstLogin after a successful password change', () async {
    final result = await useCase('Abcd1234');
    expect(result.isOk, isTrue);
    expect(repository.lastChangeOwnPassword, 'Abcd1234');
    expect(repository.completeFirstLoginCallCount, 1);
  });

  test(
    'surfaces a completeFirstLogin failure even though the password was already changed',
    () async {
      repository.nextCompleteFirstLoginResult = const Result.failure(
        NetworkFailure(),
      );
      final result = await useCase('Abcd1234');
      expect(result.fold((_) => null, (f) => f), isA<NetworkFailure>());
      expect(
        repository.lastChangeOwnPassword,
        'Abcd1234',
      ); // password change did happen
    },
  );
}
