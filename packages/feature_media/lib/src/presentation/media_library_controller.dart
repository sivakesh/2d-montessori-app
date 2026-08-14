import 'package:core_contracts/core_contracts.dart';
import 'package:flutter/foundation.dart';

import '../domain/media_asset.dart';
import '../domain/media_repository.dart';
import '../domain/media_upload_event.dart';
import '../domain/media_upload_request.dart';
import '../domain/media_usage_reference.dart';
import '../domain/use_cases/archive_media_use_case.dart';
import '../domain/use_cases/delete_media_use_case.dart';
import '../domain/use_cases/list_media_use_case.dart';
import '../domain/use_cases/update_media_metadata_use_case.dart';
import '../domain/use_cases/upload_media_use_case.dart';

/// Drives the Media Library screen (SRS MED-01..MED-06): the current
/// asset list/filter, upload lifecycle (progress -> processing ->
/// ready/failed, SRS "Clear upload progress, success and failure
/// feedback"), and every management action. The client never decides
/// whether an action is *allowed* beyond hiding controls for UX — every
/// use case's Cloud Functions callable (or, for upload, `storage.rules`)
/// re-validates authoritatively, the same trust boundary
/// `PageEditorController` already establishes for Pages.
class MediaLibraryController extends ChangeNotifier {
  MediaLibraryController({
    required MediaRepository repository,
    required this.actingRole,
    required this.actorId,
  }) : _repository = repository {
    _uploadUseCase = UploadMediaUseCase(_repository);
    _listUseCase = ListMediaUseCase(_repository);
    _updateMetadataUseCase = UpdateMediaMetadataUseCase(_repository);
    _archiveUseCase = ArchiveMediaUseCase(_repository);
    _restoreUseCase = RestoreMediaUseCase(_repository);
    _deleteUseCase = DeleteMediaUseCase(_repository);
    _listUsagesUseCase = ListMediaUsagesUseCase(_repository);
  }

  final MediaRepository _repository;
  final UserRole actingRole;
  final String actorId;

  late final UploadMediaUseCase _uploadUseCase;
  late final ListMediaUseCase _listUseCase;
  late final UpdateMediaMetadataUseCase _updateMetadataUseCase;
  late final ArchiveMediaUseCase _archiveUseCase;
  late final RestoreMediaUseCase _restoreUseCase;
  late final DeleteMediaUseCase _deleteUseCase;
  late final ListMediaUsagesUseCase _listUsagesUseCase;

  List<MediaAsset> assets = const [];
  bool isBusy = false;
  String? lastErrorMessage;
  MediaFilter currentQuery = const MediaFilter();

  /// `null` when no upload is in progress; 0.0..1.0 during the raw byte
  /// transfer; `null` again (with [uploadStatusMessage] describing the
  /// outcome) once processing finishes.
  double? uploadProgress;
  String? uploadStatusMessage;

  bool get canManageAllMedia =>
      RolePermissionMatrix.hasFull(actingRole, Capability.manageMediaLibrary);

  bool canManageAsset(MediaAsset asset) =>
      canManageAllMedia || asset.uploadedBy == actorId;

  Future<bool> loadAssets({MediaFilter? query}) => _run(() async {
    if (query != null) currentQuery = query;
    final result = await _listUseCase(query: currentQuery);
    return result.fold(
      (page) {
        assets = page.items;
        return true;
      },
      (failure) {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  /// Streams the whole upload lifecycle, updating [uploadProgress]/
  /// [uploadStatusMessage] as it goes, and prepends the finished asset to
  /// [assets] on success. Does not throw — failures land in
  /// [lastErrorMessage], same as every other action here.
  Future<void> uploadFile(MediaUploadRequest request) async {
    uploadProgress = 0;
    uploadStatusMessage = 'Uploading…';
    lastErrorMessage = null;
    notifyListeners();

    await for (final event in _uploadUseCase(
      request: request,
      actingRole: actingRole,
      actorId: actorId,
    )) {
      switch (event) {
        case MediaUploadProgress(:final fraction):
          uploadProgress = fraction;
          notifyListeners();
        case MediaUploadTransferComplete():
          uploadProgress = null;
          uploadStatusMessage = 'Processing…';
          notifyListeners();
        case MediaUploadFinished(:final result):
          uploadProgress = null;
          result.fold(
            (asset) {
              uploadStatusMessage = 'Upload complete.';
              assets = [asset, ...assets];
            },
            (failure) {
              uploadStatusMessage = null;
              lastErrorMessage = failure.message;
            },
          );
          notifyListeners();
      }
    }
  }

  Future<bool> updateMetadata(
    MediaAsset asset, {
    required String title,
    required String altText,
    String description = '',
  }) => _run(() async {
    final result = await _updateMetadataUseCase(
      currentAsset: asset,
      title: title,
      altText: altText,
      description: description,
      actingRole: actingRole,
      actorId: actorId,
    );
    return result.fold(
      (updated) {
        assets = [
          for (final a in assets) a.mediaId == updated.mediaId ? updated : a,
        ];
        return true;
      },
      (failure) {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  Future<bool> archive(MediaAsset asset) => _mutateAsset(
    asset,
    (a) => _archiveUseCase(
      currentAsset: a,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> restore(MediaAsset asset) => _mutateAsset(
    asset,
    (a) => _restoreUseCase(
      currentAsset: a,
      actingRole: actingRole,
      actorId: actorId,
    ),
  );

  Future<bool> delete(MediaAsset asset) => _run(() async {
    final result = await _deleteUseCase(
      currentAsset: asset,
      actingRole: actingRole,
      actorId: actorId,
    );
    return result.fold(
      (_) {
        assets = assets.where((a) => a.mediaId != asset.mediaId).toList();
        return true;
      },
      (failure) {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  Future<List<MediaUsageReference>> loadUsages(String mediaId) async {
    final result = await _listUsagesUseCase(mediaId);
    return result.fold((usages) => usages, (_) => const []);
  }

  Future<bool> _mutateAsset(
    MediaAsset asset,
    Future<Result<void>> Function(MediaAsset) action,
  ) => _run(() async {
    final result = await action(asset);
    return result.fold(
      (_) async {
        await loadAssets();
        return true;
      },
      (failure) async {
        lastErrorMessage = failure.message;
        return false;
      },
    );
  });

  Future<bool> _run(Future<bool> Function() body) async {
    isBusy = true;
    lastErrorMessage = null;
    notifyListeners();
    try {
      return await body();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
