import 'package:meta/meta.dart';

import 'call_to_action.dart';
import 'media_reference.dart';

/// The complete, closed catalogue of section types an administrator may
/// add to a page — SRS's approved list ("Heading and rich-text content;
/// Image with accessible alt text; Image-and-text section; Call-to-action
/// section; Highlight/cards section; FAQ reference; Gallery/media
/// reference; Testimonial reference; Related-content selection"). This is
/// a subset of the PRD §4.2 template catalogue (which additionally lists
/// `hero`, `stats`, `quote`, `testimonial_carousel`, `video`,
/// `spacer_divider`, `contact_block`) — narrower on purpose, matching
/// exactly what this milestone was asked to build; the remaining PRD
/// templates are deferred, not silently dropped (see decisions.md).
enum PageSectionType {
  richText('richText'),
  image('image'),
  imageText('imageText'),
  cta('cta'),
  highlights('highlights'),
  faq('faq'),
  gallery('gallery'),
  testimonial('testimonial'),
  relatedContent('relatedContent');

  const PageSectionType(this.storageValue);

  final String storageValue;

  static PageSectionType? fromStorageValue(String? value) {
    for (final type in PageSectionType.values) {
      if (type.storageValue == value) return type;
    }
    return null;
  }
}

/// A single approved, typed content block within a page. `sealed` so
/// every renderer/validator switch is exhaustive and the compiler flags
/// any new variant that isn't handled everywhere — the enforcement
/// mechanism behind "stable, typed section models" and "no unrestricted
/// drag-and-drop builder": there is no generic/free-form section type an
/// administrator could use to smuggle in arbitrary markup, because there
/// is no code path that accepts one.
///
/// Every variant carries [id] (stable across edits — used for React-key-
/// style diffing and analytics, never regenerated), [sortOrder]
/// (canonical position within the page) and [isVisible] (hide without
/// deleting, per PRD §4.3). None of these types have an HTML/rich-markup
/// field anywhere — "rich text" in [RichTextSection.body] is validated,
/// stored plain multi-paragraph text (paragraph breaks only, no markup),
/// not executable HTML; see that class's doc comment.
@immutable
sealed class PageSection {
  const PageSection({
    required this.id,
    required this.sortOrder,
    this.isVisible = true,
  });

  final String id;
  final int sortOrder;
  final bool isVisible;

  PageSectionType get type;

  PageSection copyWithBase({int? sortOrder, bool? isVisible});

  Map<String, Object?> toMap();
}

/// SRS "Heading and rich-text content". [body] is plain text with blank
/// lines as paragraph separators — a deliberately minimal stand-in for a
/// full structured rich-text block model (bold/italic/lists), which is
/// out of scope for this milestone. No HTML is ever accepted or stored.
@immutable
final class RichTextSection extends PageSection {
  const RichTextSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    required this.body,
  });

  final String? heading;
  final String body;

  @override
  PageSectionType get type => PageSectionType.richText;

  @override
  RichTextSection copyWithBase({int? sortOrder, bool? isVisible}) =>
      RichTextSection(
        id: id,
        sortOrder: sortOrder ?? this.sortOrder,
        isVisible: isVisible ?? this.isVisible,
        heading: heading,
        body: body,
      );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'body': body,
  };
}

/// SRS "Image with accessible alt text".
@immutable
final class ImageSection extends PageSection {
  const ImageSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    required this.image,
  });

  final MediaReference image;

  @override
  PageSectionType get type => PageSectionType.image;

  @override
  ImageSection copyWithBase({int? sortOrder, bool? isVisible}) => ImageSection(
    id: id,
    sortOrder: sortOrder ?? this.sortOrder,
    isVisible: isVisible ?? this.isVisible,
    image: image,
  );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'image': image.toMap(),
  };
}

enum ImageSide { left, right }

/// SRS "Image-and-text section".
@immutable
final class ImageTextSection extends PageSection {
  const ImageTextSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    required this.body,
    required this.image,
    this.imageSide = ImageSide.left,
  });

  final String? heading;
  final String body;
  final MediaReference image;
  final ImageSide imageSide;

  @override
  PageSectionType get type => PageSectionType.imageText;

  @override
  ImageTextSection copyWithBase({int? sortOrder, bool? isVisible}) =>
      ImageTextSection(
        id: id,
        sortOrder: sortOrder ?? this.sortOrder,
        isVisible: isVisible ?? this.isVisible,
        heading: heading,
        body: body,
        image: image,
        imageSide: imageSide,
      );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'body': body,
    'image': image.toMap(),
    'imageSide': imageSide.name,
  };
}

/// SRS "Call-to-action section".
@immutable
final class CtaSection extends PageSection {
  const CtaSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    this.body,
    required this.primaryCta,
    this.secondaryCta,
  });

  final String? heading;
  final String? body;
  final CallToAction primaryCta;
  final CallToAction? secondaryCta;

  @override
  PageSectionType get type => PageSectionType.cta;

  @override
  CtaSection copyWithBase({int? sortOrder, bool? isVisible}) => CtaSection(
    id: id,
    sortOrder: sortOrder ?? this.sortOrder,
    isVisible: isVisible ?? this.isVisible,
    heading: heading,
    body: body,
    primaryCta: primaryCta,
    secondaryCta: secondaryCta,
  );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'body': body,
    'primaryCta': primaryCta.toMap(),
    'secondaryCta': secondaryCta?.toMap(),
  };
}

