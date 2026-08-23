// Regression coverage for the P0 UAT defect: an Admin notification with
// audience == 'Public' and status == 'Published' was visible in Admin but
// never appeared in the Parent or Staff feeds.
//
// Root cause was two-layered:
//  1. AdminNotificationService.getNotificationsForAudience queried
//     `audience == 'Parents'` / `audience == 'Staff'` with a plain equality
//     filter, which a 'Public' document can never match — it was excluded
//     before relevance filtering ever ran.
//  2. Even past the query, isNotificationRelevantToParent/Staff only ever
//     returned true for broadcast flags (appliesToAllClasses/
//     appliesToAllStudents/appliesToAllStaff) or explicit target-id lists.
//     AdminNotificationFormDialog._setPublic() clears every one of those
//     flags/lists for a Public notification, so relevance would have
//     rejected it too.
//
// This file drives the real query (getNotificationsForAudience, against a
// fake Firestore) followed by the real relevance functions, end-to-end —
// the same two-stage pipeline NotificationsFeedScreen and ParentDashboard
// actually run — so it reproduces the exact reported failure and proves the
// fix, rather than exercising either layer in isolation.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/notifications/models/admin_notification_model.dart';
import 'package:montessori_app/modules/notifications/ui/notification_relevance.dart';

// See admin_notification_service_audience_test.dart for why this stand-in
// is needed: AdminNotificationService's constructor default-initializes
// storage/filePicker to real platform singletons unless one is supplied,
// and neither is ever called by the read path exercised here.
class _UnusedFilePicker extends FilePicker {}

Future<void> _seedNotification(
  FakeFirebaseFirestore firestore, {
  required String title,
  required String audience,
  required String status,
  bool isPublic = false,
  bool appliesToAllClasses = false,
  bool appliesToAllStudents = false,
  bool appliesToAllStaff = false,
  List<String> applicableStaffIds = const [],
}) async {
  await firestore.collection('school_notifications').add({
    'title': title,
    'message': 'Message for $title',
    'notificationType': 'General',
    'category': 'General',
    'priority': 'Normal',
    'audience': audience,
    'visibility': audience,
    'status': status,
    'academicYear': '2026-2027',
    'publishDate': Timestamp.fromDate(DateTime(2026, 8, 1)),
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    'isPinned': false,
    'requiresAcknowledgement': false,
    'appliesToAllClasses': appliesToAllClasses,
    'applicableClassIds': const [],
    'applicableClassNames': const [],
    'appliesToAllStudents': appliesToAllStudents,
    'applicableStudentIds': const [],
    'applicableStudentNames': const [],
    'appliesToAllStaff': appliesToAllStaff,
    'applicableStaffIds': applicableStaffIds,
    'applicableStaffNames': const [],
    'isPublic': isPublic,
    'attachmentName': '',
    'attachmentUrl': '',
    'attachmentSize': null,
    'attachmentMimeType': '',
    'createdBy': 'test',
    'createdByName': 'Test',
  });
}

/// Reproduces exactly what AdminNotificationFormDialog._setPublic() writes:
/// audience/isPublic set, every targeting flag and list cleared.
Future<void> _seedPublicNotification(
  FakeFirebaseFirestore firestore, {
  required String title,
  required String status,
}) => _seedNotification(
  firestore,
  title: title,
  audience: 'Public',
  status: status,
  isPublic: true,
  appliesToAllClasses: false,
  appliesToAllStudents: false,
  appliesToAllStaff: false,
);

AdminNotificationService _service(FakeFirebaseFirestore firestore) =>
    AdminNotificationService(
      firestore: firestore,
      storage: MockFirebaseStorage(),
      filePicker: _UnusedFilePicker(),
    );

Future<List<AdminNotificationModel>> _relevantToParent(
  AdminNotificationService service,
) async {
  final fetched = await service.getNotificationsForAudience('Parents');
  return fetched
      .where(
        (n) => isNotificationRelevantToParent(
          n,
          childStudentIds: {'student-1'},
          childClassIds: {'class-mont1'},
        ),
      )
      .toList();
}

Future<List<AdminNotificationModel>> _relevantToStaff(
  AdminNotificationService service,
) async {
  final fetched = await service.getNotificationsForAudience('Staff');
  return fetched
      .where(
        (n) => isNotificationRelevantToStaff(n, staffUserId: 'staff-1'),
      )
      .toList();
}

void main() {
  group('Public notification visibility (P0 fix)', () {
    test('1. Published Public notification is visible to Parent', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPublicNotification(
        firestore,
        title: 'School Reopens Monday',
        status: 'Published',
      );
      final result = await _relevantToParent(_service(firestore));

      expect(result, hasLength(1));
      expect(result.single.title, 'School Reopens Monday');
    });

    test('2. Published Public notification is visible to Staff', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPublicNotification(
        firestore,
        title: 'School Reopens Monday',
        status: 'Published',
      );
      final result = await _relevantToStaff(_service(firestore));

      expect(result, hasLength(1));
      expect(result.single.title, 'School Reopens Monday');
    });

    test('3. Draft Public notification is visible to neither Parent nor Staff', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedPublicNotification(
        firestore,
        title: 'Unpublished public draft',
        status: 'Draft',
      );
      final service = _service(firestore);

      expect(await _relevantToParent(service), isEmpty);
      expect(await _relevantToStaff(service), isEmpty);
    });

    test('4. Parent-targeted notification is not seen by Staff', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Fee Reminder',
        audience: 'Parents',
        status: 'Published',
        appliesToAllStudents: true,
      );
      final result = await _relevantToStaff(_service(firestore));

      expect(result, isEmpty);
    });

    test('5. Staff-targeted notification is not seen by Parent', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Staff Meeting Reminder',
        audience: 'Staff',
        status: 'Published',
        appliesToAllStaff: true,
      );
      final result = await _relevantToParent(_service(firestore));

      expect(result, isEmpty);
    });

    test(
      '6. Existing Parent/Staff broadcast and selected targeting still work alongside a Public notification',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seedPublicNotification(
          firestore,
          title: 'Public Notice',
          status: 'Published',
        );
        await _seedNotification(
          firestore,
          title: 'All-Classes Parent Notice',
          audience: 'Parents',
          status: 'Published',
          appliesToAllClasses: true,
        );
        await _seedNotification(
          firestore,
          title: 'All-Staff Notice',
          audience: 'Staff',
          status: 'Published',
          appliesToAllStaff: true,
        );

        final parentResult = await _relevantToParent(_service(firestore));
        final staffResult = await _relevantToStaff(_service(firestore));

        expect(
          parentResult.map((n) => n.title),
          containsAll(['Public Notice', 'All-Classes Parent Notice']),
        );
        expect(
          parentResult.map((n) => n.title),
          isNot(contains('All-Staff Notice')),
        );

        expect(
          staffResult.map((n) => n.title),
          containsAll(['Public Notice', 'All-Staff Notice']),
        );
        expect(
          staffResult.map((n) => n.title),
          isNot(contains('All-Classes Parent Notice')),
        );
      },
    );
  });
}
