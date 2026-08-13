import 'dart:async';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:feature_publishing/feature_publishing.dart';

class FakePagesRepository implements PagesRepository {
  final _controllers = <String, StreamController<Result<CmsPage>>>{};

  Result<CmsPage> nextCreateResult = const Result.failure(
    ValidationFailure('not configured'),
  );
  Result<CmsPage> nextUpdateResult = const Result.failure(
    ValidationFailure('not configured'),
  );
  Result<CmsPage> nextGetResult = const Result.failure(
    ContentNotFoundFailure(),
  );
  Result<Page<CmsPage>> nextListResult = const Result.ok(
    Page(items: [], nextCursor: null, hasMore: false),
  );
  Result<List<PageRevision>> nextRevisionsResult = const Result.ok([]);
  Result<CmsPage> nextRestoreResult = const Result.failure(
    ValidationFailure('not configured'),
  );
  Result<CmsPage> nextTransitionResult = const Result.failure(
    ValidationFailure('not configured'),
  );

  ({String title, String ownerId})? lastCreate;
  ({String pageId, PageContentUpdate content})? lastUpdate;
  String? lastGetPageId;
  ({String pageId, String revisionId, String actorId})? lastRestore;
  ({
    String pageId,
    PublishingAction action,
    String actorId,
    String? comment,
    DateTime? scheduledAt,
  })?
  lastTransition;

  @override
  Future<Result<CmsPage>> createPage({
    required String title,
    required String ownerId,
  }) async {
    lastCreate = (title: title, ownerId: ownerId);
    return nextCreateResult;
  }

  @override
  Future<Result<CmsPage>> updateContent({
    required String pageId,
    required PageContentUpdate content,
  }) async {
    lastUpdate = (pageId: pageId, content: content);
    return nextUpdateResult;
  }

  @override
  Future<Result<CmsPage>> get(String pageId) async {
    lastGetPageId = pageId;
    return nextGetResult;
  }

  @override
  Stream<Result<CmsPage>> observe(String pageId) => _controllers
      .putIfAbsent(pageId, () => StreamController<Result<CmsPage>>.broadcast())
      .stream;

  @override
  Future<Result<Page<CmsPage>>> list({
    PagesQuery query = const PagesQuery(),
    PageRequest request = const PageRequest(),
  }) async => nextListResult;

  @override
  Future<Result<List<PageRevision>>> listRevisions(String pageId) async =>
      nextRevisionsResult;

  @override
  Future<Result<CmsPage>> restoreRevision({
    required String pageId,
    required String revisionId,
    required String actorId,
  }) async {
    lastRestore = (pageId: pageId, revisionId: revisionId, actorId: actorId);
    return nextRestoreResult;
  }

  @override
  Future<Result<CmsPage>> transition({
    required String pageId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  }) async {
    lastTransition = (
      pageId: pageId,
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
