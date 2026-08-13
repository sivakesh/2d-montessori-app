import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter/foundation.dart';

import '../domain/cms_page.dart';
import '../domain/page_completeness_validator.dart';
import '../domain/page_content_update.dart';
import '../domain/page_repository.dart';
import '../domain/page_revision.dart';
import '../domain/pages_as_publishing_repository.dart';
import '../domain/use_cases/list_page_revisions_use_case.dart';
import '../domain/use_cases/restore_page_revision_use_case.dart';
import '../domain/use_cases/update_page_content_use_case.dart';

/// Drives one page's editor screen: holds the current [page], the client-
/// side completeness check (SRS CMS-08, UX only), and every workflow
/// action — routed through `feature_publishing`'s unmodified named use
/// cases via [PagesAsPublishingRepository], never a page-specific
/// re-implementation of transition logic. The client never decides
/// whether a transition is *allowed* beyond hiding controls for UX; the
/// Cloud Functions callable behind every use case re-validates
/// authoritatively (see [PagesRepository.transition]'s doc comment).
class PageEditorController extends ChangeNotifier {
  PageEditorController({
    required PagesRepository repository,
    required this.actingRole,
    required this.actorId,
    required CmsPage initialPage,
  }) : _repository = repository,
       _page = initialPage {
    final publishingRepository = PagesAsPublishingRepository(_repository);
    _transitionUseCase = TransitionContentUseCase(publishingRepository);
    _updateContent = UpdatePageContentUseCase(_repository);
    _listRevisions = ListPageRevisionsUseCase(_repository);
    _restoreRevision = RestorePageRevisionUseCase(_repository);
    submitForReview = SubmitForReviewUseCase(_transitionUseCase);
    approveContent = ApproveContentUseCase(_transitionUseCase);
    rejectContent = RejectContentUseCase(_transitionUseCase);
    publishContent = PublishContentUseCase(_transitionUseCase);
    unpublishContent = UnpublishContentUseCase(_transitionUseCase);
    scheduleContent = ScheduleContentUseCase(_transitionUseCase);
    unscheduleContent = UnscheduleContentUseCase(_transitionUseCase);
    archiveContent = ArchiveContentUseCase(_transitionUseCase);
    restoreContent = RestoreContentUseCase(_transitionUseCase);
  }

  final PagesRepository _repository;
  final UserRole actingRole;
  final String actorId;

  late final TransitionContentUseCase _transitionUseCase;
  late final UpdatePageContentUseCase _updateContent;
  late final ListPageRevisionsUseCase _listRevisions;
  late final RestorePageRevisionUseCase _restoreRevision;

  late final SubmitForReviewUseCase submitForReview;
  late final ApproveContentUseCase approveContent;
  late final RejectContentUseCase rejectContent;
  late final PublishContentUseCase publishContent;
  late final UnpublishContentUseCase unpublishContent;
  late final ScheduleContentUseCase scheduleContent;
  late final UnscheduleContentUseCase unscheduleContent;
  late final ArchiveContentUseCase archiveContent;
  late final RestoreContentUseCase restoreContent;

  CmsPage _page;
  CmsPage get page => _page;

  bool isBusy = false;
  String? lastErrorMessage;
  DateTime? lastSavedAt;
  List<PageRevision> revisions = const [];

  bool get canEditContent =>
      page.status == PublishingStatus.draft &&
      (RolePermissionMatrix.hasFull(actingRole, Capability.editAllContent) ||
          page.ownerId == actorId);

  List<String> get completenessViolations =>
      PageCompletenessValidator.validate(page);

  Future<bool> saveContent(PageContentUpdate content) => _run(() async {
    final result = await _updateContent(
      currentPage: page,
      content: content,
      actingRole: actingRole,
      actorId: actorId,
    );
    return result.fold(
      (updated) {
        _page = updated;
        lastSavedAt = DateTime.now();
        return true;
      },
      (failure) {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  Future<bool> loadRevisions() => _run(() async {
    final result = await _listRevisions(page.pageId);
    return result.fold(
      (list) {
        revisions = list;
        return true;
      },
      (failure) {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  Future<bool> restoreRevision(String revisionId) => _run(() async {
    final result = await _restoreRevision(
      currentPage: page,
      revisionId: revisionId,
      actingRole: actingRole,
      actorId: actorId,
    );
    return result.fold(
      (updated) {
        _page = updated;
        return true;
      },
      (failure) {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  Future<bool> _transitionCall(
    Future<Result<PublishingRecord>> Function() action,
  ) => _run(() async {
    final result = await action();
    return result.fold(
      (record) async {
        final refreshed = await _repository.get(page.pageId);
        refreshed.fold((updated) => _page = updated, (_) {});
        return true;
      },
      (failure) {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  Future<bool> doSubmitForReview() => _transitionCall(
    () => submitForReview(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> doApprove() => _transitionCall(
    () => approveContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> doReject(String comment) => _transitionCall(
    () => rejectContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
      comment: comment,
    ),
  );

  Future<bool> doPublish() => _transitionCall(
    () => publishContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> doUnpublish() => _transitionCall(
    () => unpublishContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> doSchedule(DateTime at) => _transitionCall(
    () => scheduleContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
      scheduledAt: at,
    ),
  );

  Future<bool> doUnschedule() => _transitionCall(
    () => unscheduleContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> doArchive() => _transitionCall(
    () => archiveContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> doRestore() => _transitionCall(
    () => restoreContent(
      contentId: page.pageId,
      currentStatus: page.status,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> _run(Future<bool> Function() body) async {
    isBusy = true;
    lastErrorMessage = null;
    notifyListeners();
    try {
      final ok = await body();
      return ok;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
