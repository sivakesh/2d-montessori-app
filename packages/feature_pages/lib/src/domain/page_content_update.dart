import 'package:meta/meta.dart';

import 'media_reference.dart';
import 'page_section.dart';
import 'page_type.dart';
import 'seo_metadata.dart';

/// The full editable-content payload for a save (SRS CMS-07 autosave
/// saves the whole current form state, not a sparse diff — this type
/// mirrors that: every field is the caller's complete current value, not
/// an optional "only if changed" patch). Excludes every workflow/envelope
/// field (status, owner, timestamps) — those are never client-writable
/// even indirectly; only `feature_publishing`'s transition actions change
/// them.
@immutable
class PageContentUpdate {
  const PageContentUpdate({
    required this.title,
    required this.slug,
    required this.summary,
    required this.pageType,
    required this.sections,
    this.featuredImage,
    required this.seo,
    this.navigationLabel,
    required this.showInNavigation,
  });

  final String title;
  final String slug;
  final String summary;
  final PageType pageType;
  final List<PageSection> sections;
  final MediaReference? featuredImage;
  final SeoMetadata seo;
  final String? navigationLabel;
  final bool showInNavigation;

  Map<String, Object?> toMap() => {
    'title': title,
    'slug': slug,
    'summary': summary,
    'pageType': pageType.storageValue,
    'sections': sections.map((s) => s.toMap()).toList(),
    'featuredImage': featuredImage?.toMap(),
    'seo': seo.toMap(),
    'navigationLabel': navigationLabel,
    'showInNavigation': showInNavigation,
  };
}
