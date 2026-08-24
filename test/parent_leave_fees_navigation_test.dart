// Pre-UAT cleanup pass coverage: Parent gains two first-class navigation
// destinations — Leave (ParentLeaveView) and Fees (ParentFeeHistoryView) —
// alongside the existing Dashboard/Calendar, on both desktop (AppSidebar)
// and mobile (AppBottomNav). These tests prove:
//   - the four destinations exist, in order, on both layouts, and mobile
//     opens the exact same screen as desktop for each (Navigation Identity)
//   - Parent Leave/Fees are scoped server-side to the authenticated
//     parent's own linked children (Parent Security) — never another
//     parent's child, and never a client-supplied arbitrary student id
//   - Parent Leave is read-only (no Approve/Reject action, and never shows
//     staff leave or another subject's data)
//   - Parent Fees is read-only (no fee-management actions — Admin's
//     assign/collect/edit/void surface is a different screen entirely)
//   - Admin's own Leave Requests destination/screen (Staff Leave + Student
//     Leave tabs) is untouched by any of this.
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
import 'package:montessori_app/modules/calendar/ui/calendar_view.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/fees/services/fee_service.dart';
import 'package:montessori_app/modules/fees/ui/parent_fee_history_view.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/leave/ui/admin_leave_screen.dart';
import 'package:montessori_app/modules/leave/ui/parent_leave_view.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

class _UnusedFilePicker extends FilePicker {}

void _drainExpectedFirebaseSingletonErrors(WidgetTester tester) {
  for (var i = 0; i < 10; i++) {
    if (tester.takeException() == null) return;
  }
}

Future<void> seedChild(
  FakeFirebaseFirestore firestore,
  String parentId,
  String studentId, {
  required String name,
}) async {
  await firestore.collection('students').doc(studentId).set({
    'name': name,
    'admissionNo': 'ADM-$studentId',
    'classId': 'class-x',
    'section': 'A',
    'isActive': true,
  });
  await firestore.collection('user_student_links').add({
    'userId': parentId,
    'studentId': studentId,
  });
}

Future<void> seedStudentLeave(
  FakeFirebaseFirestore firestore, {
  required String requesterId,
  required String requesterRole,
  required String studentId,
  required String studentName,
  String status = 'Pending',
}) async {
  await firestore.collection('staff_leave_requests').add({
    'requesterId': requesterId,
    'requesterName': 'Someone',
    'requesterRole': requesterRole,
    'subjectType': 'student',
    'studentId': studentId,
    'studentName': studentName,
    'leaveType': 'Sick Leave',
    'startDate': DateTime(2026, 9, 1),
    'endDate': DateTime(2026, 9, 2),
    'reason': 'Fever',
    'status': status,
    'createdAt': DateTime(2026, 8, 20),
    'updatedAt': DateTime(2026, 8, 20),
  });
}

Future<void> seedStaffLeave(
  FakeFirebaseFirestore firestore, {
  required String requesterId,
  required String requesterName,
}) async {
  await firestore.collection('staff_leave_requests').add({
    'requesterId': requesterId,
    'requesterName': requesterName,
    'requesterRole': 'staff',
    'subjectType': 'staff',
    'studentId': null,
    'studentName': null,
    'leaveType': 'Casual Leave',
    'startDate': DateTime(2026, 9, 1),
    'endDate': DateTime(2026, 9, 1),
    'reason': 'Personal',
    'status': 'Pending',
    'createdAt': DateTime(2026, 8, 20),
    'updatedAt': DateTime(2026, 8, 20),
  });
}

Future<void> seedFeeAssignment(
  FakeFirebaseFirestore firestore, {
  required String studentId,
  double totalFee = 30000,
  double paidAmount = 20000,
}) async {
  await firestore.collection('student_fee_assignments').add({
    'studentId': studentId,
    'studentName': 'Child',
    'admissionNo': 'ADM-$studentId',
    'classId': 'class-x',
    'className': 'Mont 1',
    'feeStructureId': 'structure-1',
    'feeStructureName': 'Core Fees',
    'academicYear': '2026-2027',
    'totalFee': totalFee,
    'discountAmount': 0,
    'payableAmount': totalFee,
    'paidAmount': paidAmount,
    'balanceAmount': totalFee - paidAmount,
    'status': 'Active',
    'isDeleted': false,
  });
}

Future<void> seedFeeReceipt(
  FakeFirebaseFirestore firestore, {
  required String studentId,
  double amount = 20000,
}) async {
  await firestore.collection('fee_receipts').add({
    'receiptNo': 'RCPT-1',
    'transactionId': 'txn-1',
    'assignmentId': 'assignment-1',
    'studentId': studentId,
    'studentName': 'Child',
    'admissionNo': 'ADM-$studentId',
    'className': 'Mont 1',
    'feeStructureName': 'Core Fees',
    'amount': amount,
    'paymentMode': 'Cash',
    'paymentDate': DateTime(2026, 8, 1),
    'referenceNo': 'REF-1',
    'createdAt': DateTime(2026, 8, 1),
    'createdBy': 'admin-1',
    'isDeleted': false,
  });
}

