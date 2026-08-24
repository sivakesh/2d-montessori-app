// Widget-level coverage for Staff -> Student Leave: MyLeaveView's "Student
// Leave" tab lets a staff member search for any active student and submit a
// leave request on their behalf, and only shows requests that staff member
// themselves submitted.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/my_leave_view.dart';
import 'package:montessori_app/modules/students/data/student_service.dart';

class _UnusedFilePicker extends FilePicker {}

ProviderScope _withStaffUser(Widget child) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'staff-1', phone: '9999999999', name: 'Teacher Priya', role: 'staff', isActive: true),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('17-18. Staff can search for an active student and submit a student leave request', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('students').doc('student-1').set({
      'name': 'Aarav Sharma',
      'admissionNo': 'ADM-1',
      'isActive': true,
    });
    await firestore.collection('students').doc('student-2').set({
      'name': 'Diya Mehta',
      'admissionNo': 'ADM-2',
      'isActive': true,
    });
    // Inactive student must not be offered.
    await firestore.collection('students').doc('student-3').set({
      'name': 'Inactive Ishaan',
      'admissionNo': 'ADM-3',
      'isActive': false,
    });
    final service = LeaveService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );

    await tester.pumpWidget(_withStaffUser(
      MyLeaveView(service: service, studentService: StudentService(firestore: firestore)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Student Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tap to select a student'));
    await tester.pumpAndSettle();

    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Diya Mehta'), findsOneWidget);
    expect(find.text('Inactive Ishaan'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Search student'), 'Diya');
    await tester.pumpAndSettle();
    expect(find.text('Aarav Sharma'), findsNothing);
    await tester.tap(find.text('Diya Mehta'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).last, 'Dental appointment');
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Student leave request submitted'), findsOneWidget);
    final snap = await firestore.collection('staff_leave_requests').get();
    expect(snap.docs.single.data()['studentId'], 'student-2');
    expect(snap.docs.single.data()['requesterRole'], 'staff');
  });

  testWidgets('19-20. Staff sees only their own submitted student leave requests', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = LeaveService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );
    await service.submitStudentLeaveRequest(
      requesterId: 'staff-1',
      requesterName: 'Teacher Priya',
      requesterRole: 'staff',
      studentId: 'student-1',
      studentName: 'Aarav Sharma',
      leaveType: 'Sick Leave',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 1),
      reason: 'Reported unwell',
    );
    await service.submitStudentLeaveRequest(
      requesterId: 'staff-2',
      requesterName: 'Teacher Raj',
      requesterRole: 'staff',
      studentId: 'student-2',
      studentName: 'Diya Mehta',
      leaveType: 'Sick Leave',
      startDate: DateTime(2026, 9, 2),
      endDate: DateTime(2026, 9, 2),
      reason: 'Reported unwell',
    );

    await tester.pumpWidget(_withStaffUser(MyLeaveView(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student Leave'));
    await tester.pumpAndSettle();

    expect(find.text('Aarav Sharma'), findsOneWidget);
    expect(find.text('Diya Mehta'), findsNothing);
  });

  testWidgets('regression: existing "My Leave" (self) tab is unaffected by the Student Leave tab', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = LeaveService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );
    await service.submitLeaveRequest(
      requesterId: 'staff-1',
      requesterName: 'Teacher Priya',
      leaveType: 'Casual Leave',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 1),
      reason: 'Personal work',
    );

    await tester.pumpWidget(_withStaffUser(MyLeaveView(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('My Leave'), findsOneWidget);
    expect(find.text('Casual Leave'), findsOneWidget);
  });
}
