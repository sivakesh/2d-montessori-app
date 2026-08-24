// Widget-level coverage for the Parent -> Child Leave feature added to
// ParentDashboard: the new "Leave Requests" section shows the selected
// child's leave history and a "Request Leave" action, without disturbing
// any other existing Parent Dashboard content (regression #29).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/dialogs/student_leave_request_dialog.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class _UnusedFilePicker extends FilePicker {}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedChild(String id, {required String name}) async {
    await firestore.collection('students').doc(id).set({
      'name': name,
      'admissionNo': 'ADM-$id',
      'classId': 'class-x',
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
          (ref) => AppUser(id: 'parent-1', phone: '9999999999', name: 'Test Parent', role: 'parent', isActive: true),
        ),
      ],
      child: MaterialApp(
        home: ParentDashboard(
          parentService: ParentService(firestore: firestore),
          attendanceService: AttendanceService(firestore: firestore, storage: MockFirebaseStorage()),
          feeService: FeeService(firestore: firestore, auth: MockFirebaseAuth(), storage: MockFirebaseStorage()),
          notificationService: AdminNotificationService(
            firestore: firestore,
            storage: MockFirebaseStorage(),
            filePicker: _UnusedFilePicker(),
          ),
          classService: ClassService(firestore: firestore),
          moodCheckinService: MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage()),
          leaveService: LeaveService(
            firestore: firestore,
            notificationService: AdminNotificationService(
              firestore: firestore,
              storage: MockFirebaseStorage(),
              filePicker: _UnusedFilePicker(),
            ),
            parentService: ParentService(firestore: firestore),
          ),
        ),
      ),
    );
  }

  testWidgets('shows "Request Leave" and an empty state when the child has no leave requests yet', (tester) async {
    await seedChild('student-1', name: 'Aarav');
    await tester.pumpWidget(buildDashboard());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Leave Requests'), findsOneWidget);
    expect(find.text('Request Leave'), findsOneWidget);
    expect(find.text('No leave requests for this child yet.'), findsOneWidget);
  });

  testWidgets('parent can submit a leave request for their single linked child end-to-end', (tester) async {
    await seedChild('student-1', name: 'Aarav');
    await tester.pumpWidget(buildDashboard());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Request Leave'));
    await tester.tap(find.text('Request Leave'));
    await tester.pumpAndSettle();

    expect(find.byType(StudentLeaveRequestDialog), findsOneWidget);
    // Single linked child is pre-selected — no dropdown interaction needed.
    await tester.enterText(find.byType(TextFormField).last, 'Fever, doctor advised rest');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(StudentLeaveRequestDialog), findsNothing);
    expect(find.text('Leave request submitted'), findsOneWidget);

    final snap = await firestore.collection('staff_leave_requests').get();
    expect(snap.docs, hasLength(1));
    expect(snap.docs.single.data()['studentId'], 'student-1');
    expect(snap.docs.single.data()['requesterRole'], 'parent');
  });

  testWidgets('a parent with two children can choose which child the leave request is for', (tester) async {
    await seedChild('student-1', name: 'Aarav');
    await seedChild('student-2', name: 'Diya');
    await tester.pumpWidget(buildDashboard());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Request Leave'));
    await tester.tap(find.text('Request Leave'));
    await tester.pumpAndSettle();

    // Both children must be offered in the dropdown.
    await tester.tap(find.text('Child'));
    await tester.pumpAndSettle();
    expect(find.text('Aarav').hitTestable(), findsOneWidget);
    expect(find.text('Diya').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Diya').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, 'Family function');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    final snap = await firestore.collection('staff_leave_requests').get();
    expect(snap.docs.single.data()['studentId'], 'student-2');
  });

  testWidgets('regression: existing Parent Dashboard content (welcome card, fees) still renders', (tester) async {
    await seedChild('student-1', name: 'Aarav');
    await tester.pumpWidget(buildDashboard());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Good'), findsOneWidget); // WelcomeCard greeting
    // findsWidgets (not findsOneWidget): Parent's own "Fees" nav destination
    // (added in the pre-UAT cleanup pass) now also renders this label, in
    // addition to the dashboard's Fees section heading this test originally
    // targeted.
    expect(find.text('Fees'), findsWidgets);
    expect(find.text('Aarav'), findsWidgets);
  });
}
