// Regression coverage for a Parent notification targeting defect: a
// notification targeted specifically to one linked child (Amenah Noor)
// was also appearing on the Dashboard when a *different* linked child
// (Abdul Hakeem Khan) was selected, even though both children belong to
// the same parent account.
//
// Root cause: isNotificationRelevantToParent (notification_relevance.dart)
// was never the problem — it correctly answers "is this notification
// relevant to this set of student/class ids". The bug was in
// ParentDashboard: it computed childStudentIds/childClassIds once, at
// load time, as the UNION across every linked child, filtered the fetched
// notifications against that union, and stored the already-filtered
// result — so switching the selected child never re-filtered anything,
// and a notification targeted to any one linked child stayed visible
// regardless of which child was actually selected. Amenah's studentId
// being in the union (because Amenah is linked to the parent) is a
// correct answer to "is this relevant to the parent account" — it is not
// a correct answer to "is this relevant to the currently selected child",
// which is the question the Dashboard preview actually needs answered.
//
// Fix: ParentDashboard now stores the raw, audience-narrowed
// notifications list (`_parentNotifications`, unfiltered by any child)
// and re-derives the visible subset at build time using a *singleton* set
// containing only the currently selected child's own studentId/classId —
// so the exact same, unmodified isNotificationRelevantToParent function
// now answers the right question. "View All" (ParentNotificationsScreen)
// deliberately keeps its existing parent-account-wide (union) semantics
// per the investigation's own guidance — only the Dashboard preview is
// selected-child-aware.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/notifications/models/admin_notification_model.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/notifications/ui/notification_relevance.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

// AdminNotificationService default-initializes FilePicker.platform whenever
// no filePicker is supplied — that singleton needs a real platform channel,
// which doesn't exist in a plain test. Never actually called by
// getNotificationsForAudience; a bare stand-in that's merely instantiable
// is enough (same pattern as admin_notification_service_audience_test.dart).
class _UnusedFilePicker extends FilePicker {}

Future<void> _seedNotification(
  FakeFirebaseFirestore firestore, {
  required String title,
  String status = 'Published',
  bool appliesToAllClasses = false,
  bool appliesToAllStudents = false,
  List<String> applicableClassIds = const [],
  List<String> applicableStudentIds = const [],
  String audience = 'Parents',
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
    'applicableClassIds': applicableClassIds,
    'applicableClassNames': const [],
    'appliesToAllStudents': appliesToAllStudents,
    'applicableStudentIds': applicableStudentIds,
    'applicableStudentNames': const [],
    'appliesToAllStaff': false,
    'applicableStaffIds': const [],
    'applicableStaffNames': const [],
    'isPublic': false,
    'attachmentName': '',
    'attachmentUrl': '',
    'attachmentSize': null,
    'attachmentMimeType': '',
    'createdBy': 'admin',
    'createdByName': 'Admin',
  });
}

