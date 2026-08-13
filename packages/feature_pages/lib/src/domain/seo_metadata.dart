import 'package:meta/meta.dart';

import 'media_reference.dart';

/// SRS SEO-01 "indexing control"; NFR-09 "drafts/previews are noindex and
/// inaccessible publicly". Values follow the PRD §5.2 SEO object naming
/// (SRS specifies the requirement but not the exact enum), since the two
/// documents don't conflict here.
enum PageIndexingControl {
  indexFollow('indexFollow'),
  noIndexFollow('noIndexFollow'),
  noIndexNoFollow('noIndexNoFollow');

  const PageIndexingControl(this.storageValue);

  final String storageValue;

  static PageIndexingControl fromStorageValue(String? value) =>
      PageIndexingControl.values.firstWhere(
        (v) => v.storageValue == value,
        orElse: () => PageIndexingControl.indexFollow,
      );
}

/// SRS SEO-01 "social title/description/image"; WEB-08's "social sharing"
/// for editorial content generally. Distinct from [SeoMetadata]'s search
/// fields because a page's Open Graph presentation is allowed to differ
/// from its search-result presentation (PRD §5.2 defaults `ogTitle` to
/// `metaTitle` when unset, which callers implement, not this type).
@immutable
class SocialShareMetadata {
  const SocialShareMetadata({this.title, this.description, this.image});

  final String? title;
  final String? description;
  final MediaReference? image;

  SocialShareMetadata copyWith({
    String? title,
    String? description,
    MediaReference? image,
  }) => SocialShareMetadata(
    title: title ?? this.title,
    description: description ?? this.description,
    image: image ?? this.image,
  );

  Map<String, Object?> toMap() => {
    'title': title,
    'description': description,
    'image': image?.toMap(),
  };

  factory SocialShareMetadata.fromMap(Map<String, Object?> map) =>
      SocialShareMetadata(
        title: map['title'] as String?,
        description: map['description'] as String?,
        image: map['image'] == null
            ? null
            : MediaReference.fromMap(
                Map<String, Object?>.from(map['image']! as Map),
              ),
      );

  static const empty = SocialShareMetadata();
}

/// SRS SEO-01: "Each public item supports SEO title, meta description,
/// unique readable slug, canonical URL, indexing control and social
/// title/description/image." The unique slug itself lives on [CmsPage]
/// directly (it is the page's own identity, not SEO-only metadata); this
/// type holds the rest.
@immutable
class SeoMetadata {
  const SeoMetadata({
    this.title,
    this.metaDescription,
    this.canonicalUrl,
    this.indexing = PageIndexingControl.indexFollow,
    this.social = SocialShareMetadata.empty,
  });

  /// Recommended 10–60 characters (PRD §5.2). Not enforced as a hard
  /// minimum on Draft — see [PageCompletenessValidator] for when it
  /// becomes required (submitting for review/publishing).
  final String? title;

  /// Recommended 50–160 characters (PRD §5.2).
  final String? metaDescription;

  /// SRS SEO-01 "canonical URL where applicable" — optional because not
  /// every page needs an explicit canonical override (the default is the
  /// page's own published route).
  final String? canonicalUrl;

  final PageIndexingControl indexing;
  final SocialShareMetadata social;

  SeoMetadata copyWith({
    String? title,
    String? metaDescription,
    String? canonicalUrl,
    PageIndexingControl? indexing,
    SocialShareMetadata? social,
  }) => SeoMetadata(
    title: title ?? this.title,
    metaDescription: metaDescription ?? this.metaDescription,
    canonicalUrl: canonicalUrl ?? this.canonicalUrl,
    indexing: indexing ?? this.indexing,
    social: social ?? this.social,
  );

  Map<String, Object?> toMap() => {
    'title': title,
    'metaDescription': metaDescription,
    'canonicalUrl': canonicalUrl,
    'indexing': indexing.storageValue,
    'social': social.toMap(),
  };

  factory SeoMetadata.fromMap(Map<String, Object?>? map) {
    if (map == null) return const SeoMetadata();
    return SeoMetadata(
      title: map['title'] as String?,
      metaDescription: map['metaDescription'] as String?,
      canonicalUrl: map['canonicalUrl'] as String?,
      indexing: PageIndexingControl.fromStorageValue(
        map['indexing'] as String?,
      ),
      social: map['social'] == null
          ? SocialShareMetadata.empty
          : SocialShareMetadata.fromMap(
              Map<String, Object?>.from(map['social']! as Map),
            ),
    );
  }

  static const empty = SeoMetadata();
}
