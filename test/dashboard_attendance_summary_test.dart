// ATT-06: the Staff/Admin Dashboard's attendance summary was missing Total
// Staff and Total People, and its "Not Marked Today" calculation assumed
// Not Marked = Total - Present - Absent — which silently double-counted a
// student on Approved Leave as Not Marked, since it never consulted
// LeaveService at all (the same class of bug fixed for the Attendance
// screen itself in ATT-01..05).
//
// These tests pump the REAL DashboardScreen (not a reimplementation of the
// summary math) so a regression in the actual wiring — not just the pure
// logic — would be caught here.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/admin/students/data/admin_student_service.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/attendance/providers/attendance_provider.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/classes/providers/class_provider.dart';
import 'package:montessori_app/modules/dashboard/ui/dashboard_screen.dart';
import 'package:montessori_app/modules/leave/models/leave_request_model.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/providers/mood_checkin_provider.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/students/data/student_service.dart';
import 'package:montessori_app/modules/students/providers/student_provider.dart';
import 'package:montessori_app/services/user_session_log_service.dart';

class _UnusedFilePicker extends FilePicker {}

LeaveService _leaveService(FakeFirebaseFirestore firestore) => LeaveService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );

Future<void> _seedStudent(
  FakeFirebaseFirestore firestore,
  String id,
  String name, {
  bool isActive = true,
}) async {
  await firestore.collection('students').doc(id).set({
    'name': name,
    'admissionNo': 'ADM-$id',
    'isActive': isActive,
    'classId': '',
  });
}

Future<void> _seedStaff(
  FakeFirebaseFirestore firestore,
  String id,
  String name, {
  String role = 'staff',
  bool isActive = true,
}) async {
  await firestore.collection('users').doc(id).set({
    'name': name,
    'phone': '9$id',
    'role': role,
    'isActive': isActive,
  });
}

Future<void> _seedAttendanceToday(
  FakeFirebaseFirestore firestore, {
  required String entityType,
  required String entityId,
  required String status,
}) async {
  final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());
  await firestore
      .collection('attendance')
      .doc('${dateKey}_${entityType}_$entityId')
      .set({
    'entityType': entityType,
    'entityId': entityId,
    'date': dateKey,
    'status': status,
  });
}

Future<void> _approveStudentLeaveToday(
  LeaveService service, {
  required String studentId,
  required String studentName,
}) async {
  final today = DateTime.now().toLocal();
  final id = await service.submitStudentLeaveRequest(
    requesterId: 'staff-1',
    requesterName: 'Teacher Priya',
    requesterRole: LeaveRequesterRole.staff,
    studentId: studentId,
    studentName: studentName,
    leaveType: LeaveType.sick,
    startDate: today,
    endDate: today,
    reason: 'Fever',
  );
  await service.approveLeaveRequest(id, reviewedBy: 'admin-1');
}

Future<String> _approveStaffLeaveToday(
  LeaveService service, {
  required String requesterId,
  required String requesterName,
}) async {
  final today = DateTime.now().toLocal();
  final id = await service.submitLeaveRequest(
    requesterId: requesterId,
    requesterName: requesterName,
    leaveType: LeaveType.sick,
    startDate: today,
    endDate: today,
    reason: 'Fever',
  );
  await service.approveLeaveRequest(id, reviewedBy: 'admin-1');
  return id;
}

/// Drains the known, expected build-time exceptions from other pre-existing
/// widgets on this screen that reach for real Firebase singletons directly
/// (e.g. `_DashboardHeader`'s `FirebaseAuth.instance.currentUser`) —
/// unrelated to the attendance summary under test here. Same helper
/// `dashboard_navigation_mapping_test.dart` uses for the same reason.
void _drainExpectedFirebaseSingletonErrors(WidgetTester tester) {
  for (var i = 0; i < 10; i++) {
    if (tester.takeException() == null) return;
  }
}

