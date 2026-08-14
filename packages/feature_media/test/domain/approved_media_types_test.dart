import 'package:feature_media/feature_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('approvedMediaTypeFor', () {
    test('recognizes every approved image/video/document MIME type', () {
      expect(
        approvedMediaTypeFor('image/png')?.category,
        MediaMimeCategory.image,
      );
      expect(
        approvedMediaTypeFor('video/mp4')?.category,
        MediaMimeCategory.video,
      );
      expect(
        approvedMediaTypeFor('application/pdf')?.category,
        MediaMimeCategory.document,
      );
    });

    test('returns null for an unapproved MIME type', () {
      expect(approvedMediaTypeFor('application/x-msdownload'), isNull);
      expect(approvedMediaTypeFor(''), isNull);
    });

    test('image size limit is 10MB', () {
      expect(
        approvedMediaTypeFor('image/jpeg')?.maxSizeBytes,
        10 * 1024 * 1024,
      );
    });
  });
}
