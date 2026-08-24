// ATT-06 completion: Staff Attendance parity — widget-level coverage for
// the Staff Leave -> Attendance integration on the REAL Staff Attendance
// screen (AttendanceScreen's Today tab), mirroring exactly the coverage
// attendance_screen_leave_integration_test.dart already has for Student
// Leave. Pumps the real widget rather than testing a reimplementation of
// the resolution logic.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/attendance/data/attendance_service.dart';
import 'package:montessori_app/modules/attendance/providers/attendance_provider.dart';
import 'package:montessori_app/modules/attendance/ui/attendance_screen.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/classes/data/class_service.dart';
import 'package:montessori_app/modules/classes/providers/class_provider.dart';
import 'package:montessori_app/modules/leave/models/leave_request_model.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/mood_checkin/providers/mood_checkin_provider.dart';
import 'package:montessori_app/modules/mood_checkin/services/mood_checkin_service.dart';
import 'package:montessori_app/modules/students/data/student_service.dart';
import 'package:montessori_app/modules/students/providers/student_provider.dart';

class _UnusedFilePicker extends FilePicker {}

LeaveService _leaveService(FakeFirebaseFirestore firestore) => LeaveService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );

String _todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now().toLocal());

Future<void> _seedStudent(
  FakeFirebaseFirestore firestore,
  String id,
  String name,
) async {
  await firestore.collection('students').doc(id).set({
    'name': name,
    'admissionNo': 'ADM-$id',
    'isActive': true,
    'classId': '',
  });
}

Future<void> _seedStaff(
  FakeFirebaseFirestore firestore,
  String id,
  String name,
) async {
  await firestore.collection('users').doc(id).set({
    'name': name,
    'phone': '9$id',
    'role': 'staff',
    'isActive': true,
  });
}