Widget _buildDashboard(
  FakeFirebaseFirestore firestore, {
  required LeaveService leaveService,
}) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => AppUser(id: 'u1', phone: '9999999999', role: 'staff', isActive: true),
      ),
      attendanceServiceProvider.overrideWithValue(
        AttendanceService(firestore: firestore, storage: MockFirebaseStorage()),
      ),
      classServiceProvider.overrideWithValue(ClassService(firestore: firestore)),
      studentServiceProvider.overrideWithValue(StudentService(firestore: firestore)),
      moodCheckinServiceProvider.overrideWithValue(
        MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage()),
      ),
    ],
    child: MaterialApp(
      home: DashboardScreen(
        userService: UserService(firestore),
        userSessionLogService: UserSessionLogService(
          firebaseAuth: MockFirebaseAuth(),
          firestore: firestore,
          userService: UserService(firestore),
        ),
        adminStudentService: AdminStudentService(
          firestore: firestore,
          storage: MockFirebaseStorage(),
        ),
        classService: ClassService(firestore: firestore),
        leaveService: leaveService,
      ),
    ),
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  FakeFirebaseFirestore firestore, {
  required LeaveService leaveService,
}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_buildDashboard(firestore, leaveService: leaveService));
  await tester.pumpAndSettle();
  _drainExpectedFirebaseSingletonErrors(tester);
}

// Reads the value shown under a given metric card's label — _MetricCard
// renders exactly two Text widgets inside its Card (label, then value).
String _metricValue(WidgetTester tester, String label) {
  final card = find.ancestor(of: find.text(label), matching: find.byType(Card));
  final texts = tester
      .widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)))
      .toList();
  return texts[1].data ?? '';
}

