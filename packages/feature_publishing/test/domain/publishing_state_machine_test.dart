import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublishingStateMachine.resolve', () {
    const expectedEdges =
        <(PublishingStatus, PublishingAction, PublishingStatus)>[
          (
            PublishingStatus.draft,
            PublishingAction.submitForReview,
            PublishingStatus.inReview,
          ),
          (
            PublishingStatus.draft,
            PublishingAction.archive,
            PublishingStatus.archived,
          ),
          (
            PublishingStatus.inReview,
            PublishingAction.reject,
            PublishingStatus.draft,
          ),
          (
            PublishingStatus.inReview,
            PublishingAction.approve,
            PublishingStatus.approved,
          ),
          (
            PublishingStatus.inReview,
            PublishingAction.archive,
            PublishingStatus.archived,
          ),
          (
            PublishingStatus.approved,
            PublishingAction.reject,
            PublishingStatus.draft,
          ),
          (
            PublishingStatus.approved,
            PublishingAction.schedule,
            PublishingStatus.scheduled,
          ),
          (
            PublishingStatus.approved,
            PublishingAction.publish,
            PublishingStatus.published,
          ),
          (
            PublishingStatus.approved,
            PublishingAction.archive,
            PublishingStatus.archived,
          ),
          (
            PublishingStatus.scheduled,
            PublishingAction.unschedule,
            PublishingStatus.approved,
          ),
          (
            PublishingStatus.scheduled,
            PublishingAction.publish,
            PublishingStatus.published,
          ),
          (
            PublishingStatus.scheduled,
            PublishingAction.archive,
            PublishingStatus.archived,
          ),
          (
            PublishingStatus.published,
            PublishingAction.unpublish,
            PublishingStatus.archived,
          ),
          (
            PublishingStatus.archived,
            PublishingAction.restore,
            PublishingStatus.draft,
          ),
        ];

    for (final (from, action, to) in expectedEdges) {
      test('$from --${action.storageValue}--> $to', () {
        expect(PublishingStateMachine.resolve(from, action)?.to, to);
      });
    }

    test('returns null for an edge that does not exist', () {
      expect(
        PublishingStateMachine.resolve(
          PublishingStatus.draft,
          PublishingAction.publish,
        ),
        isNull,
      );
      expect(
        PublishingStateMachine.resolve(
          PublishingStatus.published,
          PublishingAction.submitForReview,
        ),
        isNull,
      );
    });

    test('reject requires a comment', () {
      expect(
        PublishingStateMachine.resolve(
          PublishingStatus.inReview,
          PublishingAction.reject,
        )?.requiresComment,
        isTrue,
      );
      expect(
        PublishingStateMachine.resolve(
          PublishingStatus.approved,
          PublishingAction.reject,
        )?.requiresComment,
        isTrue,
      );
    });

    test('schedule requires a future scheduledAt', () {
      expect(
        PublishingStateMachine.resolve(
          PublishingStatus.approved,
          PublishingAction.schedule,
        )?.requiresFutureScheduledAt,
        isTrue,
      );
    });
  });

  group('PublishingStateMachine.isAllowed', () {
    test('Editor may submit for review but not approve', () {
      expect(
        PublishingStateMachine.isAllowed(
          PublishingStatus.draft,
          PublishingAction.submitForReview,
          UserRole.editor,
        ),
        isTrue,
      );
      expect(
        PublishingStateMachine.isAllowed(
          PublishingStatus.inReview,
          PublishingAction.approve,
          UserRole.editor,
        ),
        isFalse,
      );
    });

    test('Editor may not schedule ("suggest only" is not full access)', () {
      expect(
        PublishingStateMachine.isAllowed(
          PublishingStatus.approved,
          PublishingAction.schedule,
          UserRole.editor,
        ),
        isFalse,
      );
      expect(
        PublishingStateMachine.isAllowed(
          PublishingStatus.approved,
          PublishingAction.schedule,
          UserRole.publisher,
        ),
        isTrue,
      );
    });

    test('Publisher and Super Admin may approve/publish/archive/restore', () {
      for (final role in [UserRole.publisher, UserRole.superAdmin]) {
        expect(
          PublishingStateMachine.isAllowed(
            PublishingStatus.inReview,
            PublishingAction.approve,
            role,
          ),
          isTrue,
        );
        expect(
          PublishingStateMachine.isAllowed(
            PublishingStatus.approved,
            PublishingAction.publish,
            role,
          ),
          isTrue,
        );
        expect(
          PublishingStateMachine.isAllowed(
            PublishingStatus.published,
            PublishingAction.unpublish,
            role,
          ),
          isTrue,
        );
        expect(
          PublishingStateMachine.isAllowed(
            PublishingStatus.archived,
            PublishingAction.restore,
            role,
          ),
          isTrue,
        );
      }
    });

    test('returns false for a nonexistent edge regardless of role', () {
      expect(
        PublishingStateMachine.isAllowed(
          PublishingStatus.draft,
          PublishingAction.publish,
          UserRole.superAdmin,
        ),
        isFalse,
      );
    });
  });
}
