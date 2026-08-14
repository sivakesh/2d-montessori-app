import 'dart:async';

import 'package:core_contracts/core_contracts.dart' as core;
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/media_asset.dart';
import '../domain/media_failures.dart';
import '../domain/media_repository.dart';
import '../domain/media_status.dart';
import '../domain/media_upload_event.dart';
import '../domain/media_upload_request.dart';
import '../domain/media_usage_reference.dart';
import 'media_asset_mapper.dart';
import 'media_failure_mapper.dart';
import 'media_usage_reference_mapper.dart';

/// `mediaFns-<name>` per the grouped export naming (`export * as
/// mediaFns from './media'` in functions/src/index.ts) — mirrors
/// `feature_pages`' `_PagesCallables` convention. Upload itself is
/// deliberately NOT here — it is a direct authenticated Storage write,
/// not a callable; see `functions/src/media/index.ts`'s doc comment.
abstract final class _MediaCallables {
  static const updateMediaMetadata = 'mediaFns-updateMediaMetadata';
  static const archiveMedia = 'mediaFns-archiveMedia';
  static const restoreMedia = 'mediaFns-restoreMedia';
  static const deleteMedia = 'mediaFns-deleteMedia';
}

class FirestoreMediaRepository implements MediaRepository {
  FirestoreMediaRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required FirebaseStorage storage,
  }) : _firestore = firestore,
       _functions = functions,
       _storage = storage;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;

  @override
  Stream<MediaUploadEvent> upload(
    MediaUploadRequest request, {
    required String actorId,
  }) {
    final controller = StreamController<MediaUploadEvent>();
    unawaited(_runUpload(request, actorId, controller));
    return controller.stream;
  }

  Future<void> _runUpload(
    MediaUploadRequest request,
    String actorId,
    StreamController<MediaUploadEvent> controller,
  ) async {
    final mediaId = _firestore.collection('media').doc().id;
    final extension = request.fileName.contains('.')
        ? request.fileName.split('.').last
        : 'bin';
    final ref = _storage.ref('private/media/$mediaId/original.$extension');

    try {
      final uploadTask = ref.putData(
        request.bytes,
        SettableMetadata(
          contentType: request.mimeType,
          customMetadata: {
            'title': request.title,
            'altText': request.altText,
            'description': request.description,
            'uploadedBy': actorId,
          },
        ),
      );

      final progressSubscription = uploadTask.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          controller.add(
            MediaUploadProgress(
              snapshot.bytesTransferred / snapshot.totalBytes,
            ),
          );
        }
      });

      await uploadTask;
      await progressSubscription.cancel();
      controller.add(MediaUploadTransferComplete(mediaId));
    } catch (_) {
      controller.add(
        const MediaUploadFinished(core.Result.failure(MediaUploadFailure())),
      );
      await controller.close();
      return;
    }

    // The byte transfer is done; wait for
    // functions/src/media/onMediaUploaded.ts to finish processing
    // (Processing -> Ready/Failed) by listening to the same doc the
    // trigger writes to.
    late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
    processingSubscription;
    processingSubscription = _firestore
        .collection('media')
        .doc(mediaId)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) return;
          final asset = MediaAssetMapper.fromSnapshot(snapshot);
          if (asset.status == MediaStatus.ready) {
            controller.add(MediaUploadFinished(core.Result.ok(asset)));
            processingSubscription.cancel();
            controller.close();
          } else if (asset.status == MediaStatus.failed) {
            controller.add(
              MediaUploadFinished(
                core.Result.failure(
                  MediaUploadFailure(
                    asset.failureReason ?? 'Processing failed.',
                  ),
                ),
              ),
            );
            processingSubscription.cancel();
            controller.close();
          }
        });
  }

  @override
  Future<core.Result<MediaAsset>> get(String mediaId) async {
    try {
      final snapshot = await _firestore.collection('media').doc(mediaId).get();
      if (!snapshot.exists) {
        return const core.Result.failure(MediaNotFoundFailure());
      }
      return core.Result.ok(MediaAssetMapper.fromSnapshot(snapshot));
    } on FirebaseException catch (e) {
      return core.Result.failure(
        core.ValidationFailure(e.message ?? 'Failed to load media asset.'),
      );
    }
  }

  @override
  Stream<core.Result<MediaAsset>> observe(String mediaId) {
    return _firestore.collection('media').doc(mediaId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) {
        return const core.Result.failure(MediaNotFoundFailure());
      }
      return core.Result.ok(MediaAssetMapper.fromSnapshot(snapshot));
    });
  }

  @override
  Future<core.Result<core.Page<MediaAsset>>> list({
    MediaFilter query = const MediaFilter(),
    core.PageRequest request = const core.PageRequest(),
  }) async {
    try {
      // `archived` is a real Firestore equality filter, not a client-side
      // pass — filtering an already-fetched page client-side would make
      // `hasMore`/pagination wrong whenever a page's results were mostly
      // the *other* archived state (e.g. a page of 20 could yield zero
      // matching items despite more existing beyond the cursor). See
      // firebase/firestoreIndexes.json for the composite indexes this
      // requires: (mimeCategory, archived, uploadedAt) for a type-
      // filtered list, (archived, uploadedAt) for "all types".
      Query<Map<String, dynamic>> firestoreQuery = _firestore
          .collection('media')
          .where('archived', isEqualTo: query.includeArchived);
      if (query.category != null) {
        firestoreQuery = firestoreQuery.where(
          'mimeCategory',
          isEqualTo: query.category!.storageValue,
        );
      }
      firestoreQuery = firestoreQuery
          .orderBy('uploadedAt', descending: true)
          .limit(request.limit);

      if (request.cursor != null) {
        final cursorDoc = await _firestore
            .collection('media')
            .doc(request.cursor)
            .get();
        if (cursorDoc.exists) {
          firestoreQuery = firestoreQuery.startAfterDocument(cursorDoc);
        }
      }

      final snapshot = await firestoreQuery.get();
      var assets = snapshot.docs.map(MediaAssetMapper.fromSnapshot).toList();

      // searchText remains a client-side substring match on this one
      // page's results — the same pragmatic approach
      // FirestorePagesRepository already uses for title search; a real
      // full-text index is out of scope for a Phase 1 library.
      final search = query.searchText?.trim().toLowerCase();
      if (search != null && search.isNotEmpty) {
        assets = assets
            .where(
              (a) =>
                  a.title.toLowerCase().contains(search) ||
                  a.fileName.toLowerCase().contains(search),
            )
            .toList();
      }

      return core.Result.ok(
        core.Page(
          items: assets,
          nextCursor: snapshot.docs.isEmpty ? null : snapshot.docs.last.id,
          hasMore: snapshot.docs.length == request.limit,
        ),
      );
    } on FirebaseException catch (e) {
      return core.Result.failure(
        core.ValidationFailure(e.message ?? 'Failed to load media.'),
      );
    }
  }

  @override
  Future<core.Result<MediaAsset>> updateMetadata({
    required String mediaId,
    required String title,
    required String altText,
    String description = '',
  }) async {
    try {
      await _functions
          .httpsCallable(_MediaCallables.updateMediaMetadata)
          .call<Map<String, dynamic>>({
            'mediaId': mediaId,
            'title': title,
            'altText': altText,
            'description': description,
          });
      return get(mediaId);
    } on FirebaseFunctionsException catch (e) {
      return core.Result.failure(MediaFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<core.Result<void>> archive(String mediaId) =>
      _runVoidCallable(_MediaCallables.archiveMedia, {'mediaId': mediaId});

  @override
  Future<core.Result<void>> restore(String mediaId) =>
      _runVoidCallable(_MediaCallables.restoreMedia, {'mediaId': mediaId});

  @override
  Future<core.Result<void>> delete(String mediaId) =>
      _runVoidCallable(_MediaCallables.deleteMedia, {'mediaId': mediaId});

  Future<core.Result<void>> _runVoidCallable(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      await _functions.httpsCallable(name).call<Map<String, dynamic>>(data);
      return const core.Result.ok(null);
    } on FirebaseFunctionsException catch (e) {
      return core.Result.failure(MediaFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<core.Result<List<MediaUsageReference>>> listUsages(
    String mediaId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('mediaUsages')
          .where('mediaId', isEqualTo: mediaId)
          .get();
      return core.Result.ok(
        snapshot.docs
            .map((d) => MediaUsageReferenceMapper.fromSnapshot(d))
            .toList(),
      );
    } on FirebaseException catch (e) {
      return core.Result.failure(
        core.ValidationFailure(e.message ?? 'Failed to load usage references.'),
      );
    }
  }
}
