import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_publishing_repository.dart';

PublishingRecord _record(PublishingStatus status) {
  final now = DateTime(2026, 1, 1);
  return PublishingRecord(
    contentId: 'content-1',
    contentType: 'page',
    title: 'Test page',
    status: status,
    ownerId: 'owner-1',
    createdAt: now,
    createdBy: 'owner-1',
    updatedAt: now,
    updatedBy: 'owner-1',
  );
}

void main() {
  late FakePublishingRepository repository;
  late TransitionContentUseCase transition;

  setUp(() {
    repository = FakePublishingRepository();
    transition = TransitionContentUseCase(repository);
  });

  tearDown(() => repository.dispose());

  group('TransitionContentUseCase', () {
    test(
      'fails with InvalidTransitionFailure when the edge does not exist and never calls the repository',
      () async {
        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.publish,
          currentStatus: PublishingStatus.draft,
          actingRole: UserRole.superAdmin,
          actorId: 'admin-1',
        );

        expect(result.isFailure, isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<InvalidTransitionFailure>()),
        );
        expect(repository.lastTransition, isNull);
      },
    );

    test(
      'fails with PermissionFailure when the role lacks the required capability and never calls the repository',
      () async {
        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.approve,
          currentStatus: PublishingStatus.inReview,
          actingRole: UserRole.editor,
          actorId: 'editor-1',
        );

        expect(result.isFailure, isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<PermissionFailure>()),
        );
        expect(repository.lastTransition, isNull);
      },
    );

    test(
      'fails with CommentRequiredFailure when reject is called without a comment',
      () async {
        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.reject,
          currentStatus: PublishingStatus.inReview,
          actingRole: UserRole.superAdmin,
          actorId: 'admin-1',
        );

        expect(result.isFailure, isTrue);
        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<CommentRequiredFailure>()),
        );
        expect(repository.lastTransition, isNull);
      },
    );

    test(
      'fails with CommentRequiredFailure when the comment is blank',
      () async {
        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.reject,
          currentStatus: PublishingStatus.inReview,
          actingRole: UserRole.superAdmin,
          actorId: 'admin-1',
          comment: '   ',
        );

        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<CommentRequiredFailure>()),
        );
      },
    );

    test(
      'fails with InvalidScheduleFailure when scheduledAt is missing',
      () async {
        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.schedule,
          currentStatus: PublishingStatus.approved,
          actingRole: UserRole.publisher,
          actorId: 'pub-1',
        );

        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<InvalidScheduleFailure>()),
        );
        expect(repository.lastTransition, isNull);
      },
    );

    test(
      'fails with InvalidScheduleFailure when scheduledAt is in the past',
      () async {
        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.schedule,
          currentStatus: PublishingStatus.approved,
          actingRole: UserRole.publisher,
          actorId: 'pub-1',
          scheduledAt: DateTime(2000, 1, 1),
        );

        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<InvalidScheduleFailure>()),
        );
      },
    );

    test(
      'delegates to the repository and returns its result once all checks pass',
      () async {
        repository.nextTransitionResult = Result.ok(
          _record(PublishingStatus.approved),
        );

        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.approve,
          currentStatus: PublishingStatus.inReview,
          actingRole: UserRole.superAdmin,
          actorId: 'admin-1',
        );

        expect(result.isOk, isTrue);
        expect(repository.lastTransition?.contentId, 'content-1');
        expect(repository.lastTransition?.action, PublishingAction.approve);
        expect(repository.lastTransition?.actorId, 'admin-1');
      },
    );

    test(
      'passes a future scheduledAt through to the repository for schedule',
      () async {
        final future = DateTime.now().add(const Duration(days: 1));
        repository.nextTransitionResult = Result.ok(
          _record(PublishingStatus.scheduled),
        );

        final result = await transition(
          contentId: 'content-1',
          action: PublishingAction.schedule,
          currentStatus: PublishingStatus.approved,
          actingRole: UserRole.publisher,
          actorId: 'pub-1',
          scheduledAt: future,
        );

        expect(result.isOk, isTrue);
        expect(repository.lastTransition?.scheduledAt, future);
      },
    );
  });

  group('named wrapper use cases', () {
    test('SubmitForReviewUseCase: Editor may submit their own draft', () async {
      repository.nextTransitionResult = Result.ok(
        _record(PublishingStatus.inReview),
      );
      final useCase = SubmitForReviewUseCase(transition);

      final result = await useCase(
        contentId: 'content-1',
        currentStatus: PublishingStatus.draft,
        actingRole: UserRole.editor,
        actorId: 'editor-1',
      );

      expect(result.isOk, isTrue);
      expect(
        repository.lastTransition?.action,
        PublishingAction.submitForReview,
      );
    });

    test('ApproveContentUseCase: Editor is denied', () async {
      final useCase = ApproveContentUseCase(transition);

      final result = await useCase(
        contentId: 'content-1',
        currentStatus: PublishingStatus.inReview,
        actingRole: UserRole.editor,
        actorId: 'editor-1',
      );

      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<PermissionFailure>()),
      );
    });

    test(
      'RejectContentUseCase: requires a non-blank comment even though the parameter is required',
      () async {
        final useCase = RejectContentUseCase(transition);

        final result = await useCase(
          contentId: 'content-1',
          currentStatus: PublishingStatus.inReview,
          actingRole: UserRole.superAdmin,
          actorId: 'admin-1',
          comment: '',
        );

        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<CommentRequiredFailure>()),
        );
      },
    );

    test(
      'RejectContentUseCase: succeeds with a comment and returns to Draft',
      () async {
        repository.nextTransitionResult = Result.ok(
          _record(PublishingStatus.draft),
        );
        final useCase = RejectContentUseCase(transition);

        final result = await useCase(
          contentId: 'content-1',
          currentStatus: PublishingStatus.approved,
          actingRole: UserRole.publisher,
          actorId: 'pub-1',
          comment: 'Needs more detail.',
        );

        expect(result.isOk, isTrue);
        expect(repository.lastTransition?.comment, 'Needs more detail.');
      },
    );

    test(
      'PublishContentUseCase: Publisher may publish Approved content',
      () async {
        repository.nextTransitionResult = Result.ok(
          _record(PublishingStatus.published),
        );
        final useCase = PublishContentUseCase(transition);

        final result = await useCase(
          contentId: 'content-1',
          currentStatus: PublishingStatus.approved,
          actingRole: UserRole.publisher,
          actorId: 'pub-1',
        );

        expect(result.isOk, isTrue);
        expect(repository.lastTransition?.action, PublishingAction.publish);
      },
    );

    test('UnpublishContentUseCase: moves Published to Archived', () async {
      repository.nextTransitionResult = Result.ok(
        _record(PublishingStatus.archived),
      );
      final useCase = UnpublishContentUseCase(transition);

      final result = await useCase(
        contentId: 'content-1',
        currentStatus: PublishingStatus.published,
        actingRole: UserRole.superAdmin,
        actorId: 'admin-1',
      );

      expect(result.isOk, isTrue);
      expect(repository.lastTransition?.action, PublishingAction.unpublish);
    });

    test(
      'ScheduleContentUseCase: Editor is denied even with a valid future date',
      () async {
        final useCase = ScheduleContentUseCase(transition);

        final result = await useCase(
          contentId: 'content-1',
          currentStatus: PublishingStatus.approved,
          actingRole: UserRole.editor,
          actorId: 'editor-1',
          scheduledAt: DateTime.now().add(const Duration(days: 1)),
        );

        result.fold(
          (_) => fail('expected failure'),
          (f) => expect(f, isA<PermissionFailure>()),
        );
      },
    );

    test(
      'UnscheduleContentUseCase: moves Scheduled back to Approved',
      () async {
        repository.nextTransitionResult = Result.ok(
          _record(PublishingStatus.approved),
        );
        final useCase = UnscheduleContentUseCase(transition);

        final result = await useCase(
          contentId: 'content-1',
          currentStatus: PublishingStatus.scheduled,
          actingRole: UserRole.publisher,
          actorId: 'pub-1',
        );

        expect(result.isOk, isTrue);
        expect(repository.lastTransition?.action, PublishingAction.unschedule);
      },
    );

    test('ArchiveContentUseCase: archives directly from Draft', () async {
      repository.nextTransitionResult = Result.ok(
        _record(PublishingStatus.archived),
      );
      final useCase = ArchiveContentUseCase(transition);

      final result = await useCase(
        contentId: 'content-1',
        currentStatus: PublishingStatus.draft,
        actingRole: UserRole.superAdmin,
        actorId: 'admin-1',
      );

      expect(result.isOk, isTrue);
      expect(repository.lastTransition?.action, PublishingAction.archive);
    });

    test('RestoreContentUseCase: moves Archived back to Draft', () async {
      repository.nextTransitionResult = Result.ok(
        _record(PublishingStatus.draft),
      );
      final useCase = RestoreContentUseCase(transition);

      final result = await useCase(
        contentId: 'content-1',
        currentStatus: PublishingStatus.archived,
        actingRole: UserRole.publisher,
        actorId: 'pub-1',
      );

      expect(result.isOk, isTrue);
      expect(repository.lastTransition?.action, PublishingAction.restore);
    });
  });
}
