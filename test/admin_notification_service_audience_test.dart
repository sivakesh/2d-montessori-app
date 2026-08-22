// Regression coverage for AdminNotificationService.getNotificationsForAudience
// — the consumer-facing Parent/Staff feeds' only query, which must exclude
// drafts and other-audience notifications before relevance filtering ever
// runs. Covers cases 8 ("unpublished notification") and 9 ("wrong audience")
// from the Phase B notification audit; the pure targeting-relevance cases
// (1-7, 10) live in notification_relevance_test.dart since they don't touch
// Firestore at all.
//
// The 'Staff notification pipeline' group below additionally exercises the
// full getNotificationsForAudience -> isNotificationRelevantToStaff chain
// end-to-end (not just the pure relevance function in isolation), because
// the reported "Staff notification does not appear" defect turned out to be
// upstream of relevance entirely: AdminNotificationFormDialog has no UI
// control to set `status`, so every notification it creates — for any
// audience — is saved as 'Draft' and never reaches this query's
// status == 'Published' filter. These tests seed data the way a Published
// Staff notification actually looks once that gap is fixed, to guard the
// query + relevance combination a Staff user's feed depends on.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/notifications/ui/notification_relevance.dart';

// AdminNotificationService's constructor default-initializes storage/
// filePicker to their real platform singletons whenever the caller doesn't
// supply one — those singletons need a real Firebase app / platform channel
// respectively, neither of which exists in a plain unit test. Neither is
// ever actually called by getNotificationsForAudience, so a bare stand-in
// that's merely instantiable is enough.
class _UnusedFilePicker extends FilePicker {}

Future<void> _seedNotification(
  FakeFirebaseFirestore firestore, {
  required String title,
  required String audience,
  required String status,
  bool appliesToAllStaff = true,
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
    'appliesToAllClasses': true,
    'applicableClassIds': const [],
    'applicableClassNames': const [],
    'appliesToAllStudents': true,
    'applicableStudentIds': const [],
    'applicableStudentNames': const [],
    'appliesToAllStaff': appliesToAllStaff,
    'applicableStaffIds': applicableStaffIds,
    'applicableStaffNames': const [],
    'isPublic': false,
    'attachmentName': '',
    'attachmentUrl': '',
    'attachmentSize': null,
    'attachmentMimeType': '',
    'createdBy': 'test',
    'createdByName': 'Test',
  });
}

void main() {
  group('getNotificationsForAudience', () {
    test('excludes an unpublished (Draft) notification even with a matching audience', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Draft notice',
        audience: 'Parents',
        status: 'Draft',
      );
      final service = AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      );

      final result = await service.getNotificationsForAudience('Parents');

      expect(result, isEmpty);
    });

    test('excludes a Published notification whose audience does not match', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Staff-only notice',
        audience: 'Staff',
        status: 'Published',
      );
      final service = AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      );

      final result = await service.getNotificationsForAudience('Parents');

      expect(result, isEmpty);
    });

    test('includes a Published notification with a matching audience', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Fee reminder',
        audience: 'Parents',
        status: 'Published',
      );
      final service = AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      );

      final result = await service.getNotificationsForAudience('Parents');

      expect(result, hasLength(1));
      expect(result.single.title, 'Fee reminder');
    });
  });

  group('Staff notification pipeline (query + relevance)', () {
    test('Test 1 — Published Staff broadcast (appliesToAllStaff) is returned and relevant to any staff user', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Staff Meeting Reminder',
        audience: 'Staff',
        status: 'Published',
        appliesToAllStaff: true,
      );
      final service = AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      );

      final result = await service.getNotificationsForAudience('Staff');

      expect(result, hasLength(1));
      expect(
        isNotificationRelevantToStaff(result.single, staffUserId: 'staff-1'),
        isTrue,
      );
    });

    test('Test 2 — Published Staff selected-targeting notification reaches only the selected staff id', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Payroll Update',
        audience: 'Staff',
        status: 'Published',
        appliesToAllStaff: false,
        applicableStaffIds: ['staff-a'],
      );
      final service = AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      );

      final result = await service.getNotificationsForAudience('Staff');

      expect(result, hasLength(1));
      expect(
        isNotificationRelevantToStaff(result.single, staffUserId: 'staff-a'),
        isTrue,
      );
      expect(
        isNotificationRelevantToStaff(result.single, staffUserId: 'staff-b'),
        isFalse,
      );
    });

    test('Test 3 — a Parent notification does not appear when querying the Staff audience', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Fee Reminder',
        audience: 'Parents',
        status: 'Published',
      );
      final service = AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      );

      final result = await service.getNotificationsForAudience('Staff');

      expect(result, isEmpty);
    });

    test('Test 4 — a Draft Staff notification (the AdminNotificationFormDialog default) never reaches the feed', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Newly created staff notice',
        audience: 'Staff',
        status: 'Draft',
        appliesToAllStaff: true,
      );
      final service = AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      );

      final result = await service.getNotificationsForAudience('Staff');

      expect(result, isEmpty);
    });
  });
}
