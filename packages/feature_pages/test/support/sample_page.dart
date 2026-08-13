import 'package:feature_pages/feature_pages.dart';
import 'package:feature_publishing/feature_publishing.dart';

CmsPage samplePage({
  String pageId = 'page-1',
  String title = 'About us',
  String slug = 'about-us',
  String summary = 'A short summary.',
  List<PageSection> sections = const [],
  SeoMetadata seo = const SeoMetadata(
    title: 'About us',
    metaDescription: 'A page about us.',
  ),
  MediaReference? featuredImage,
  PublishingStatus status = PublishingStatus.draft,
  String ownerId = 'owner-1',
}) {
  final now = DateTime(2026, 1, 1);
  return CmsPage(
    pageId: pageId,
    title: title,
    slug: slug,
    summary: summary,
    sections: sections,
    seo: seo,
    featuredImage: featuredImage,
    status: status,
    ownerId: ownerId,
    createdAt: now,
    createdBy: ownerId,
    updatedAt: now,
    updatedBy: ownerId,
  );
}
