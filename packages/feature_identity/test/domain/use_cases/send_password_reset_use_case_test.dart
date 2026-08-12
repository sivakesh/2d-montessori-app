import 'package:feature_identity/feature_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;
  late SendPasswordResetUseCase useCase;

  setUp(() {
    repository = FakeAuthRepository();
    useCase = SendPasswordResetUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test('rejects an invalid email without calling the repository', () async {
    final result = await useCase('not-an-email');
    expect(result.fold((_) => null, (f) => f), isA<ValidationFailure>());
    expect(repository.lastPasswordResetEmail, isNull);
  });

  test('trims and forwards a valid email', () async {
    final result = await useCase('  a@example.com  ');
    expect(result.isOk, isTrue);
    expect(repository.lastPasswordResetEmail, 'a@example.com');
  });
}