Future<void> _seedAttendance(
  FakeFirebaseFirestore firestore, {
  required String entityType,
  required String entityId,
  required String status,
}) async {
  final dateKey = _todayKey();
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

Future<String> _approveStaffLeaveCoveringToday(
  LeaveService service, {
  required String staffId,
  required String staffName,
}) async {
  final today = DateTime.now().toLocal();
  final id = await service.submitLeaveRequest(
    requesterId: staffId,
    requesterName: staffName,
    leaveType: LeaveType.sick,
    startDate: DateTime(today.year, today.month, today.day),
    endDate: DateTime(today.year, today.month, today.day),
    reason: 'Fever',
  );
  await service.approveLeaveRequest(id, reviewedBy: 'admin-1');
  return id;
}

Future<void> _pumpAttendanceScreen(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required LeaveService leaveService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => AppUser(
            id: 'staff-1',
            phone: '9999999999',
            name: 'Teacher Priya',
            role: 'staff',
            isActive: true,
          ),
        ),
        classServiceProvider.overrideWithValue(
          ClassService(firestore: firestore),
        ),
        studentServiceProvider.overrideWithValue(
          StudentService(firestore: firestore),
        ),
        attendanceServiceProvider.overrideWithValue(
          AttendanceService(firestore: firestore, storage: MockFirebaseStorage()),
        ),
        moodCheckinServiceProvider.overrideWithValue(
          MoodCheckinService(firestore: firestore, storage: MockFirebaseStorage()),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: AttendanceScreen(
            leaveService: leaveService,
            userService: UserService(firestore),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Scopes a finder to the one attendance row/card for [name] — needed because
// the summary section above the list also renders bare "Present" / "Absent"
// / "Not Marked" text as its own labels, so an unscoped find.text(status)
// matches both the summary label and the row's own status pill.
Finder _rowFor(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(Card)).first;

Finder _statusTextIn(String name, String status) =>
    find.descendant(of: _rowFor(name), matching: find.text(status));

IconButton _absentButtonFor(WidgetTester tester, String name) {
  final finder = find.descendant(
    of: _rowFor(name),
    matching: find.ancestor(
      of: find.byIcon(Icons.person_off),
      matching: find.byType(IconButton),
    ),
  );
  return tester.widget<IconButton>(finder);
}

void main() {
  group('AttendanceScreen (Staff Attendance) — Staff Leave integration', () {
    testWidgets('a staff member with no attendance record stays Not Marked', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Not Marked'), findsOneWidget);
      expect(_absentButtonFor(tester, 'Malini').onPressed, isNotNull);
    });

    testWidgets('a staff member marked Present shows Present', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      await _seedAttendance(firestore, entityType: 'staff', entityId: 'staff-2', status: 'present');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Present'), findsOneWidget);
    });

    testWidgets('a staff member marked Absent shows Absent', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      await _seedAttendance(firestore, entityType: 'staff', entityId: 'staff-2', status: 'absent');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Absent'), findsOneWidget);
    });

    testWidgets('a staff member on approved leave today with no attendance record shows On Leave and cannot be marked Absent', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);
      await _approveStaffLeaveCoveringToday(leaveService, staffId: 'staff-2', staffName: 'Malini');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'On Leave'), findsOneWidget);
      expect(_statusTextIn('Malini', 'Not Marked'), findsNothing);
      expect(_absentButtonFor(tester, 'Malini').onPressed, isNull);
    });

    testWidgets('a staff member with Pending leave stays Not Marked', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);
      final today = DateTime.now().toLocal();
      await leaveService.submitLeaveRequest(
        requesterId: 'staff-2',
        requesterName: 'Malini',
        leaveType: LeaveType.sick,
        startDate: DateTime(today.year, today.month, today.day),
        endDate: DateTime(today.year, today.month, today.day),
        reason: 'Fever',
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Malini', 'On Leave'), findsNothing);
    });

    testWidgets('a staff member with Rejected leave stays Not Marked', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);
      final today = DateTime.now().toLocal();
      final id = await leaveService.submitLeaveRequest(
        requesterId: 'staff-2',
        requesterName: 'Malini',
        leaveType: LeaveType.sick,
        startDate: DateTime(today.year, today.month, today.day),
        endDate: DateTime(today.year, today.month, today.day),
        reason: 'Fever',
      );
      await leaveService.rejectLeaveRequest(id, reviewedBy: 'admin-1');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Malini', 'On Leave'), findsNothing);
    });

    testWidgets('a staff member whose approved leave does not cover today stays Not Marked', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);
      final farFuture = DateTime.now().toLocal().add(const Duration(days: 60));
      final id = await leaveService.submitLeaveRequest(
        requesterId: 'staff-2',
        requesterName: 'Malini',
        leaveType: LeaveType.sick,
        startDate: farFuture,
        endDate: farFuture,
        reason: 'Planned trip',
      );
      await leaveService.approveLeaveRequest(id, reviewedBy: 'admin-1');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Malini', 'On Leave'), findsNothing);
      expect(_absentButtonFor(tester, 'Malini').onPressed, isNotNull);
    });

    testWidgets('an existing Present record is not overwritten by an approved staff leave', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      await _seedAttendance(firestore, entityType: 'staff', entityId: 'staff-2', status: 'present');
      final leaveService = _leaveService(firestore);
      await _approveStaffLeaveCoveringToday(leaveService, staffId: 'staff-2', staffName: 'Malini');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Present'), findsOneWidget);
      expect(_statusTextIn('Malini', 'On Leave'), findsNothing);
    });

    testWidgets('an existing Absent record is not overwritten by an approved staff leave', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      await _seedAttendance(firestore, entityType: 'staff', entityId: 'staff-2', status: 'absent');
      final leaveService = _leaveService(firestore);
      await _approveStaffLeaveCoveringToday(leaveService, staffId: 'staff-2', staffName: 'Malini');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'Absent'), findsOneWidget);
      expect(_statusTextIn('Malini', 'On Leave'), findsNothing);
    });

    testWidgets('the Absent action is blocked (disabled) for a staff member On Leave', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);
      await _approveStaffLeaveCoveringToday(leaveService, staffId: 'staff-2', staffName: 'Malini');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      final button = _absentButtonFor(tester, 'Malini');
      expect(button.onPressed, isNull);
    });

    testWidgets('Student Leave does not affect a Staff member (isolation)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav Sharma');
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);
      final today = DateTime.now().toLocal();
      final id = await leaveService.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav Sharma',
        leaveType: LeaveType.sick,
        startDate: DateTime(today.year, today.month, today.day),
        endDate: DateTime(today.year, today.month, today.day),
        reason: 'Fever',
      );
      await leaveService.approveLeaveRequest(id, reviewedBy: 'admin-1');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Aarav Sharma', 'On Leave'), findsOneWidget);
      expect(_statusTextIn('Malini', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Malini', 'On Leave'), findsNothing);
    });

    testWidgets('Staff Leave does not affect a Student (isolation)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav Sharma');
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);
      await _approveStaffLeaveCoveringToday(leaveService, staffId: 'staff-2', staffName: 'Malini');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);

      expect(_statusTextIn('Malini', 'On Leave'), findsOneWidget);
      expect(_statusTextIn('Aarav Sharma', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Aarav Sharma', 'On Leave'), findsNothing);
    });
  });
}