void main() {
  group('Dashboard attendance summary (ATT-06)', () {
    testWidgets('Total Students counts active students only', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      await _seedStudent(firestore, 'student-2', 'Diya');
      await _seedStudent(firestore, 'student-3', 'Inactive Ishaan', isActive: false);
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Total Students'), '2');
    });

    testWidgets('Total Staff counts active staff only, not today\'s attendance', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      await _seedStaff(firestore, 'staff-2', 'Teacher Raj', role: 'teacher');
      await _seedStaff(firestore, 'staff-3', 'Inactive Nurse', isActive: false);
      // Not marked present/absent today — Total Staff must still count them.
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Total Staff'), '2');
    });

    testWidgets('Total People = Total Students + Total Staff', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      await _seedStudent(firestore, 'student-2', 'Diya');
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Total Students'), '2');
      expect(_metricValue(tester, 'Total Staff'), '1');
      expect(_metricValue(tester, 'Total People'), '3');
    });

    testWidgets('Students Present Today counts today\'s Present student records', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      await _seedStudent(firestore, 'student-2', 'Diya');
      await _seedAttendanceToday(firestore, entityType: 'student', entityId: 'student-1', status: 'present');
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Students Present Today'), '1');
    });

    testWidgets('Staff Present Today counts today\'s Present staff records', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      await _seedStaff(firestore, 'staff-2', 'Teacher Raj');
      await _seedAttendanceToday(firestore, entityType: 'staff', entityId: 'staff-1', status: 'present');
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Staff Present Today'), '1');
    });

    testWidgets('an approved student leave with no attendance record is not counted as Not Marked', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav'); // present
      await _seedStudent(firestore, 'student-2', 'Diya'); // absent
      await _seedStudent(firestore, 'student-3', 'On Leave Ishaan'); // approved leave, no record
      await _seedAttendanceToday(firestore, entityType: 'student', entityId: 'student-1', status: 'present');
      await _seedAttendanceToday(firestore, entityType: 'student', entityId: 'student-2', status: 'absent');
      final leaveService = _leaveService(firestore);
      await _approveStudentLeaveToday(leaveService, studentId: 'student-3', studentName: 'On Leave Ishaan');

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      // All 3 students are accounted for (present/absent/on leave) — none
      // left over as Not Marked.
      expect(_metricValue(tester, 'Not Marked Today'), '0');
    });

    testWidgets('an approved staff leave with no attendance record is not counted as Not Marked (ATT-06 completion: Staff Leave -> Attendance)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      final leaveService = _leaveService(firestore);
      await _approveStaffLeaveToday(leaveService, requesterId: 'staff-1', requesterName: 'Teacher Priya');

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      // Staff Leave is now wired into Attendance's on-leave resolution the
      // same way Student Leave already was — an approved leave with no
      // attendance record must not inflate Not Marked Today.
      expect(_metricValue(tester, 'Total Staff'), '1');
      expect(_metricValue(tester, 'Staff Present Today'), '0');
      expect(_metricValue(tester, 'Not Marked Today'), '0');
    });

    testWidgets('a Present staff record takes precedence over an approved staff leave on the same day', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      await _seedAttendanceToday(firestore, entityType: 'staff', entityId: 'staff-1', status: 'present');
      final leaveService = _leaveService(firestore);
      await _approveStaffLeaveToday(leaveService, requesterId: 'staff-1', requesterName: 'Teacher Priya');

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Staff Present Today'), '1');
      expect(_metricValue(tester, 'Not Marked Today'), '0');
    });

    testWidgets('a Student Leave request does not affect Staff counts, and a Staff Leave request does not affect Student counts', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      final leaveService = _leaveService(firestore);
      await _approveStudentLeaveToday(leaveService, studentId: 'student-1', studentName: 'Aarav');
      await _approveStaffLeaveToday(leaveService, requesterId: 'staff-1', requesterName: 'Teacher Priya');

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      // Both populations are fully accounted for as On Leave (the student
      // by Student Leave, the staff member by Staff Leave) — cross-leakage
      // between the two would show up as a stray Not Marked.
      expect(_metricValue(tester, 'Not Marked Today'), '0');
    });

    testWidgets('a Present record takes precedence over an approved leave on the same day', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      await _seedAttendanceToday(firestore, entityType: 'student', entityId: 'student-1', status: 'present');
      final leaveService = _leaveService(firestore);
      await _approveStudentLeaveToday(leaveService, studentId: 'student-1', studentName: 'Aarav');

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Students Present Today'), '1');
      expect(_metricValue(tester, 'Not Marked Today'), '0');
    });

    testWidgets('an Absent record takes precedence over an approved leave on the same day', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      await _seedAttendanceToday(firestore, entityType: 'student', entityId: 'student-1', status: 'absent');
      final leaveService = _leaveService(firestore);
      await _approveStudentLeaveToday(leaveService, studentId: 'student-1', studentName: 'Aarav');

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      // Absent, not Present, and not folded into Not Marked either.
      expect(_metricValue(tester, 'Students Present Today'), '0');
      expect(_metricValue(tester, 'Not Marked Today'), '0');
    });

    testWidgets('does not regress with zero staff', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Total Staff'), '0');
      expect(_metricValue(tester, 'Staff Present Today'), '0');
      expect(_metricValue(tester, 'Total People'), '1');
      expect(_metricValue(tester, 'Not Marked Today'), '1');
    });

    testWidgets('does not regress with zero students', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(_metricValue(tester, 'Total Students'), '0');
      expect(_metricValue(tester, 'Students Present Today'), '0');
      expect(_metricValue(tester, 'Total People'), '1');
      expect(_metricValue(tester, 'Not Marked Today'), '1');
    });

    testWidgets('Total Students, Total Staff, and Total People cards are all visible together', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav');
      await _seedStaff(firestore, 'staff-1', 'Teacher Priya');
      final leaveService = _leaveService(firestore);

      await _pumpDashboard(tester, firestore, leaveService: leaveService);

      expect(find.text('Total Students'), findsOneWidget);
      expect(find.text('Total Staff'), findsOneWidget);
      expect(find.text('Total People'), findsOneWidget);
      expect(find.text('Students Present Today'), findsOneWidget);
      expect(find.text('Staff Present Today'), findsOneWidget);
      expect(find.text('Not Marked Today'), findsOneWidget);
      expect(find.text('Mood Check-ins Today'), findsOneWidget);
      expect(find.text('Alerts / Distress'), findsOneWidget);
    });
  });
}
