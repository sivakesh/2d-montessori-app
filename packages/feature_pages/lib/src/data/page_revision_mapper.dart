import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/media_reference.dart';
import '../domain/page_revision.dart';
import '../domain/page_section.dart';
import '../domain/page_type.dart';
import '../domain/seo_metadata.dart';

abstract final class PageRevisionMapper {
  static PageRevision fromSnapshot(
    String pageId,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const {};
    return PageRevision(
      revisionId: snapshot.id,
      pageId: pageId,
      title: data['title'] as String? ?? '',
      slug: data['slug'] as String? ?? '',
      summary: data['summary'] as String? ?? '',
      pageType:
          PageType.fromStorageValue(data['pageType'] as String?) ??
          PageType.standard,
      sections: ((data['sections'] as List?) ?? const [])
          .map((e) => pageSectionFromMap(Map<String, Object?>.from(e as Map)))
          .whereType<PageSection>()
          .toList(),
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
      actorId: data['actorId'] as String? ?? '',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
