import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_pages_repository.dart';
import '../../support/sample_page.dart';

PageContentUpdate _validUpdate({
  String title = 'About us',
  String slug = 'about-us',
}) => PageContentUpdate(
  title: title,
  slug: slug,
  summary: 'Summary',
  pageType: PageType.standard,
  sections: const [],
  seo: const SeoMetadata(),
  showInNavigation: false,
);

void main() {
  late FakePagesRepository repository;
  late UpdatePageContentUseCase useCase;

  setUp(() {
    repository = FakePagesRepository();
    useCase = UpdatePageContentUseCase(repository);
  });

  tearDown(() => repository.dispose());

  test(
    'fails with PageNotEditableFailure when the page is not a draft',
    () async {
      final page = samplePage(
        status: PublishingStatus.inReview,
        ownerId: 'owner-1',
      );
      final result = await useCase(
        currentPage: page,
        content: _validUpdate(),
        actingRole: UserRole.editor,
        actorId: 'owner-1',
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<PageNotEditableFailure>()),
      );
      expect(repository.lastUpdate, isNull);
    },
  );

  test(
    'fails with PermissionFailure when an Editor tries to edit a page they do not own',
    () async {
      final page = samplePage(
        status: PublishingStatus.draft,
        ownerId: 'owner-1',
      );
      final result = await useCase(
        currentPage: page,
        content: _validUpdate(),
        actingRole: UserRole.editor,
        actorId: 'someone-else',
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<PermissionFailure>()),
      );
      expect(repository.lastUpdate, isNull);
    },
  );

  test('allows an Editor to edit their own draft', () async {
    final page = samplePage(status: PublishingStatus.draft, ownerId: 'owner-1');
    repository.nextUpdateResult = Result.ok(page);
    final result = await useCase(
      currentPage: page,
      content: _validUpdate(),
      actingRole: UserRole.editor,
      actorId: 'owner-1',
    );
    expect(result.isOk, isTrue);
    expect(repository.lastUpdate?.pageId, page.pageId);
  });

  test(
    'allows a Publisher to edit content they do not own (edit-all-content)',
    () async {
      final page = samplePage(
        status: PublishingStatus.draft,
        ownerId: 'owner-1',
      );
      repository.nextUpdateResult = Result.ok(page);
      final result = await useCase(
        currentPage: page,
        content: _validUpdate(),
        actingRole: UserRole.publisher,
        actorId: 'publisher-9',
      );
      expect(result.isOk, isTrue);
    },
  );

  test('fails with ValidationFailure for a blank title', () async {
    final page = samplePage(status: PublishingStatus.draft, ownerId: 'owner-1');
    final result = await useCase(
      currentPage: page,
      content: _validUpdate(title: '  '),
      actingRole: UserRole.editor,
      actorId: 'owner-1',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<ValidationFailure>()),
    );
  });

  test('fails with ValidationFailure for an invalid slug format', () async {
    final page = samplePage(status: PublishingStatus.draft, ownerId: 'owner-1');
    final result = await useCase(
      currentPage: page,
      content: _validUpdate(slug: 'Not Valid!'),
      actingRole: UserRole.editor,
      actorId: 'owner-1',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<ValidationFailure>()),
    );
  });
}
