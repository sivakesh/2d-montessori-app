import 'package:core_contracts/core_contracts.dart';
import 'package:feature_publishing/feature_publishing.dart'
    show ContentNotFoundFailure, UnknownPublishingFailure;
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/public_page_view.dart';
import '../domain/public_pages_repository.dart';
import 'public_page_view_mapper.dart';

/// Reads directly from the public `publishedPages` collection — no Cloud
/// Functions callable involved, since Firestore Rules already grant
/// unauthenticated read on it (see firebase/firestore.rules) and there is
/// nothing privileged about resolving a slug. This is the entire public
/// read surface `apps/public_web` needs for Pages.
class FirestorePublicPagesRepository implements PublicPagesRepository {
  FirestorePublicPagesRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  @override
  Future<Result<PublicPageView>> getBySlug(String slug) async {
    try {
      final snapshot = await _firestore
          .collection('publishedPages')
          .doc(slug)
          .get();
      if (!snapshot.exists) {
        return const Result.failure(ContentNotFoundFailure());
      }
      return Result.ok(PublicPageViewMapper.fromSnapshot(snapshot));
    } on FirebaseException catch (e) {
      return Result.failure(
        UnknownPublishingFailure(e.message ?? 'Failed to load this page.'),
      );
    }
  }

  @override
  Future<Result<List<PublicPageView>>> listNavigationPages() async {
    try {
      final snapshot = await _firestore
          .collection('publishedPages')
          .where('showInNavigation', isEqualTo: true)
          .get();
      return Result.ok(
        snapshot.docs.map(PublicPageViewMapper.fromSnapshot).toList(),
      );
    } on FirebaseException catch (e) {
      return Result.failure(
        UnknownPublishingFailure(e.message ?? 'Failed to load navigation.'),
      );
    }
  }
}