void main() {
  group(
    'isNotificationRelevantToParent — selected single child (Tests 1-7)',
    () {
      const amenahId = 'student-amenah';
      const abdulId = 'student-abdul';
      const classX = 'class-x';
      const classY = 'class-y';

      late FakeFirebaseFirestore firestore;
      late AdminNotificationService service;

      setUp(() {
        firestore = FakeFirebaseFirestore();
        service = AdminNotificationService(
          firestore: firestore,
          storage: MockFirebaseStorage(),
          filePicker: _UnusedFilePicker(),
        );
      });

      bool relevantTo(
        AdminNotificationModel n, {
        required String studentId,
        required String classId,
      }) {
        return isNotificationRelevantToParent(
          n,
          childStudentIds: {studentId},
          childClassIds: classId.isEmpty ? const {} : {classId},
        );
      }

      test('Test 1 — a notification targeted to Amenah is visible for Amenah, invisible for Abdul', () async {
        await _seedNotification(
          firestore,
          title: 'For Amenah only',
          applicableStudentIds: [amenahId],
        );
        final result = await service.getNotificationsForAudience('Parents');
        final n = result.single;

        expect(relevantTo(n, studentId: amenahId, classId: classX), isTrue);
        expect(relevantTo(n, studentId: abdulId, classId: classY), isFalse);
      });

      test('Test 2 — reverse targeting: a notification targeted to Abdul is invisible for Amenah', () async {
        await _seedNotification(
          firestore,
          title: 'For Abdul only',
          applicableStudentIds: [abdulId],
        );
        final result = await service.getNotificationsForAudience('Parents');
        final n = result.single;

        expect(relevantTo(n, studentId: amenahId, classId: classX), isFalse);
        expect(relevantTo(n, studentId: abdulId, classId: classY), isTrue);
      });

      test('Test 3 — appliesToAllStudents is visible for every linked child', () async {
        await _seedNotification(
          firestore,
          title: 'Broadcast to all students',
          appliesToAllStudents: true,
        );
        final result = await service.getNotificationsForAudience('Parents');
        final n = result.single;

        expect(relevantTo(n, studentId: amenahId, classId: classX), isTrue);
        expect(relevantTo(n, studentId: abdulId, classId: classY), isTrue);
      });

      test('Test 4 — class targeting: visible only for the child in that class', () async {
        await _seedNotification(
          firestore,
          title: 'Class X notice',
          applicableClassIds: [classX],
        );
        final result = await service.getNotificationsForAudience('Parents');
        final n = result.single;

        // Amenah is in Class X, Abdul is in Class Y.
        expect(relevantTo(n, studentId: amenahId, classId: classX), isTrue);
        expect(relevantTo(n, studentId: abdulId, classId: classY), isFalse);
      });

      test('Test 5 — a Staff notification never appears in the Parent audience query', () async {
        await _seedNotification(
          firestore,
          title: 'Staff-only notice',
          audience: 'Staff',
          appliesToAllStudents: true,
        );
        final result = await service.getNotificationsForAudience('Parents');

        expect(result, isEmpty);
      });

      test('Test 6 — a Draft Parent notification never reaches either child', () async {
        await _seedNotification(
          firestore,
          title: 'Unpublished notice',
          status: 'Draft',
          appliesToAllStudents: true,
        );
        final result = await service.getNotificationsForAudience('Parents');

        expect(result, isEmpty);
      });

      test('Test 7 — an existing broadcast (appliesToAllClasses) notification still reaches every child', () async {
        await _seedNotification(
          firestore,
          title: 'School-wide notice',
          appliesToAllClasses: true,
        );
        final result = await service.getNotificationsForAudience('Parents');
        final n = result.single;

        expect(relevantTo(n, studentId: amenahId, classId: classX), isTrue);
        expect(relevantTo(n, studentId: abdulId, classId: classY), isTrue);
      });
    },
  );

  group('ParentDashboard — selected child notification targeting (Test 8, Test 9)', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    Future<void> seedChild(
      String id, {
      required String name,
      required String classId,
    }) async {
      await firestore.collection('students').doc(id).set({
        'name': name,
        'admissionNo': 'ADM-$id',
        'classId': classId,
        'section': 'A',
        'isActive': true,
      });
      await firestore.collection('user_student_links').add({
        'userId': 'parent-1',
        'studentId': id,
      });
    }

    Widget buildDashboard() {
      return ProviderScope(
        overrides: [
          currentUserProvider.overrideWith(
            (ref) => AppUser(
              id: 'parent-1',
              phone: '9999999999',
              name: 'Test Parent',
              role: 'parent',
              isActive: true,
            ),
          ),
        ],
        child: MaterialApp(
          home: ParentDashboard(
            parentService: ParentService(firestore: firestore),
            attendanceService: AttendanceService(
              firestore: firestore,
              storage: MockFirebaseStorage(),
            ),
            feeService: FeeService(
              firestore: firestore,
              auth: MockFirebaseAuth(),
              storage: MockFirebaseStorage(),
            ),
            notificationService: AdminNotificationService(
              firestore: firestore,
              storage: MockFirebaseStorage(),
              filePicker: _UnusedFilePicker(),
            ),
            classService: ClassService(firestore: firestore),
            moodCheckinService: MoodCheckinService(
              firestore: firestore,
              storage: MockFirebaseStorage(),
            ),
            leaveService: LeaveService(firestore: firestore),
          ),
        ),
      );
    }

    testWidgets('Test 8 — a single-child parent receives targeted and broadcast notifications correctly', (
      tester,
    ) async {
      await seedChild('student-amenah', name: 'Amenah Noor', classId: 'class-x');
      await _seedNotification(
        firestore,
        title: 'Only for Amenah',
        applicableStudentIds: ['student-amenah'],
      );
      await _seedNotification(
        firestore,
        title: 'School-wide notice',
        appliesToAllClasses: true,
      );

      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Only for Amenah'), findsOneWidget);
      expect(find.text('School-wide notice'), findsOneWidget);
    });

    testWidgets('Test 9 — switching the selected child shows/hides a child-targeted notification live', (
      tester,
    ) async {
      await seedChild('student-amenah', name: 'Amenah Noor', classId: 'class-x');
      await seedChild('student-abdul', name: 'Abdul Hakeem Khan', classId: 'class-y');
      await _seedNotification(
        firestore,
        title: 'Only for Amenah',
        applicableStudentIds: ['student-amenah'],
      );

      await tester.pumpWidget(buildDashboard());
      await tester.pumpAndSettle();

      // Amenah is linked first and is selected by default.
      expect(find.text('Only for Amenah'), findsOneWidget);

      // Switch to Abdul via the child selector chip — the notification
      // targeted specifically to Amenah must disappear.
      await tester.tap(find.text('Abdul Hakeem Khan'));
      await tester.pumpAndSettle();
      expect(find.text('Only for Amenah'), findsNothing);

      // Switch back to Amenah — it must reappear, proving the Dashboard
      // re-derives relevance from the live selected child rather than a
      // value cached once at load time.
      await tester.tap(find.text('Amenah Noor'));
      await tester.pumpAndSettle();
      expect(find.text('Only for Amenah'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
