import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_media_repository.dart';
import '../../support/sample_media_asset.dart';

void main() {
  late FakeMediaRepository repository;
  late DeleteMediaUseCase useCase;

  setUp(() {
    repository = FakeMediaRepository();
    useCase = DeleteMediaUseCase(repository);
  });

  test('fails with PermissionFailure for a non-owner Editor', () async {
    final asset = sampleMediaAsset(uploadedBy: 'owner-1', archived: true);
    final result = await useCase(
      currentAsset: asset,
      actingRole: UserRole.editor,
      actorId: 'editor-2',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<PermissionFailure>()),
    );
    expect(repository.lastDeletedMediaId, isNull);
  });

  test(
    'fails with MediaNotArchivedFailure — permanent delete requires archiving first (SRS recycle-bin behaviour)',
    () async {
      final asset = sampleMediaAsset(uploadedBy: 'owner-1', archived: false);
      final result = await useCase(
        currentAsset: asset,
        actingRole: UserRole.superAdmin,
        actorId: 'admin-1',
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<MediaNotArchivedFailure>()),
      );
      expect(repository.lastDeletedMediaId, isNull);
    },
  );

  test(
    'fails with MediaInUseFailure when the asset is still referenced by a page (SRS deletion protection)',
    () async {
      final asset = sampleMediaAsset(
        uploadedBy: 'owner-1',
        archived: true,
        usageCount: 1,
      );
      final result = await useCase(
        currentAsset: asset,
        actingRole: UserRole.superAdmin,
        actorId: 'admin-1',
      );
      result.fold(
        (_) => fail('expected failure'),
        (f) => expect(f, isA<MediaInUseFailure>()),
      );
      expect(repository.lastDeletedMediaId, isNull);
    },
  );

  test(
    'permanently deletes an archived, unused asset the caller owns',
    () async {
      final asset = sampleMediaAsset(
        mediaId: 'm1',
        uploadedBy: 'owner-1',
        archived: true,
        usageCount: 0,
      );
      final result = await useCase(
        currentAsset: asset,
        actingRole: UserRole.editor,
        actorId: 'owner-1',
      );
      expect(result.isOk, isTrue);
      expect(repository.lastDeletedMediaId, 'm1');
    },
  );
}
