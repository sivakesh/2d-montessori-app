import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_pages_repository.dart';
import '../../support/sample_page.dart';

void main() {
  late FakePagesRepository repository;
  late CreatePageUseCase useCase;

  setUp(() {
    repository = FakePagesRepository();
    useCase = CreatePageUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test('rejects a blank title without calling the repository', () async {
    final result = await useCase(title: '   ', ownerId: 'owner-1');
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<ValidationFailure>()),
    );
    expect(repository.lastCreate, isNull);
  });

  test('trims the title and delegates to the repository', () async {
    repository.nextCreateResult = Result.ok(samplePage(title: 'About us'));
    final result = await useCase(title: '  About us  ', ownerId: 'owner-1');

    expect(result.isOk, isTrue);
    expect(repository.lastCreate?.title, 'About us');
    expect(repository.lastCreate?.ownerId, 'owner-1');
  });
}
