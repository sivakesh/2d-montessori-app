// Regression coverage for the P0 UAT gap: Admin had no way to remove an
// incorrect, test, or obsolete notification. AdminNotificationService
// already had an unused `archiveNotification` method — this reuses that
// existing lifecycle (status: 'Archived') instead of inventing a new one or
// hard-deleting, since the Parent/Staff/Public feed query
// (getNotificationsForAudience) already filters to `status == 'Published'`
// only, and the Admin screen's Status filter already understands
// 'Archived'. Archiving therefore removes a notification from every
// consumer feed while preserving the original document (and any
// attachment) for Admin history — nothing new to build there, only the
// missing UI trigger + confirmation + feedback.
//
// Two groups:
//  - 'AdminNotificationService.archiveNotification (data safety + feed
//    exclusion)': pure service/query-level tests, no widget involved —
//    covers cases 1, 4, 5, 6, 7, 8, 9 from the task's numbered list.
//  - 'AdminNotificationsScreen archive action (UX)': drives the actual
//    screen — covers cases 1 (UI trigger), 2, 3, 10.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/ui/admin_notifications_screen.dart';
import 'package:montessori_app/modules/notifications/ui/notification_relevance.dart';

// See admin_notification_service_audience_test.dart for why this stand-in
// is needed: AdminNotificationService's constructor default-initializes
// storage/filePicker to real platform singletons unless one is supplied.
class _UnusedFilePicker extends FilePicker {}

/// Overrides archiveNotification to always fail, without ever touching
/// Firestore — simulating a genuine write failure (e.g. a network drop)
/// where nothing is written, so the underlying document is provably
/// unchanged. Extends the real service so the widget under test still gets
/// a real AdminNotificationService for every other call (getNotifications).
class _ThrowingArchiveService extends AdminNotificationService {
  _ThrowingArchiveService({
    required FirebaseFirestore firestore,
    required super.storage,
    required super.filePicker,
  }) : super(firestore: firestore);

  @override
  Future<void> archiveNotification(String id) async {
    throw Exception('network error');
  }
}

Future<String> _seedNotification(
  FakeFirebaseFirestore firestore, {
  required String title,
  required String audience,
  required String status,
  bool isPublic = false,
  bool appliesToAllClasses = false,
  bool appliesToAllStudents = false,
  bool appliesToAllStaff = false,
  String attachmentUrl = '',
}) async {
  final doc = await firestore.collection('school_notifications').add({
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
    'applicableStaffIds': const [],
    'applicableStaffNames': const [],
    'isPublic': isPublic,
    'attachmentName': attachmentUrl.isEmpty ? '' : 'file.pdf',
    'attachmentUrl': attachmentUrl,
    'attachmentSize': null,
    'attachmentMimeType': '',
    'createdBy': 'test',
    'createdByName': 'Test',
  });
  return doc.id;
}

AdminNotificationService _service(FakeFirebaseFirestore firestore) =>
    AdminNotificationService(
      firestore: firestore,
      storage: MockFirebaseStorage(),
      filePicker: _UnusedFilePicker(),
    );

