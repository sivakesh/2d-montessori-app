import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/publishing_record.dart';
import '../domain/publishing_status.dart';

/// Maps between the `content/{contentId}` Firestore document shape and
/// the domain `PublishingRecord`. See
/// docs/architecture/firestore-model.md for the collection's field list.
abstract final class PublishingRecordMapper {
  static PublishingRecord fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('content/${snapshot.id} has no data');
    }
    return fromMap(snapshot.id, data);
  }

  static PublishingRecord fromMap(String contentId, Map<String, dynamic> data) {
    return PublishingRecord(
      contentId: contentId,
      contentType: data['contentType'] as String? ?? '',
      title: data['title'] as String? ?? '',
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
}
