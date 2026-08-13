import 'package:core_contracts/core_contracts.dart' as core;
import 'package:feature_publishing/feature_publishing.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/cms_page.dart';
import '../domain/page_content_update.dart';
import '../domain/page_repository.dart';
import '../domain/page_revision.dart';
import 'cms_page_mapper.dart';
import 'page_failure_mapper.dart';
import 'page_revision_mapper.dart';

/// Cloud Functions callable names — `pagesFns-<name>` per the grouped
/// export naming (`export * as pagesFns from './pages'` in
/// functions/src/index.ts), mirroring `_PublishingCallables` in
/// `feature_publishing`. `transitionPage` (not `publishingFns-
/// transitionContent`) is used for every workflow action so the SRS
/// CMS-08 completeness gate `functions/src/pages/transitionPage.ts` adds
/// on submit/publish/schedule actually runs — the underlying transition
/// engine it delegates to afterwards is the exact same
/// `applyTransition.ts` `publishingFns-transitionContent` also uses.
abstract final class _PagesCallables {
  static const createPage = 'pagesFns-createPage';
  static const updatePageContent = 'pagesFns-updatePageContent';
  static const transitionPage = 'pagesFns-transitionPage';
  static const restorePageRevision = 'pagesFns-restorePageRevision';
}

class FirestorePagesRepository implements PagesRepository {
  FirestorePagesRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Future<core.Result<CmsPage>> createPage({
    required String title,
    required String ownerId,
  }) async {
    try {
      final response = await _functions
          .httpsCallable(_PagesCallables.createPage)
          .call<Map<String, dynamic>>({'title': title});
      return get(response.data['pageId'] as String);
    } on FirebaseFunctionsException catch (e) {
      return core.Result.failure(PageFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<core.Result<CmsPage>> updateContent({
    required String pageId,
    required PageContentUpdate content,
  }) async {
    try {
      await _functions
          .httpsCallable(_PagesCallables.updatePageContent)
          .call<Map<String, dynamic>>({'pageId': pageId, ...content.toMap()});
      return get(pageId);
    } on FirebaseFunctionsException catch (e) {
      return core.Result.failure(PageFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<core.Result<CmsPage>> get(String pageId) async {
    try {
      final snapshot = await _firestore.collection('content').doc(pageId).get();
      if (!snapshot.exists) {
        return const core.Result.failure(ContentNotFoundFailure());
      }
      return core.Result.ok(CmsPageMapper.fromSnapshot(snapshot));
    } on FirebaseException catch (e) {
      return core.Result.failure(
        UnknownPublishingFailure(e.message ?? 'Failed to load page.'),
      );
    }
  }

  @override
  Stream<core.Result<CmsPage>> observe(String pageId) {
    return _firestore.collection('content').doc(pageId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return const core.Result.failure(ContentNotFoundFailure());
      }
      return core.Result.ok(CmsPageMapper.fromSnapshot(snapshot));
    });
  }

  @override
  Future<core.Result<core.Page<CmsPage>>> list({
    PagesQuery query = const PagesQuery(),
    core.PageRequest request = const core.PageRequest(),
  }) async {
    try {
      Query<Map<String, dynamic>> firestoreQuery = _firestore
          .collection('content')
          .where('contentType', isEqualTo: 'page');
      if (query.status != null) {
        firestoreQuery = firestoreQuery.where(
          'status',
          isEqualTo: query.status!.storageValue,
        );
      }
      if (query.ownerId != null) {
        firestoreQuery = firestoreQuery.where(
          'ownerId',
          isEqualTo: query.ownerId,
        );
      }
      firestoreQuery = firestoreQuery
          .orderBy('createdAt', descending: true)
          .limit(request.limit);

      if (request.cursor != null) {
        final cursorDoc = await _firestore
            .collection('content')
            .doc(request.cursor)
            .get();
        if (cursorDoc.exists) {
          firestoreQuery = firestoreQuery.startAfterDocument(cursorDoc);
        }
      }

      final snapshot = await firestoreQuery.get();
      var pages = snapshot.docs.map(CmsPageMapper.fromSnapshot).toList();

      final search = query.searchText?.trim().toLowerCase();
      if (search != null && search.isNotEmpty) {
        pages = pages
            .where(
              (p) =>
                  p.title.toLowerCase().contains(search) ||
                  p.summary.toLowerCase().contains(search),
            )
            .toList();
      }

      return core.Result.ok(
        core.Page(
          items: pages,
          nextCursor: pages.isEmpty ? null : pages.last.pageId,
          hasMore: snapshot.docs.length == request.limit,
        ),
      );
    } on FirebaseException catch (e) {
      return core.Result.failure(
        UnknownPublishingFailure(e.message ?? 'Failed to load pages.'),
      );
    }
  }

  @override
  Future<core.Result<List<PageRevision>>> listRevisions(String pageId) async {
    try {
      final snapshot = await _firestore
          .collection('content')
          .doc(pageId)
          .collection('revisions')
          .orderBy('createdAt', descending: true)
          .get();
      return core.Result.ok(
        snapshot.docs
            .map((d) => PageRevisionMapper.fromSnapshot(pageId, d))
            .toList(),
      );
    } on FirebaseException catch (e) {
      return core.Result.failure(
        UnknownPublishingFailure(
          e.message ?? 'Failed to load revision history.',
        ),
      );
    }
  }

  @override
  Future<core.Result<CmsPage>> restoreRevision({
    required String pageId,
    required String revisionId,
    required String actorId,
  }) async {
    try {
      await _functions
          .httpsCallable(_PagesCallables.restorePageRevision)
          .call<Map<String, dynamic>>({
            'pageId': pageId,
            'revisionId': revisionId,
          });
      return get(pageId);
    } on FirebaseFunctionsException catch (e) {
      return core.Result.failure(PageFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<core.Result<CmsPage>> transition({
    required String pageId,
    required PublishingAction action,
    required String actorId,
    String? comment,
    DateTime? scheduledAt,
  }) async {
    try {
      await _functions
          .httpsCallable(_PagesCallables.transitionPage)
          .call<Map<String, dynamic>>({
            'contentId': pageId,
            'action': action.storageValue,
            if (comment != null) 'comment': comment,
            if (scheduledAt != null)
              'scheduledAt': scheduledAt.toIso8601String(),
          });
      return get(pageId);
    } on FirebaseFunctionsException catch (e) {
      return core.Result.failure(PageFailureMapper.fromFunctionsException(e));
    }
  }
}
