import 'package:feature_pages/feature_pages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sample_page.dart';

void main() {
  group('PageCompletenessValidator', () {
    test('a fully-filled page with one valid section has no violations', () {
      final page = samplePage(
        sections: [
          const RichTextSection(id: 's1', sortOrder: 0, body: 'Hello world.'),
        ],
      );
      expect(PageCompletenessValidator.validate(page), isEmpty);
    });

    test('flags a missing title, slug, summary, sections and SEO fields', () {
      final page = samplePage(
        title: '',
        slug: '',
        summary: '',
        seo: const SeoMetadata(),
      );
      final violations = PageCompletenessValidator.validate(page);
      expect(violations, contains('Title is required.'));
      expect(violations, contains('A URL slug is required.'));
      expect(violations, contains('A short summary is required.'));
      expect(violations, contains('At least one section is required.'));
      expect(violations, contains('An SEO title is required.'));
      expect(violations, contains('A meta description is required.'));
    });

    test('flags an invalid slug format', () {
      final page = samplePage(slug: 'Not A Valid Slug!');
      expect(
        PageCompletenessValidator.validate(page),
        contains(
          'The URL slug must be lowercase letters, numbers and hyphens only.',
        ),
      );
    });

    test('flags a featured image with no alt text', () {
      final page = samplePage(
        featuredImage: const MediaReference(
          url: 'https://example.test/x.png',
          altText: '',
        ),
      );
      expect(
        PageCompletenessValidator.validate(page),
        contains('The featured image needs alternative text.'),
      );
    });

    test('flags an image section missing alt text', () {
      final page = samplePage(
        sections: [
          ImageSection(
            id: 's1',
            sortOrder: 0,
            image: const MediaReference(
              url: 'https://x.test/a.png',
              altText: '',
            ),
          ),
        ],
      );
      expect(
        PageCompletenessValidator.validate(page),
        contains('An image section is missing alternative text.'),
      );
    });

    test('flags an image-and-text section missing alt text or body', () {
      final page = samplePage(
        sections: [
          ImageTextSection(
            id: 's1',
            sortOrder: 0,
            body: '',
            image: const MediaReference(
              url: 'https://x.test/a.png',
              altText: '',
            ),
          ),
        ],
      );
      final violations = PageCompletenessValidator.validate(page);
      expect(
        violations,
        contains('An image-and-text section is missing alternative text.'),
      );
      expect(
        violations,
        contains('An image-and-text section has no body text.'),
      );
    });

    test('flags a CTA section with no label or destination', () {
      final page = samplePage(
        sections: [
          const CtaSection(
            id: 's1',
            sortOrder: 0,
            primaryCta: CallToAction(
              label: '',
              linkType: CallToActionLinkType.internal,
              target: '',
            ),
          ),
        ],
      );
      expect(
        PageCompletenessValidator.validate(page),
        contains('A call-to-action section needs a label and a destination.'),
      );
    });

    test('flags an empty highlights section', () {
      final page = samplePage(
        sections: [const HighlightsSection(id: 's1', sortOrder: 0, cards: [])],
      );
      expect(
        PageCompletenessValidator.validate(page),
        contains('A highlights section needs at least one card.'),
      );
    });

    test('flags an FAQ section with no items or an incomplete item', () {
      final empty = samplePage(
        sections: [const FaqSection(id: 's1', sortOrder: 0, items: [])],
      );
      expect(
        PageCompletenessValidator.validate(empty),
        contains('An FAQ section needs at least one question.'),
      );

      final incomplete = samplePage(
        sections: [
          const FaqSection(
            id: 's1',
            sortOrder: 0,
            items: [FaqItem(question: 'Q?', answer: '')],
          ),
        ],
      );
      expect(
        PageCompletenessValidator.validate(incomplete),
        contains('Every FAQ item needs both a question and an answer.'),
      );
    });

    test('flags a gallery section with no items or missing alt text', () {
      final empty = samplePage(
        sections: [const GallerySection(id: 's1', sortOrder: 0, items: [])],
      );
      expect(
        PageCompletenessValidator.validate(empty),
        contains('A gallery section needs at least one image.'),
      );

      final missingAlt = samplePage(
        sections: [
          const GallerySection(
            id: 's1',
            sortOrder: 0,
            items: [MediaReference(url: 'https://x.test/a.png', altText: '')],
          ),
        ],
      );
      expect(
        PageCompletenessValidator.validate(missingAlt),
        contains('Every gallery image needs alternative text.'),
      );
    });

    test('flags a testimonial section with no items or an empty quote', () {
      final empty = samplePage(
        sections: [const TestimonialSection(id: 's1', sortOrder: 0, items: [])],
      );
      expect(
        PageCompletenessValidator.validate(empty),
        contains('A testimonial section needs at least one entry.'),
      );

      final blankQuote = samplePage(
        sections: [
          const TestimonialSection(
            id: 's1',
            sortOrder: 0,
            items: [TestimonialEntry(quote: '')],
          ),
        ],
      );
      expect(
        PageCompletenessValidator.validate(blankQuote),
        contains('Every testimonial needs quote text.'),
      );
    });

    test('flags a related-content section with no selections', () {
      final page = samplePage(
        sections: [
          const RelatedContentSection(
            id: 's1',
            sortOrder: 0,
            relatedPageIds: [],
          ),
        ],
      );
      expect(
        PageCompletenessValidator.validate(page),
        contains('A related-content section needs at least one selection.'),
      );
    });

    test('flags a rich-text section with no body', () {
      final page = samplePage(
        sections: [const RichTextSection(id: 's1', sortOrder: 0, body: '   ')],
      );
      expect(
        PageCompletenessValidator.validate(page),
        contains('A rich-text section has no content.'),
      );
    });
  });
}
