import 'package:feature_publishing/feature_publishing.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/cms_page.dart';
import '../domain/media_reference.dart';
import '../domain/page_section.dart';
import '../domain/page_type.dart';
import '../domain/seo_metadata.dart';

/// Firestore document <-> [CmsPage]. Not exported from the package
/// barrel — internal to `data/`, mirroring `feature_publishing`'s
/// `PublishingRecordMapper` convention (mappers are an implementation
/// detail of the repository, not part of the public API).
abstract final class CmsPageMapper {
  static CmsPage fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => fromMap(snapshot.id, snapshot.data() ?? const {});

  static CmsPage fromMap(String pageId, Map<String, dynamic> data) => CmsPage(
    pageId: pageId,
    title: data['title'] as String? ?? '',
    slug: data['slug'] as String? ?? '',
    summary: data['summary'] as String? ?? '',
    pageType:
        PageType.fromStorageValue(data['pageType'] as String?) ??
        PageType.standard,
    sections: _sectionsFrom(data['sections']),
    featuredImage: data['featuredImage'] == null
        ? null
        : MediaReference.fromMap(
            Map<String, Object?>.from(data['featuredImage'] as Map),
          ),
    seo: SeoMetadata.fromMap(
      data['seo'] == null
          ? null
          : Map<String, Object?>.from(data['seo'] as Map),
    ),
    navigationLabel: data['navigationLabel'] as String?,
    showInNavigation: data['showInNavigation'] as bool? ?? false,
    status:
        PublishingStatus.fromStorageValue(data['status'] as String?) ??
        PublishingStatus.draft,
    ownerId: data['ownerId'] as String? ?? '',
    submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
    submittedBy: data['submittedBy'] as String?,
    reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
    reviewedBy: data['reviewedBy'] as String?,
    scheduledAt: (data['scheduledAt'] as Timestamp?)?.toDate(),
    publishedAt: (data['publishedAt'] as Timestamp?)?.toDate(),
    publishedBy: data['publishedBy'] as String?,
    archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
    archivedBy: data['archivedBy'] as String?,
    restoredAt: (data['restoredAt'] as Timestamp?)?.toDate(),
    restoredBy: data['restoredBy'] as String?,
    createdAt:
        (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    createdBy: data['createdBy'] as String? ?? '',
    updatedAt:
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedBy: data['updatedBy'] as String? ?? '',
  );
}

List<PageSection> _sectionsFrom(Object? raw) => ((raw as List?) ?? const [])
    .map((e) => pageSectionFromMap(Map<String, Object?>.from(e as Map)))
    .whereType<PageSection>()
    .toList();
