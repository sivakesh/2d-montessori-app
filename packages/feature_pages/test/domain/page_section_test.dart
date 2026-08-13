import 'package:feature_pages/feature_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageSection toMap/fromMap round trip', () {
    test('RichTextSection', () {
      const section = RichTextSection(
        id: 's1',
        sortOrder: 0,
        heading: 'Welcome',
        body: 'Body text.',
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<RichTextSection>());
      expect((decoded as RichTextSection).heading, 'Welcome');
      expect(decoded.body, 'Body text.');
    });

    test('ImageSection', () {
      const section = ImageSection(
        id: 's1',
        sortOrder: 0,
        image: MediaReference(url: 'https://x.test/a.png', altText: 'A photo'),
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<ImageSection>());
      expect((decoded as ImageSection).image.altText, 'A photo');
    });

    test('ImageTextSection preserves imageSide', () {
      const section = ImageTextSection(
        id: 's1',
        sortOrder: 0,
        body: 'Body',
        image: MediaReference(url: 'https://x.test/a.png', altText: 'Alt'),
        imageSide: ImageSide.right,
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<ImageTextSection>());
      expect((decoded as ImageTextSection).imageSide, ImageSide.right);
    });

    test('CtaSection with a secondary action', () {
      const section = CtaSection(
        id: 's1',
        sortOrder: 0,
        primaryCta: CallToAction(
          label: 'Enquire',
          linkType: CallToActionLinkType.internal,
          target: '/contact',
        ),
        secondaryCta: CallToAction(
          label: 'Call',
          linkType: CallToActionLinkType.phone,
          target: 'tel:+911234567890',
        ),
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<CtaSection>());
      expect(
        (decoded as CtaSection).secondaryCta?.linkType,
        CallToActionLinkType.phone,
      );
    });

    test('HighlightsSection with cards', () {
      const section = HighlightsSection(
        id: 's1',
        sortOrder: 0,
        cards: [HighlightCard(title: 'Card 1', body: 'Body 1')],
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<HighlightsSection>());
      expect((decoded as HighlightsSection).cards, hasLength(1));
      expect(decoded.cards.first.title, 'Card 1');
    });

    test('FaqSection with items', () {
      const section = FaqSection(
        id: 's1',
        sortOrder: 0,
        items: [FaqItem(question: 'Q?', answer: 'A.')],
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<FaqSection>());
      expect((decoded as FaqSection).items.single.question, 'Q?');
    });

    test('GallerySection with items', () {
      const section = GallerySection(
        id: 's1',
        sortOrder: 0,
        items: [MediaReference(url: 'https://x.test/a.png', altText: 'Alt')],
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<GallerySection>());
      expect((decoded as GallerySection).items.single.altText, 'Alt');
    });

    test('TestimonialSection with items', () {
      const section = TestimonialSection(
        id: 's1',
        sortOrder: 0,
        items: [
          TestimonialEntry(quote: 'Great school!', attributionName: 'A parent'),
        ],
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<TestimonialSection>());
      expect(
        (decoded as TestimonialSection).items.single.attributionName,
        'A parent',
      );
    });

    test('RelatedContentSection with ids', () {
      const section = RelatedContentSection(
        id: 's1',
        sortOrder: 0,
        relatedPageIds: ['page-2', 'page-3'],
      );
      final decoded = pageSectionFromMap(section.toMap());
      expect(decoded, isA<RelatedContentSection>());
      expect((decoded as RelatedContentSection).relatedPageIds, [
        'page-2',
        'page-3',
      ]);
    });

    test('returns null for an unrecognized type', () {
      expect(pageSectionFromMap({'type': 'notARealType', 'id': 's1'}), isNull);
    });

    test(
      'copyWithBase updates sortOrder and isVisible without touching content',
      () {
        const section = RichTextSection(id: 's1', sortOrder: 0, body: 'Body');
        final moved = section.copyWithBase(sortOrder: 5, isVisible: false);
        expect(moved, isA<RichTextSection>());
        expect(moved.sortOrder, 5);
        expect(moved.isVisible, isFalse);
        expect(moved.body, 'Body');
      },
    );
  });
}
