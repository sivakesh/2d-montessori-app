import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';

import 'page_repository.dart';

/// Adapts a [PagesRepository] to `feature_publishing`'s
/// [PublishingRepository] interface so pages can be driven through the
/// *unmodified* `TransitionContentUseCase` and all nine named workflow
/// use cases (`SubmitForReviewUseCase`, `ApproveContentUseCase`, ...)
/// exactly as `feature_publishing` exports them — zero duplicated
/// transition/capability logic on the client, per this milestone's
/// instruction to reuse the existing engine rather than build a
/// page-specific one.
///
/// `createDraft`'s `contentType` parameter is ignored — Pages always
/// create through [PagesRepository.createPage], which this class's own
/// `createDraft` delegates to; the parameter exists only to satisfy
/// [PublishingRepository]'s generic signature.
class PagesAsPublishingRepository implements PublishingRepository {
  const PagesAsPublishingRepository(this._pages);

  final PagesRepository _pages;

  @override
  Future<Result<PublishingRecord>> createDraft({
    required String contentType,
    required String title,
    required String ownerId,
  }) async {
    final result = await _pages.createPage(title: title, ownerId: ownerId);
    return result.fold(
      (page) => Result.ok(page.toPublishingRecord()),
      (failure) => Result.failure(failure),
    );
  }

  @override
  Future<Result<PublishingRecord>> get(String contentId) async {
    final result = await _pages.get(contentId);
    return result.fold(
      (page) => Result.ok(page.toPublishingRecord()),
      (failure) => Result.failure(failure),
    );
  }

  @override
  Stream<Result<PublishingRecord>> observe(String contentId) => _pages
      .observe(contentId)
      .map(
        (result) => result.fold(
          (page) => Result.ok(page.toPublishingRecord()),
          (failure) => Result.failure(failure),
        ),
      );

  @override
  Future<Result<PublishingRecord>> transition({
    required String contentId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  }) async {
    final result = await _pages.transition(
      pageId: contentId,
      action: action,
      actorId: actorId,
      comment: comment,
      scheduledAt: scheduledAt,
    );
    return result.fold(
      (page) => Result.ok(page.toPublishingRecord()),
      (failure) => Result.failure(failure),
    );
  }
}