@immutable
class HighlightCard {
  const HighlightCard({required this.title, required this.body, this.image});

  final String title;
  final String body;
  final MediaReference? image;

  Map<String, Object?> toMap() => {
    'title': title,
    'body': body,
    'image': image?.toMap(),
  };

  factory HighlightCard.fromMap(Map<String, Object?> map) => HighlightCard(
    title: map['title'] as String? ?? '',
    body: map['body'] as String? ?? '',
    image: map['image'] == null
        ? null
        : MediaReference.fromMap(
            Map<String, Object?>.from(map['image']! as Map),
          ),
  );
}

/// SRS "Highlight/cards section".
@immutable
final class HighlightsSection extends PageSection {
  const HighlightsSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    this.introduction,
    required this.cards,
  });

  final String? heading;
  final String? introduction;
  final List<HighlightCard> cards;

  @override
  PageSectionType get type => PageSectionType.highlights;

  @override
  HighlightsSection copyWithBase({int? sortOrder, bool? isVisible}) =>
      HighlightsSection(
        id: id,
        sortOrder: sortOrder ?? this.sortOrder,
        isVisible: isVisible ?? this.isVisible,
        heading: heading,
        introduction: introduction,
        cards: cards,
      );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'introduction': introduction,
    'cards': cards.map((c) => c.toMap()).toList(),
  };
}

@immutable
class FaqItem {
  const FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  Map<String, Object?> toMap() => {'question': question, 'answer': answer};

  factory FaqItem.fromMap(Map<String, Object?> map) => FaqItem(
    question: map['question'] as String? ?? '',
    answer: map['answer'] as String? ?? '',
  );
}

/// SRS "FAQ reference". Stores question/answer pairs inline rather than
/// referencing a central FAQ collection: SRS WEB-09's centrally-managed
/// FAQ module (`feature_faqs`) does not exist yet in this milestone, so a
/// cross-feature reference would point at nothing. Migrating to
/// references once `feature_faqs` ships is a natural, additive follow-up
/// (add an optional `faqId` alongside these inline fields), not a
/// redesign — see decisions.md.
@immutable
final class FaqSection extends PageSection {
  const FaqSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    required this.items,
  });

  final String? heading;
  final List<FaqItem> items;

  @override
  PageSectionType get type => PageSectionType.faq;

  @override
  FaqSection copyWithBase({int? sortOrder, bool? isVisible}) => FaqSection(
    id: id,
    sortOrder: sortOrder ?? this.sortOrder,
    isVisible: isVisible ?? this.isVisible,
    heading: heading,
    items: items,
  );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'items': items.map((i) => i.toMap()).toList(),
  };
}

/// SRS "Gallery/media reference". Per the Media boundary, [items] are
/// plain [MediaReference]s the editor supplies directly — not a
/// `feature_media` library selection (that module doesn't exist yet).
@immutable
final class GallerySection extends PageSection {
  const GallerySection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    required this.items,
  });

  final String? heading;
  final List<MediaReference> items;

  @override
  PageSectionType get type => PageSectionType.gallery;

  @override
  GallerySection copyWithBase({int? sortOrder, bool? isVisible}) =>
      GallerySection(
        id: id,
        sortOrder: sortOrder ?? this.sortOrder,
        isVisible: isVisible ?? this.isVisible,
        heading: heading,
        items: items,
      );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'items': items.map((m) => m.toMap()).toList(),
  };
}

@immutable
class TestimonialEntry {
  const TestimonialEntry({
    required this.quote,
    this.attributionName,
    this.relationship,
  });

  final String quote;

  /// SRS WEB-10: "named or anonymised attribution" — null/empty means
  /// anonymised, a deliberate choice rather than a missing-data error.
  final String? attributionName;

  final String? relationship;

  Map<String, Object?> toMap() => {
    'quote': quote,
    'attributionName': attributionName,
    'relationship': relationship,
  };

  factory TestimonialEntry.fromMap(Map<String, Object?> map) =>
      TestimonialEntry(
        quote: map['quote'] as String? ?? '',
        attributionName: map['attributionName'] as String?,
        relationship: map['relationship'] as String?,
      );
}

/// SRS "Testimonial reference". Stores entries inline for the same reason
/// as [FaqSection] — SRS WEB-10's dedicated Testimonials module
/// (`feature_testimonials`) is not built yet in this milestone.
@immutable
final class TestimonialSection extends PageSection {
  const TestimonialSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    required this.items,
  });

  final String? heading;
  final List<TestimonialEntry> items;

  @override
  PageSectionType get type => PageSectionType.testimonial;

  @override
  TestimonialSection copyWithBase({int? sortOrder, bool? isVisible}) =>
      TestimonialSection(
        id: id,
        sortOrder: sortOrder ?? this.sortOrder,
        isVisible: isVisible ?? this.isVisible,
        heading: heading,
        items: items,
      );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'items': items.map((i) => i.toMap()).toList(),
  };
}

