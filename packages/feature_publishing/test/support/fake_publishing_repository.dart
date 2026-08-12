import 'dart:async';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';

class FakePublishingRepository implements PublishingRepository {
  final _controllers = <String, StreamController<Result<PublishingRecord>>>{};

  Result<PublishingRecord> nextCreateDraftResult = const Result.failure(
    ValidationFailure('not configured'),
  );
  Result<PublishingRecord> nextGetResult = const Result.failure(
    ContentNotFoundFailure(),
  );
  Result<PublishingRecord> nextTransitionResult = const Result.failure(
    ValidationFailure('not configured'),
  );

  ({String contentType, String title, String ownerId})? lastCreateDraft;
  String? lastGetContentId;
  ({
    String contentId,
    PublishingAction action,
    String actorId,
    String? comment,
    DateTime? scheduledAt,
  })?
  lastTransition;

  @override
  Future<Result<PublishingRecord>> createDraft({
    required String contentType,
    required String title,
    required String ownerId,
  }) async {
    lastCreateDraft = (
      contentType: contentType,
      title: title,
      ownerId: ownerId,
    );
    return nextCreateDraftResult;
  }

  @override
  Future<Result<PublishingRecord>> get(String contentId) async {
    lastGetContentId = contentId;
    return nextGetResult;
  }

  @override
  Stream<Result<PublishingRecord>> observe(String contentId) {
    return _controllers
        .putIfAbsent(
          contentId,
          () => StreamController<Result<PublishingRecord>>.broadcast(),
        )
        .stream;
  }

  @override
  Future<Result<PublishingRecord>> transition({
    required String contentId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  }) async {
    lastTransition = (
      contentId: contentId,
      action: action,
      actorId: actorId,
      comment: comment,
      scheduledAt: scheduledAt,
    );
    return nextTransitionResult;
  }

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
