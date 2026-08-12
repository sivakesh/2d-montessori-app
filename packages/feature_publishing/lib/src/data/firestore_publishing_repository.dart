import 'package:core_contracts/core_contracts.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/publishing_action.dart';
import '../domain/publishing_failures.dart';
import '../domain/publishing_record.dart';
import '../domain/publishing_repository.dart';
import 'publishing_failure_mapper.dart';
import 'publishing_record_mapper.dart';

/// Cloud Functions callable names, deployed/emulated as
/// `publishingFns-<name>` per the grouped-export naming in
/// functions/src/index.ts (`export * as publishingFns from
/// './publishing'`) — mirrors the `authFns-*` convention in
/// feature_identity's data layer.
///
/// Unlike feature_identity's five distinct auth callables, every
/// publishing action shares one implementation
/// (functions/src/publishing/applyTransition.ts) — the 9 actions differ
/// only in which edge of `PublishingStateMachine.transitions` applies, so
/// one parameterized `transitionContent` callable is the right shape
/// here, not 9 near-duplicates. `action.storageValue` is the parameter.
abstract final class _PublishingCallables {
  static const createDraft = 'publishingFns-createDraft';
  static const transitionContent = 'publishingFns-transitionContent';
}

class FirestorePublishingRepository implements PublishingRepository {
  FirestorePublishingRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<Result<PublishingRecord>> createDraft({
    required String contentType,
    required String title,
    required String ownerId,
  }) async {
    try {
      final response = await _functions
          .httpsCallable(_PublishingCallables.createDraft)
          .call<Map<String, dynamic>>({
            'contentType': contentType,
            'title': title,
          });
      final data = response.data;
      return Result.ok(
        PublishingRecordMapper.fromMap(data['contentId'] as String, data),
      );
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(PublishingFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<Result<PublishingRecord>> get(String contentId) async {
    try {
      final snapshot = await _firestore
          .collection('content')
          .doc(contentId)
          .get();
      if (!snapshot.exists) {
        return const Result.failure(ContentNotFoundFailure());
      }
      return Result.ok(PublishingRecordMapper.fromSnapshot(snapshot));
    } on FirebaseException catch (e) {
      return Result.failure(
        UnknownPublishingFailure(e.message ?? 'Failed to load content.'),
      );
    }
  }

  @override
  Stream<Result<PublishingRecord>> observe(String contentId) {
    return _firestore.collection('content').doc(contentId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return const Result.failure(ContentNotFoundFailure());
      }
      try {
        return Result.ok(PublishingRecordMapper.fromSnapshot(snapshot));
      } on StateError catch (e) {
        return Result.failure(UnknownPublishingFailure(e.message));
      }
    });
  }

  @override
  Future<Result<PublishingRecord>> transition({
    required String contentId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  }) async {
    try {
      final response = await _functions
          .httpsCallable(_PublishingCallables.transitionContent)
          .call<Map<String, dynamic>>({
            'contentId': contentId,
            'action': action.storageValue,
            if (comment != null) 'comment': comment,
            if (scheduledAt != null)
              'scheduledAt': scheduledAt.toIso8601String(),
          });
      return Result.ok(
        PublishingRecordMapper.fromMap(contentId, response.data),
      );
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(PublishingFailureMapper.fromFunctionsException(e));
    }
  }
}
