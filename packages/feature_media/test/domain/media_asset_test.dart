import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sample_media_asset.dart';

void main() {
  group('MediaAsset.thumbnailVariant', () {
    test('returns null when there are no variants', () {
      expect(sampleMediaAsset().thumbnailVariant, isNull);
    });

    test('returns the narrowest variant', () {
      final asset = sampleMediaAsset(
        variants: const {
          'w1920': MediaVariant(
            storagePath: 'p',
            url: 'u1920',
            format: 'webp',
            width: 1920,
          ),
          'w320': MediaVariant(
            storagePath: 'p',
            url: 'u320',
            format: 'webp',
            width: 320,
          ),
          'w640': MediaVariant(
            storagePath: 'p',
            url: 'u640',
            format: 'webp',
            width: 640,
          ),
        },
      );
      expect(asset.thumbnailVariant?.url, 'u320');
    });
  });

  group('MediaAsset.largestVariant', () {
    test('returns null when there are no variants', () {
      expect(sampleMediaAsset().largestVariant, isNull);
    });

    test('returns the widest variant', () {
      final asset = sampleMediaAsset(
        variants: const {
          'w320': MediaVariant(
            storagePath: 'p',
            url: 'u320',
            format: 'webp',
            width: 320,
          ),
          'w1920': MediaVariant(
            storagePath: 'p',
            url: 'u1920',
            format: 'webp',
            width: 1920,
          ),
        },
      );
      expect(asset.largestVariant?.url, 'u1920');
    });

    test('treats a non-image passthrough variant (null width) as smallest', () {
      final asset = sampleMediaAsset(
        variants: const {
          'original': MediaVariant(
            storagePath: 'p',
            url: 'u-original',
            format: 'pdf',
          ),
        },
      );
      expect(asset.largestVariant?.url, 'u-original');
      expect(asset.thumbnailVariant?.url, 'u-original');
    });
  });

  group('MediaAsset.copyWith', () {
    test('overrides only the given fields, keeping everything else', () {
      final original = sampleMediaAsset(title: 'Original');
      final updated = original.copyWith(title: 'Updated', archived: true);
      expect(updated.title, 'Updated');
      expect(updated.archived, isTrue);
      expect(updated.mediaId, original.mediaId);
      expect(updated.altText, original.altText);
    });
  });

  group('MediaStatus.fromStorageValue', () {
    test('round-trips every status', () {
      for (final status in MediaStatus.values) {
        expect(MediaStatus.fromStorageValue(status.storageValue), status);
      }
    });

    test('returns null for an unknown value', () {
      expect(MediaStatus.fromStorageValue('bogus'), isNull);
      expect(MediaStatus.fromStorageValue(null), isNull);
    });
  });

  group('MediaMimeCategory / MediaOrientation fromStorageValue', () {
    test('round-trip every category and orientation', () {
      for (final category in MediaMimeCategory.values) {
        expect(
          MediaMimeCategory.fromStorageValue(category.storageValue),
          category,
        );
      }
      for (final orientation in MediaOrientation.values) {
        expect(
          MediaOrientation.fromStorageValue(orientation.storageValue),
          orientation,
        );
      }
    });
  });
}
