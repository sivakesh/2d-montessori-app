import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_pages_repository.dart';
import '../support/sample_page.dart';

/// Proves the adapter lets `feature_publishing`'s *unmodified* named use
/// cases drive a page end to end — the core claim behind "reuses the
/// existing feature_publishing contracts... does not duplicate the
/// workflow engine".
void main() {
  late FakePagesRepository repository;
  late PagesAsPublishingRepository adapter;

  setUp(() {
    repository = FakePagesRepository();
    adapter = PagesAsPublishingRepository(repository);
  });

  tearDown(() => repository.dispose());

  test(
    'createDraft delegates to PagesRepository.createPage and maps the result',
    () async {
      repository.nextCreateResult = Result.ok(
        samplePage(title: 'About', ownerId: 'owner-1'),
      );
      final result = await adapter.createDraft(
        contentType: 'page',
        title: 'About',
        ownerId: 'owner-1',
      );

      expect(result.isOk, isTrue);
      expect(repository.lastCreate?.title, 'About');
      result.fold(
        (record) => expect(record.contentType, 'page'),
        (_) => fail('expected success'),
      );
    },
  );

  test('get maps a CmsPage to a PublishingRecord', () async {
    repository.nextGetResult = Result.ok(
      samplePage(pageId: 'p1', status: PublishingStatus.approved),
    );
    final result = await adapter.get('p1');
    result.fold(
      (record) => expect(record.status, PublishingStatus.approved),
      (_) => fail('expected success'),
    );
  });

  test('transition delegates to PagesRepository.transition', () async {
    repository.nextTransitionResult = Result.ok(
      samplePage(status: PublishingStatus.inReview),
    );
    final result = await adapter.transition(
      contentId: 'p1',
      action: PublishingAction.submitForReview,
      actorId: 'owner-1',
    );
    expect(result.isOk, isTrue);
    expect(repository.lastTransition?.action, PublishingAction.submitForReview);
  });

  test(
    'an unmodified SubmitForReviewUseCase built on the adapter drives a real transition',
    () async {
      repository.nextTransitionResult = Result.ok(
        samplePage(status: PublishingStatus.inReview),
      );
      final transitionUseCase = TransitionContentUseCase(adapter);
      final submitForReview = SubmitForReviewUseCase(transitionUseCase);

      final result = await submitForReview(
        contentId: 'p1',
        currentStatus: PublishingStatus.draft,
        actingRole: UserRole.editor,
        actorId: 'owner-1',
      );

      expect(result.isOk, isTrue);
      expect(repository.lastTransition?.pageId, 'p1');
      expect(
        repository.lastTransition?.action,
        PublishingAction.submitForReview,
      );
    },
  );

  test(
    'the shared engine still rejects an invalid transition before the adapter is ever called',
    () async {
      final transitionUseCase = TransitionContentUseCase(adapter);
      final publish = PublishContentUseCase(transitionUseCase);

      final result = await publish(
        contentId: 'p1',
        currentStatus: PublishingStatus.draft,
        actingRole: UserRole.superAdmin,
        actorId: 'admin-1',
      );

      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<InvalidTransitionFailure>()),
      );
      expect(repository.lastTransition, isNull);
    },
  );
}
