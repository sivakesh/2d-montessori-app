import 'package:feature_pages/feature_pages.dart';
import 'package:feature_publishing/feature_publishing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sample_page.dart';

void main() {
  group('CmsPage.toPublishingRecord', () {
    test(
      'carries the envelope fields across unchanged, with contentType "page"',
      () {
        final page = samplePage(
          pageId: 'p1',
          title: 'About',
          status: PublishingStatus.inReview,
          ownerId: 'owner-9',
        );
        final record = page.toPublishingRecord();

        expect(record.contentId, 'p1');
        expect(record.contentType, 'page');
        expect(record.title, 'About');
        expect(record.status, PublishingStatus.inReview);
        expect(record.ownerId, 'owner-9');
        expect(record.createdAt, page.createdAt);
        expect(record.updatedAt, page.updatedAt);
      },
    );
  });

  group('CmsPage.copyWith', () {
    test('updates only the requested fields', () {
      final page = samplePage(title: 'Old title', slug: 'old-slug');
      final updated = page.copyWith(title: 'New title');

      expect(updated.title, 'New title');
      expect(updated.slug, 'old-slug');
      expect(updated.pageId, page.pageId);
    });

    test(
      'clearScheduledAt actually clears scheduledAt even though scheduledAt is not passed',
      () {
        final page = samplePage().copyWith(scheduledAt: DateTime(2026, 6, 1));
        expect(page.scheduledAt, isNotNull);

        final cleared = page.copyWith(clearScheduledAt: true);
        expect(cleared.scheduledAt, isNull);
      },
    );

    test('clearFeaturedImage actually clears featuredImage', () {
      final page = samplePage(
        featuredImage: const MediaReference(
          url: 'https://x.test/a.png',
          altText: 'Alt',
        ),
      );
      expect(page.featuredImage, isNotNull);

      final cleared = page.copyWith(clearFeaturedImage: true);
      expect(cleared.featuredImage, isNull);
    });
  });
}
