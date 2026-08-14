import 'package:core_contracts/core_contracts.dart';
import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_media_repository.dart';
import '../../support/sample_media_asset.dart';

void main() {
  test('GetMediaUseCase delegates to the repository', () async {
    final repository = FakeMediaRepository();
    final asset = sampleMediaAsset(mediaId: 'm1');
    repository.getResponse = Result.ok(asset);
    final useCase = GetMediaUseCase(repository);

    final result = await useCase('m1');

    expect(repository.lastGetMediaId, 'm1');
    expect(result.fold((a) => a.mediaId, (_) => null), 'm1');
  });

  test(
    'ListMediaUseCase delegates the filter and pagination request',
    () async {
      final repository = FakeMediaRepository();
      final useCase = ListMediaUseCase(repository);
      const filter = MediaFilter(category: MediaMimeCategory.image);

      await useCase(query: filter, request: const PageRequest(limit: 10));

      expect(repository.lastListQuery, filter);
    },
  );

  test('ListMediaUsagesUseCase delegates to the repository', () async {
    final repository = FakeMediaRepository();
    final useCase = ListMediaUsagesUseCase(repository);
    repository.listUsagesResponse = const Result.ok([
      MediaUsageReference(
        mediaId: 'm1',
        contentId: 'c1',
        contentTitle: 'About us',
        fieldPaths: ['featuredImage'],
      ),
    ]);

    final result = await useCase('m1');

    expect(result.fold((list) => list.length, (_) => -1), 1);
  });
}