/// SRS "Related-content selection"; CMS-12 "Administrators select and
/// order related ... content. Unpublished/archived items disappear
/// automatically." [relatedPageIds] is the only content type available
/// to relate to in this milestone (Programs/Experiences/Events/articles/
/// FAQs don't exist yet) — deliberately manual, never automatic, per the
/// SRS 2.2 exclusion of "automatic related-content recommendations".
/// CMS-12's "disappear automatically" behavior is enforced at *render*
/// time (the public renderer/repository filters out any referenced page
/// that is not currently published), not baked into this list — an
/// unpublished page's id stays in [relatedPageIds] (so re-publishing it
/// makes it reappear without an editor having to re-add it) but is
/// simply skipped while it isn't publicly visible.
@immutable
final class RelatedContentSection extends PageSection {
  const RelatedContentSection({
    required super.id,
    required super.sortOrder,
    super.isVisible,
    this.heading,
    required this.relatedPageIds,
  });

  final String? heading;
  final List<String> relatedPageIds;

  @override
  PageSectionType get type => PageSectionType.relatedContent;

  @override
  RelatedContentSection copyWithBase({int? sortOrder, bool? isVisible}) =>
      RelatedContentSection(
        id: id,
        sortOrder: sortOrder ?? this.sortOrder,
        isVisible: isVisible ?? this.isVisible,
        heading: heading,
        relatedPageIds: relatedPageIds,
      );

  @override
  Map<String, Object?> toMap() => {
    'id': id,
    'type': type.storageValue,
    'sortOrder': sortOrder,
    'isVisible': isVisible,
    'heading': heading,
    'relatedPageIds': relatedPageIds,
  };
}

/// Deserializes a section map (as stored in Firestore/sent over the
/// wire) back into the correctly-typed [PageSection] subclass. Kept
/// alongside the sealed hierarchy (rather than in `data/`, unlike
/// `feature_publishing`'s mapper convention) because both the client and
/// the Cloud Functions validators need an equivalent switch, and keeping
/// the exhaustive `switch` next to the types it maps makes it easiest to
/// keep in sync when a new section type is ever added.
PageSection? pageSectionFromMap(Map<String, Object?> map) {
  final type = PageSectionType.fromStorageValue(map['type'] as String?);
  final id = map['id'] as String? ?? '';
  final sortOrder = (map['sortOrder'] as num?)?.toInt() ?? 0;
  final isVisible = map['isVisible'] as bool? ?? true;
  MediaReference mediaFrom(String key) => MediaReference.fromMap(
    Map<String, Object?>.from((map[key] as Map?) ?? const {}),
  );

  switch (type) {
    case PageSectionType.richText:
      return RichTextSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        body: map['body'] as String? ?? '',
      );
    case PageSectionType.image:
      return ImageSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        image: mediaFrom('image'),
      );
    case PageSectionType.imageText:
      return ImageTextSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        body: map['body'] as String? ?? '',
        image: mediaFrom('image'),
        imageSide: (map['imageSide'] as String?) == 'right'
            ? ImageSide.right
            : ImageSide.left,
      );
    case PageSectionType.cta:
      return CtaSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        body: map['body'] as String?,
        primaryCta: CallToAction.fromMap(
          Map<String, Object?>.from((map['primaryCta'] as Map?) ?? const {}),
        ),
        secondaryCta: map['secondaryCta'] == null
            ? null
            : CallToAction.fromMap(
                Map<String, Object?>.from(map['secondaryCta']! as Map),
              ),
      );
    case PageSectionType.highlights:
      return HighlightsSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        introduction: map['introduction'] as String?,
        cards: ((map['cards'] as List?) ?? const [])
            .map(
              (e) => HighlightCard.fromMap(Map<String, Object?>.from(e as Map)),
            )
            .toList(),
      );
    case PageSectionType.faq:
      return FaqSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        items: ((map['items'] as List?) ?? const [])
            .map((e) => FaqItem.fromMap(Map<String, Object?>.from(e as Map)))
            .toList(),
      );
    case PageSectionType.gallery:
      return GallerySection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        items: ((map['items'] as List?) ?? const [])
            .map(
              (e) =>
                  MediaReference.fromMap(Map<String, Object?>.from(e as Map)),
            )
            .toList(),
      );
    case PageSectionType.testimonial:
      return TestimonialSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        items: ((map['items'] as List?) ?? const [])
            .map(
              (e) =>
                  TestimonialEntry.fromMap(Map<String, Object?>.from(e as Map)),
            )
            .toList(),
      );
    case PageSectionType.relatedContent:
      return RelatedContentSection(
        id: id,
        sortOrder: sortOrder,
        isVisible: isVisible,
        heading: map['heading'] as String?,
        relatedPageIds: ((map['relatedPageIds'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
      );
    case null:
      return null;
  }
}
