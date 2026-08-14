import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_media_repository.dart';
import '../../support/sample_media_asset.dart';

void main() {
  late FakeMediaRepository repository;
  late UpdateMediaMetadataUseCase useCase;

  setUp(() {
    repository = FakeMediaRepository();
    useCase = UpdateMediaMetadataUseCase(repository);
  });

  test('fails with MediaNotEditableFailure while still processing', () async {
    final asset = sampleMediaAsset(status: MediaStatus.processing);
    final result = await useCase(
      currentAsset: asset,
      title: 'New title',
      altText: 'New alt',
      actingRole: UserRole.publisher,
      actorId: 'p1',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<MediaNotEditableFailure>()),
    );
    expect(repository.lastUpdateMediaId, isNull);
  });

  test('fails with PermissionFailure for a non-owner Editor', () async {
    final asset = sampleMediaAsset(uploadedBy: 'owner-1');
    final result = await useCase(
      currentAsset: asset,
      title: 'New title',
      altText: 'New alt',
      actingRole: UserRole.editor,
      actorId: 'editor-2',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<PermissionFailure>()),
    );
    expect(repository.lastUpdateMediaId, isNull);
  });

  test('allows the owning Editor to update their own asset', () async {
    final asset = sampleMediaAsset(mediaId: 'm1', uploadedBy: 'owner-1');
    repository.updateMetadataResponse = Result.ok(asset);
    final result = await useCase(
      currentAsset: asset,
      title: 'New title',
      altText: 'New alt',
      actingRole: UserRole.editor,
      actorId: 'owner-1',
    );
    expect(result.isOk, isTrue);
    expect(repository.lastUpdateMediaId, 'm1');
    expect(repository.lastUpdateTitle, 'New title');
  });

  test('allows a Publisher to edit an asset they do not own', () async {
    final asset = sampleMediaAsset(mediaId: 'm1', uploadedBy: 'owner-1');
    repository.updateMetadataResponse = Result.ok(asset);
    final result = await useCase(
      currentAsset: asset,
      title: 'New title',
      altText: 'New alt',
      actingRole: UserRole.publisher,
      actorId: 'publisher-1',
    );
    expect(result.isOk, isTrue);
  });

  test('fails with ValidationFailure for a blank title', () async {
    final asset = sampleMediaAsset(uploadedBy: 'owner-1');
    final result = await useCase(
      currentAsset: asset,
      title: '',
      altText: 'New alt',
      actingRole: UserRole.publisher,
      actorId: 'publisher-1',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<ValidationFailure>()),
    );
  });

  test('fails with ValidationFailure for blank alt text', () async {
    final asset = sampleMediaAsset(uploadedBy: 'owner-1');
    final result = await useCase(
      currentAsset: asset,
      title: 'Title',
      altText: '',
      actingRole: UserRole.publisher,
      actorId: 'publisher-1',
    );
    result.fold(
      (_) => fail('expected failure'),
      (f) => expect(f, isA<ValidationFailure>()),
    );
  });
}
