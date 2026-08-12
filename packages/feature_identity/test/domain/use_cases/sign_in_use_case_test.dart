import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late SignInUseCase useCase;

  setUp(() {
    repository = FakeAuthRepository();
    useCase = SignInUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test(
    'rejects an empty/invalid email without calling the repository',
    () async {
      final result = await useCase(
        email: 'not-an-email',
        password: 'irrelevant',
      );
      expect(result.isFailure, isTrue);
      expect(result.fold((_) => null, (f) => f), isA<ValidationFailure>());
      expect(repository.lastSignIn, isNull);
    },
  );

  test('rejects an empty password without calling the repository', () async {
    final result = await useCase(email: 'a@example.com', password: '');
    expect(result.isFailure, isTrue);
    expect(repository.lastSignIn, isNull);
  });

  test('trims the email and forwards to the repository', () async {
    repository.nextSignInResult = const Result.ok(null);
    final result = await useCase(
      email: '  a@example.com  ',
      password: 'secret123',
    );
    expect(result.isOk, isTrue);
    expect(repository.lastSignIn, (
      email: 'a@example.com',
      password: 'secret123',
    ));
  });

  test('propagates a repository failure', () async {
    repository.nextSignInResult = const Result.failure(
      InvalidCredentialsFailure(),
    );
    final result = await useCase(email: 'a@example.com', password: 'wrong');
    expect(result.isFailure, isTrue);
    expect(
      result.fold((_) => null, (f) => f),
      isA<InvalidCredentialsFailure>(),
    );
  });
}
