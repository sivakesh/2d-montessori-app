import 'cms_page.dart';
import 'page_section.dart';
import 'slug_format.dart';

/// SRS CMS-08: "Publishing checks required fields, alt text, ... links,
/// SEO metadata, unique slug, logical schedules/expiry, ... and media
/// readiness. Errors block." This is the *client-side* half of that
/// check — defense-in-depth/UX only, exactly like
/// `feature_publishing.TransitionContentUseCase`'s client-side checks.
/// The Cloud Functions callable behind `submitForReview`/`publish`/
/// `schedule` (`functions/src/pages/completeness.ts`) re-implements the
/// same rules server-side, which is the actual authority — this class
/// exists so the admin editor can show every problem before a round trip,
/// not to be trusted on its own.
///
/// Slug *uniqueness* (as opposed to slug *format*) is deliberately not
/// checked here — it requires a Firestore query only the server can
/// authoritatively answer at the moment of submission (see
/// `SlugConflictFailure`), so it is server-only.
abstract final class PageCompletenessValidator {
  /// Returns a list of human-readable problems; an empty list means the
  /// page is ready to submit for review, publish, or schedule.
  static List<String> validate(CmsPage page) {
    final violations = <String>[];

    if (page.title.trim().isEmpty) {
      violations.add('Title is required.');
    }
    if (page.slug.trim().isEmpty) {
      violations.add('A URL slug is required.');
    } else if (!isValidSlugFormat(page.slug)) {
      violations.add(
        'The URL slug must be lowercase letters, numbers and hyphens only.',
      );
    }
    if (page.summary.trim().isEmpty) {
      violations.add('A short summary is required.');
    }
    if (page.sections.isEmpty) {
      violations.add('At least one section is required.');
    }
    if ((page.seo.title ?? '').trim().isEmpty) {
      violations.add('An SEO title is required.');
    }
    if ((page.seo.metaDescription ?? '').trim().isEmpty) {
      violations.add('A meta description is required.');
    }
    if (page.featuredImage != null &&
        page.featuredImage!.altText.trim().isEmpty) {
      violations.add('The featured image needs alternative text.');
    }

    for (final section in page.sections) {
      violations.addAll(_validateSection(section));
    }

    return violations;
  }

  static List<String> _validateSection(PageSection section) {
    final violations = <String>[];
    switch (section) {
      case RichTextSection(:final body):
        if (body.trim().isEmpty) {
          violations.add('A rich-text section has no content.');
        }
      case ImageSection(:final image):
        if (image.altText.trim().isEmpty) {
          violations.add('An image section is missing alternative text.');
        }
      case ImageTextSection(:final image, :final body):
        if (image.altText.trim().isEmpty) {
          violations.add(
            'An image-and-text section is missing alternative text.',
          );
        }
        if (body.trim().isEmpty) {
          violations.add('An image-and-text section has no body text.');
        }
      case CtaSection(:final primaryCta):
        if (primaryCta.label.trim().isEmpty ||
            primaryCta.target.trim().isEmpty) {
          violations.add(
            'A call-to-action section needs a label and a destination.',
          );
        }
      case HighlightsSection(:final cards):
        if (cards.isEmpty) {
          violations.add('A highlights section needs at least one card.');
        }
      case FaqSection(:final items):
        if (items.isEmpty) {
          violations.add('An FAQ section needs at least one question.');
        } else if (items.any(
          (i) => i.question.trim().isEmpty || i.answer.trim().isEmpty,
        )) {
          violations.add('Every FAQ item needs both a question and an answer.');
        }
      case GallerySection(:final items):
        if (items.isEmpty) {
          violations.add('A gallery section needs at least one image.');
        } else if (items.any((m) => m.altText.trim().isEmpty)) {
          violations.add('Every gallery image needs alternative text.');
        }
      case TestimonialSection(:final items):
        if (items.isEmpty) {
          violations.add('A testimonial section needs at least one entry.');
        } else if (items.any((t) => t.quote.trim().isEmpty)) {
          violations.add('Every testimonial needs quote text.');
        }
      case RelatedContentSection(:final relatedPageIds):
        if (relatedPageIds.isEmpty) {
          violations.add(
            'A related-content section needs at least one selection.',
          );
        }
    }
    return violations;
  }
}
