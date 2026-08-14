import 'dart:typed_data';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_media_repository.dart';
import '../support/sample_media_asset.dart';

void main() {
  late FakeMediaRepository repository;
  late MediaLibraryController controller;

  setUp(() {
    repository = FakeMediaRepository();
    controller = MediaLibraryController(
      repository: repository,
      actingRole: UserRole.publisher,
      actorId: 'publisher-1',
    );
  });

  tearDown(() => controller.dispose());

  test('loadAssets populates assets on success', () async {
    final asset = sampleMediaAsset(mediaId: 'm1');
    repository.listResponse = Result.ok(
      Page(items: [asset], nextCursor: null, hasMore: false),
    );

    final ok = await controller.loadAssets();

    expect(ok, isTrue);
    expect(controller.assets, [asset]);
  });

  test('loadAssets records the failure message on error', () async {
    repository.listResponse = const Result.failure(ValidationFailure('boom'));

    final ok = await controller.loadAssets();

    expect(ok, isFalse);
    expect(controller.lastErrorMessage, 'boom');
  });

  test(
    'uploadFile drives progress -> processing -> ready and prepends the new asset',
    () async {
      final asset = sampleMediaAsset(mediaId: 'm1');
      repository.uploadResponse = Stream.fromIterable([
        const MediaUploadProgress(0.5),
        const MediaUploadTransferComplete('m1'),
        MediaUploadFinished(Result.ok(asset)),
      ]);

      await controller.uploadFile(
        MediaUploadRequest(
          bytes: Uint8List(4),
          fileName: 'logo.png',
          mimeType: 'image/png',
          title: 'Logo',
          altText: 'The school logo',
        ),
      );

      expect(controller.uploadProgress, isNull);
      expect(controller.assets, [asset]);
      expect(controller.lastErrorMessage, isNull);
    },
  );

  test('uploadFile records a failure without adding an asset', () async {
    repository.uploadResponse = Stream.value(
      const MediaUploadFinished(
        Result.failure(MediaUploadFailure('Upload rejected')),
      ),
    );

    await controller.uploadFile(
      MediaUploadRequest(
        bytes: Uint8List(4),
        fileName: 'logo.png',
        mimeType: 'image/png',
        title: 'Logo',
        altText: 'The school logo',
      ),
    );

    expect(controller.assets, isEmpty);
    expect(controller.lastErrorMessage, 'Upload rejected');
  });

  test('canManageAsset is true for Publisher regardless of owner', () {
    final asset = sampleMediaAsset(uploadedBy: 'someone-else');
    expect(controller.canManageAsset(asset), isTrue);
  });

  test('canManageAsset for an Editor is limited to their own uploads', () {
    final editorController = MediaLibraryController(
      repository: repository,
      actingRole: UserRole.editor,
      actorId: 'editor-1',
    );
    expect(
      editorController.canManageAsset(sampleMediaAsset(uploadedBy: 'editor-1')),
      isTrue,
    );
    expect(
      editorController.canManageAsset(
        sampleMediaAsset(uploadedBy: 'someone-else'),
      ),
      isFalse,
    );
    editorController.dispose();
  });

  test('archive reloads the asset list on success', () async {
    final asset = sampleMediaAsset(mediaId: 'm1', uploadedBy: 'publisher-1');
    repository.listResponse = Result.ok(
      Page(
        items: [asset.copyWith(archived: true)],
        nextCursor: null,
        hasMore: false,
      ),
    );

    final ok = await controller.archive(asset);

    expect(ok, isTrue);
    expect(repository.lastArchivedMediaId, 'm1');
  });

  test('delete removes the asset from the local list on success', () async {
    final asset = sampleMediaAsset(mediaId: 'm1', archived: true);
    controller.assets = [asset];

    final ok = await controller.delete(asset);

    expect(ok, isTrue);
    expect(controller.assets, isEmpty);
  });

  test(
    'delete keeps the asset and records the failure on protection error',
    () async {
      final asset = sampleMediaAsset(mediaId: 'm1', archived: true);
      controller.assets = [asset];
      repository.deleteResponse = const Result.failure(MediaInUseFailure());

      final ok = await controller.delete(asset);

      expect(ok, isFalse);
      expect(controller.assets, [asset]);
      expect(controller.lastErrorMessage, isNotNull);
    },
  );
}