void main() {
  group('AdminNotificationService.archiveNotification (data safety + feed exclusion)', () {
    test('1. archiving sets status to Archived and preserves every other field', () async {
      final firestore = FakeFirebaseFirestore();
      final id = await _seedNotification(
        firestore,
        title: 'Test blast — please ignore',
        audience: 'Parents',
        status: 'Published',
        appliesToAllStudents: true,
        attachmentUrl: 'https://example.com/file.pdf',
      );
      final service = _service(firestore);

      await service.archiveNotification(id);

      final all = await service.getNotifications();
      final archived = all.singleWhere((n) => n.id == id);
      expect(archived.status, 'Archived');
      expect(archived.title, 'Test blast — please ignore');
      expect(archived.audience, 'Parents');
      expect(archived.attachmentUrl, 'https://example.com/file.pdf');
      expect(archived.appliesToAllStudents, isTrue);
    });

    test('4. an archived Parents-audience notification no longer appears in the Parent feed', () async {
      final firestore = FakeFirebaseFirestore();
      final id = await _seedNotification(
        firestore,
        title: 'Fee Reminder',
        audience: 'Parents',
        status: 'Published',
        appliesToAllStudents: true,
      );
      final service = _service(firestore);
      await service.archiveNotification(id);

      final fetched = await service.getNotificationsForAudience('Parents');
      final relevant = fetched.where(
        (n) => isNotificationRelevantToParent(n, childStudentIds: {}, childClassIds: {}),
      );

      expect(relevant, isEmpty);
    });

    test('5. an archived Staff-audience notification no longer appears in the Staff feed', () async {
      final firestore = FakeFirebaseFirestore();
      final id = await _seedNotification(
        firestore,
        title: 'Staff Meeting Reminder',
        audience: 'Staff',
        status: 'Published',
        appliesToAllStaff: true,
      );
      final service = _service(firestore);
      await service.archiveNotification(id);

      final fetched = await service.getNotificationsForAudience('Staff');
      final relevant = fetched.where(
        (n) => isNotificationRelevantToStaff(n, staffUserId: 'staff-1'),
      );

      expect(relevant, isEmpty);
    });

    test('6. an archived Public notification no longer appears in the Parent or Staff feed', () async {
      final firestore = FakeFirebaseFirestore();
      final id = await _seedNotification(
        firestore,
        title: 'School Reopens Monday',
        audience: 'Public',
        status: 'Published',
        isPublic: true,
      );
      final service = _service(firestore);
      await service.archiveNotification(id);

      final parentFetched = await service.getNotificationsForAudience('Parents');
      final staffFetched = await service.getNotificationsForAudience('Staff');

      expect(
        parentFetched.where(
          (n) => isNotificationRelevantToParent(n, childStudentIds: {}, childClassIds: {}),
        ),
        isEmpty,
      );
      expect(
        staffFetched.where(
          (n) => isNotificationRelevantToStaff(n, staffUserId: 'staff-1'),
        ),
        isEmpty,
      );
    });

    test('7. archiving one notification does not affect another notification', () async {
      final firestore = FakeFirebaseFirestore();
      final archivedId = await _seedNotification(
        firestore,
        title: 'Old test notice',
        audience: 'Parents',
        status: 'Published',
        appliesToAllStudents: true,
      );
      final untouchedId = await _seedNotification(
        firestore,
        title: 'Real fee reminder',
        audience: 'Parents',
        status: 'Published',
        appliesToAllStudents: true,
      );
      final service = _service(firestore);

      await service.archiveNotification(archivedId);

      final all = await service.getNotifications();
      final untouched = all.singleWhere((n) => n.id == untouchedId);
      expect(untouched.status, 'Published');
      expect(untouched.title, 'Real fee reminder');

      final feed = await service.getNotificationsForAudience('Parents');
      expect(feed.map((n) => n.id), [untouchedId]);
    });

    test('8. an existing Published notification (never archived) continues to reach the feed', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Holiday Notice',
        audience: 'Parents',
        status: 'Published',
        appliesToAllStudents: true,
      );
      final service = _service(firestore);

      final feed = await service.getNotificationsForAudience('Parents');

      expect(feed, hasLength(1));
      expect(feed.single.title, 'Holiday Notice');
    });

    test('9. an existing Draft notification remains excluded from the feed, unrelated to archiving', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedNotification(
        firestore,
        title: 'Unpublished draft',
        audience: 'Parents',
        status: 'Draft',
        appliesToAllStudents: true,
      );
      final service = _service(firestore);

      final feed = await service.getNotificationsForAudience('Parents');

      expect(feed, isEmpty);
    });
  });

  group('AdminNotificationsScreen archive action (UX)', () {
    testWidgets(
      '2. tapping Archive requires confirmation before anything is written',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final id = await _seedNotification(
          firestore,
          title: 'Test blast',
          audience: 'Parents',
          status: 'Published',
          appliesToAllStudents: true,
        );
        final service = _service(firestore);

        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(home: AdminNotificationsScreen(service: service)),
          ),
        );
        await tester.pumpAndSettle();

        final archiveButton = find.widgetWithIcon(IconButton, Icons.archive_outlined);
        await tester.ensureVisible(archiveButton);
        await tester.tap(archiveButton);
        await tester.pumpAndSettle();

        expect(find.text('Archive Notification'), findsOneWidget);
        final doc = await firestore.collection('school_notifications').doc(id).get();
        expect(doc.data()!['status'], 'Published');
      },
    );

    testWidgets('3. Cancel leaves the notification completely unchanged', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final id = await _seedNotification(
        firestore,
        title: 'Test blast',
        audience: 'Parents',
        status: 'Published',
        appliesToAllStudents: true,
      );
      final service = _service(firestore);

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp(home: AdminNotificationsScreen(service: service))),
      );
      await tester.pumpAndSettle();

      final archiveButton = find.widgetWithIcon(IconButton, Icons.archive_outlined);
      await tester.ensureVisible(archiveButton);
      await tester.tap(archiveButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Archive Notification'), findsNothing);
      final doc = await firestore.collection('school_notifications').doc(id).get();
      expect(doc.data()!['status'], 'Published');
      // The row still offers Archive — nothing was removed from the list.
      expect(find.widgetWithIcon(IconButton, Icons.archive_outlined), findsOneWidget);
    });

    testWidgets(
      '1. confirming Archive updates Firestore and shows a success message',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final id = await _seedNotification(
          firestore,
          title: 'Test blast',
          audience: 'Parents',
          status: 'Published',
          appliesToAllStudents: true,
        );
        final service = _service(firestore);

        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: AdminNotificationsScreen(service: service))),
        );
        await tester.pumpAndSettle();

        final archiveButton = find.widgetWithIcon(IconButton, Icons.archive_outlined);
        await tester.ensureVisible(archiveButton);
        await tester.tap(archiveButton);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
        await tester.pumpAndSettle();

        expect(find.text('Notification archived'), findsOneWidget);
        final doc = await firestore.collection('school_notifications').doc(id).get();
        expect(doc.data()!['status'], 'Archived');
        // Already-archived rows don't offer Archive again.
        expect(find.widgetWithIcon(IconButton, Icons.archive_outlined), findsNothing);
      },
    );

    testWidgets(
      '10. a failed archive shows an error message and leaves the document unchanged',
      (tester) async {
        final firestore = FakeFirebaseFirestore();
        final id = await _seedNotification(
          firestore,
          title: 'Test blast',
          audience: 'Parents',
          status: 'Published',
          appliesToAllStudents: true,
        );
        final service = _ThrowingArchiveService(
          firestore: firestore,
          storage: MockFirebaseStorage(),
          filePicker: _UnusedFilePicker(),
        );

        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp(home: AdminNotificationsScreen(service: service))),
        );
        await tester.pumpAndSettle();

        final archiveButton = find.widgetWithIcon(IconButton, Icons.archive_outlined);
        await tester.ensureVisible(archiveButton);
        await tester.tap(archiveButton);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Failed to archive notification'), findsOneWidget);
        final doc = await firestore.collection('school_notifications').doc(id).get();
        expect(doc.data()!['status'], 'Published');
        // Still offered — the row was never marked archived.
        expect(find.widgetWithIcon(IconButton, Icons.archive_outlined), findsOneWidget);
      },
    );
  });
}
