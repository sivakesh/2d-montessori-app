import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_pages_repository.dart';
import '../../support/sample_page.dart';

void main() {
  late FakePagesRepository repository;
  late RestorePageRevisionUseCase useCase;

  setUp(() {
    repository = FakePagesRepository();
    useCase = RestorePageRevisionUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test(
    'fails with PageNotEditableFailure when the page is not a draft',
    () async {
      final page = samplePage(
        status: PublishingStatus.published,
        ownerId: 'owner-1',
      );
      final result = await useCase(
        currentPage: page,
        revisionId: 'r1',
        actingRole: UserRole.editor,
        actorId: 'owner-1',
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<PageNotEditableFailure>()),
      );
      expect(repository.lastRestore, isNull);
    },
  );

  test('fails with PermissionFailure for a non-owner Editor', () async {
    final page = samplePage(status: PublishingStatus.draft, ownerId: 'owner-1');
    final result = await useCase(
      currentPage: page,
      revisionId: 'r1',
      actingRole: UserRole.editor,
      actorId: 'someone-else',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<PermissionFailure>()),
    );
  });

  test(
    'restores for the owning Editor and delegates to the repository',
    () async {
      final page = samplePage(
        status: PublishingStatus.draft,
        ownerId: 'owner-1',
      );
      repository.nextRestoreResult = Result.ok(page);
      final result = await useCase(
        currentPage: page,
        revisionId: 'r1',
        actingRole: UserRole.editor,
        actorId: 'owner-1',
      );
      expect(result.isOk, isTrue);
      expect(repository.lastRestore?.revisionId, 'r1');
    },
  );
}
