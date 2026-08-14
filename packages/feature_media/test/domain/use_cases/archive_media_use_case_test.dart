import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_media_repository.dart';
import '../../support/sample_media_asset.dart';

void main() {
  late FakeMediaRepository repository;
  late ArchiveMediaUseCase archiveUseCase;
  late RestoreMediaUseCase restoreUseCase;

  setUp(() {
    repository = FakeMediaRepository();
    archiveUseCase = ArchiveMediaUseCase(repository);
    restoreUseCase = RestoreMediaUseCase(repository);
  });

  group('ArchiveMediaUseCase', () {
    test('fails with PermissionFailure for a non-owner Editor', () async {
      final asset = sampleMediaAsset(uploadedBy: 'owner-1');
      final result = await archiveUseCase(
        currentAsset: asset,
        actingRole: UserRole.editor,
        actorId: 'editor-2',
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<PermissionFailure>()),
      );
      expect(repository.lastArchivedMediaId, isNull);
    });

    test('allows the owning Editor to archive their own upload', () async {
      final asset = sampleMediaAsset(mediaId: 'm1', uploadedBy: 'owner-1');
      final result = await archiveUseCase(
        currentAsset: asset,
        actingRole: UserRole.editor,
        actorId: 'owner-1',
      );
      expect(result.isOk, isTrue);
      expect(repository.lastArchivedMediaId, 'm1');
    });

    test('allows a Super Admin to archive any upload', () async {
      final asset = sampleMediaAsset(mediaId: 'm1', uploadedBy: 'owner-1');
      final result = await archiveUseCase(
        currentAsset: asset,
        actingRole: UserRole.superAdmin,
        actorId: 'admin-1',
      );
      expect(result.isOk, isTrue);
    });
  });

  group('RestoreMediaUseCase', () {
    test('fails with PermissionFailure for a non-owner Editor', () async {
      final asset = sampleMediaAsset(uploadedBy: 'owner-1', archived: true);
      final result = await restoreUseCase(
        currentAsset: asset,
        actingRole: UserRole.editor,
        actorId: 'editor-2',
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<PermissionFailure>()),
      );
    });

    test('allows the owning Editor to restore their own upload', () async {
      final asset = sampleMediaAsset(
        mediaId: 'm1',
        uploadedBy: 'owner-1',
        archived: true,
      );
      final result = await restoreUseCase(
        currentAsset: asset,
        actingRole: UserRole.editor,
        actorId: 'owner-1',
      );
      expect(result.isOk, isTrue);
      expect(repository.lastRestoredMediaId, 'm1');
    });
  });
}