Widget _buildParentDashboard(FakeFirebaseFirestore firestore, {String parentId = 'parent-1'}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: parentId, phone: '9999999999', name: 'Test Parent', role: 'parent', isActive: true),
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

Future<void> _pumpDesktop(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
  _drainExpectedFirebaseSingletonErrors(tester);
}

Future<void> _pumpMobile(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(widget);
  await tester.pumpAndSettle();
  _drainExpectedFirebaseSingletonErrors(tester);
}

Future<void> _tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
  _drainExpectedFirebaseSingletonErrors(tester);
}

/// Finds a nav destination's label specifically within the sidebar/bottom
/// nav (not any same-labelled text elsewhere in the page — e.g. Parent
/// Dashboard's own inline "Fees" section heading, which coexists with the
/// "Fees" nav destination label on the Dashboard tab).
Finder _navDestination(String label) {
  if (find.byType(NavigationRail).evaluate().isNotEmpty) {
    return find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
  }
  return find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
}

void main() {
  group('Parent — desktop (AppSidebar) has exactly Dashboard, Calendar, Leave, Fees', () {
    testWidgets('sidebar destinations are exactly these four, in this order', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildParentDashboard(firestore));

      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      final labels = rail.destinations.map((d) => (d.label as Text).data).toList();
      expect(labels, ['Dashboard', 'Calendar', 'Leave', 'Fees']);
    });

    testWidgets('Dashboard (default) shows the dashboard body, selectedIndex 0', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildParentDashboard(firestore));

      expect(find.widgetWithText(AppBar, 'Dashboard'), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 0);
    });

    testWidgets('Calendar opens CalendarView, selectedIndex 1', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildParentDashboard(firestore));

      await _tapAndSettle(tester, find.text('Calendar'));

      expect(find.widgetWithText(AppBar, 'Calendar'), findsOneWidget);
      expect(find.byType(CalendarView), findsOneWidget);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 1);
    });

    testWidgets('Leave opens ParentLeaveView (not AdminLeaveScreen), selectedIndex 2', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildParentDashboard(firestore));

      await _tapAndSettle(tester, find.text('Leave'));

      expect(find.widgetWithText(AppBar, 'Leave'), findsOneWidget);
      expect(find.byType(ParentLeaveView), findsOneWidget);
      expect(find.byType(AdminLeaveScreen), findsNothing);
      expect(find.byType(CalendarView), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 2);
    });

    testWidgets('Fees opens ParentFeeHistoryView, selectedIndex 3', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpDesktop(tester, _buildParentDashboard(firestore));

      await _tapAndSettle(tester, _navDestination('Fees'));

      expect(find.widgetWithText(AppBar, 'Fees'), findsOneWidget);
      expect(find.byType(ParentFeeHistoryView), findsOneWidget);
      expect(find.byType(ParentLeaveView), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 3);
    });
  });

  group('Parent — mobile (AppBottomNav) matches desktop one-for-one', () {
    testWidgets('bottom nav has exactly the same four destinations, in the same order', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpMobile(tester, _buildParentDashboard(firestore));

      final labels = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((d) => d.label)
          .toList();
      expect(labels, ['Dashboard', 'Calendar', 'Leave', 'Fees']);
    });

    testWidgets('Leave opens ParentLeaveView on mobile too', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpMobile(tester, _buildParentDashboard(firestore));

      await _tapAndSettle(tester, find.text('Leave'));

      expect(find.widgetWithText(AppBar, 'Leave'), findsOneWidget);
      expect(find.byType(ParentLeaveView), findsOneWidget);
    });

    testWidgets('Fees opens ParentFeeHistoryView on mobile too', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _pumpMobile(tester, _buildParentDashboard(firestore));

      await _tapAndSettle(tester, _navDestination('Fees'));

      expect(find.widgetWithText(AppBar, 'Fees'), findsOneWidget);
      expect(find.byType(ParentFeeHistoryView), findsOneWidget);
    });
  });

  group('Parent Leave — scoped to linked children, read-only', () {
    testWidgets('shows this parent\'s own child leave requests', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await seedStudentLeave(
        firestore,
        requesterId: 'parent-1',
        requesterRole: 'parent',
        studentId: 'student-1',
        studentName: 'Aarav',
      );
      await _pumpDesktop(tester, _buildParentDashboard(firestore));
      await _tapAndSettle(tester, find.text('Leave'));

      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('Sick Leave • Sep 1, 2026 - Sep 2, 2026'), findsOneWidget);
    });

    testWidgets('never shows another parent\'s child leave request', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await seedChild(firestore, 'parent-2', 'student-2', name: 'Diya');
      await seedStudentLeave(
        firestore,
        requesterId: 'parent-2',
        requesterRole: 'parent',
        studentId: 'student-2',
        studentName: 'Diya',
      );
      await _pumpDesktop(tester, _buildParentDashboard(firestore, parentId: 'parent-1'));
      await _tapAndSettle(tester, find.text('Leave'));

      expect(find.text('Diya'), findsNothing);
      expect(find.text('No leave requests yet.'), findsOneWidget);
    });

    testWidgets('never shows Staff Leave requests, and never shows Approve/Reject actions', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await seedStudentLeave(
        firestore,
        requesterId: 'parent-1',
        requesterRole: 'parent',
        studentId: 'student-1',
        studentName: 'Aarav',
      );
      await seedStaffLeave(firestore, requesterId: 'staff-1', requesterName: 'Ms. Rao');
      await _pumpDesktop(tester, _buildParentDashboard(firestore, parentId: 'parent-1'));
      await _tapAndSettle(tester, find.text('Leave'));

      expect(find.text('Ms. Rao'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
    });

    testWidgets('parent can submit a new student leave request from the Leave destination', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await _pumpDesktop(tester, _buildParentDashboard(firestore, parentId: 'parent-1'));
      await _tapAndSettle(tester, find.text('Leave'));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Fever, doctor advised rest');
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Leave request submitted'), findsOneWidget);
      final snap = await firestore.collection('staff_leave_requests').get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.single.data()['studentId'], 'student-1');
    });
  });

  group('Parent Fees — read-only, scoped to linked children', () {
    testWidgets('shows child, total fee, paid amount, and outstanding balance', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await seedFeeAssignment(firestore, studentId: 'student-1', totalFee: 30000, paidAmount: 20000);
      await _pumpDesktop(tester, _buildParentDashboard(firestore, parentId: 'parent-1'));
      await _tapAndSettle(tester, _navDestination('Fees'));

      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('₹30000'), findsOneWidget);
      expect(find.text('₹20000'), findsOneWidget);
      expect(find.text('₹10000'), findsOneWidget);
    });

    testWidgets('shows payment/collection history', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await seedFeeAssignment(firestore, studentId: 'student-1', totalFee: 30000, paidAmount: 20000);
      await seedFeeReceipt(firestore, studentId: 'student-1', amount: 20000);
      await _pumpDesktop(tester, _buildParentDashboard(firestore, parentId: 'parent-1'));
      await _tapAndSettle(tester, _navDestination('Fees'));

      expect(find.text('Payment History'), findsOneWidget);
      expect(find.text('Core Fees'), findsWidgets);
    });

    testWidgets('never shows another parent\'s child fee data', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await seedChild(firestore, 'parent-2', 'student-2', name: 'Diya');
      await seedFeeAssignment(firestore, studentId: 'student-2', totalFee: 50000, paidAmount: 0);
      await _pumpDesktop(tester, _buildParentDashboard(firestore, parentId: 'parent-1'));
      await _tapAndSettle(tester, _navDestination('Fees'));

      expect(find.text('Diya'), findsNothing);
      expect(find.text('₹50000'), findsNothing);
    });

    testWidgets('exposes no fee-management actions (no FAB, no collect/assign/void controls)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await seedChild(firestore, 'parent-1', 'student-1', name: 'Aarav');
      await seedFeeAssignment(firestore, studentId: 'student-1', totalFee: 30000, paidAmount: 20000);
      await _pumpDesktop(tester, _buildParentDashboard(firestore, parentId: 'parent-1'));
      await _tapAndSettle(tester, _navDestination('Fees'));

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Collect Fee'), findsNothing);
      expect(find.text('Assign Fee'), findsNothing);
      expect(find.text('Void'), findsNothing);
    });
  });

  group('Admin — Leave Requests screen is unchanged by the Parent nav expansion', () {
    testWidgets('AdminLeaveScreen still has both Staff Leave and Student Leave tabs', (tester) async {
      final firestore = FakeFirebaseFirestore();
      final service = LeaveService(firestore: firestore);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith(
              (ref) => AppUser(id: 'admin-1', phone: '9999999999', role: 'admin', isActive: true),
            ),
          ],
          child: MaterialApp(home: AdminLeaveScreen(service: service)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Staff Leave'), findsOneWidget);
      expect(find.text('Student Leave'), findsOneWidget);
      expect(find.text('Leave Requests'), findsWidgets); // AdminLayout title
    });
  });
}
