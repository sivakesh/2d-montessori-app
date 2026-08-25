// Widget-level coverage for the Student Leave -> Attendance integration on
// the REAL Staff Attendance screen (AttendanceScreen), not the Admin
// back-office one.
//
// This is the screen that was actually broken in UAT: Student Leave
// integration existed in AdminAttendanceManagementScreen (and its pure
// helpers were unit-tested — see attendance_summary_test.dart and
// student_leave_attendance_integration_test.dart), but Staff -> Attendance
// navigates to AttendanceScreen, which never consulted LeaveService at all.
// Those existing unit tests kept passing throughout, because they only
// exercised the pure helper, never the actual screen — so this file pumps
// the real widget instead.
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

Future<String> _approveStudentLeaveCoveringToday(
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
  group('AttendanceScreen (Staff Attendance) — Student Leave integration', () {
    testWidgets('a student on approved leave today with no attendance record shows On Leave and cannot be marked Absent', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav Sharma');
      final leaveService = _leaveService(firestore);
      await _approveStudentLeaveCoveringToday(
        leaveService,
        studentId: 'student-1',
        studentName: 'Aarav Sharma',
      );

      await _pumpAttendanceScreen(
        tester,
        firestore: firestore,
        leaveService: leaveService,
      );

      expect(_statusTextIn('Aarav Sharma', 'On Leave'), findsOneWidget);
      expect(_statusTextIn('Aarav Sharma', 'Not Marked'), findsNothing);
      expect(_absentButtonFor(tester, 'Aarav Sharma').onPressed, isNull);
    });

    testWidgets('a student with no attendance record and no approved leave stays Not Marked with actions available', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav Sharma');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(
        tester,
        firestore: firestore,
        leaveService: leaveService,
      );

      expect(_statusTextIn('Aarav Sharma', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Aarav Sharma', 'On Leave'), findsNothing);
      expect(_absentButtonFor(tester, 'Aarav Sharma').onPressed, isNotNull);
    });

    testWidgets('an existing Present record is not overwritten by an approved leave', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav Sharma');
      await _seedAttendance(
        firestore,
        entityType: 'student',
        entityId: 'student-1',
        status: 'present',
      );
      final leaveService = _leaveService(firestore);
      await _approveStudentLeaveCoveringToday(
        leaveService,
        studentId: 'student-1',
        studentName: 'Aarav Sharma',
      );

      await _pumpAttendanceScreen(
        tester,
        firestore: firestore,
        leaveService: leaveService,
      );

      expect(_statusTextIn('Aarav Sharma', 'Present'), findsOneWidget);
      expect(_statusTextIn('Aarav Sharma', 'On Leave'), findsNothing);
    });

    testWidgets('an existing Absent record is not overwritten by an approved leave', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav Sharma');
      await _seedAttendance(
        firestore,
        entityType: 'student',
        entityId: 'student-1',
        status: 'absent',
      );
      final leaveService = _leaveService(firestore);
      await _approveStudentLeaveCoveringToday(
        leaveService,
        studentId: 'student-1',
        studentName: 'Aarav Sharma',
      );

      await _pumpAttendanceScreen(
        tester,
        firestore: firestore,
        leaveService: leaveService,
      );

      expect(_statusTextIn('Aarav Sharma', 'Absent'), findsOneWidget);
      expect(_statusTextIn('Aarav Sharma', 'On Leave'), findsNothing);
    });

    testWidgets('a student whose approved leave does not cover today is not shown as On Leave', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Aarav Sharma');
      final leaveService = _leaveService(firestore);
      // 60 days out, nudged onto a weekday if it lands on a weekend — the
      // Student Leave 5-working-day cap rejects a weekend-only request, and
      // this date only needs to be "in the future", not any specific day.
      var farFuture = DateTime.now().toLocal().add(const Duration(days: 60));
      if (farFuture.weekday == DateTime.saturday) {
        farFuture = farFuture.add(const Duration(days: 2));
      } else if (farFuture.weekday == DateTime.sunday) {
        farFuture = farFuture.add(const Duration(days: 1));
      }
      final id = await leaveService.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav Sharma',
        leaveType: LeaveType.sick,
        startDate: farFuture,
        endDate: farFuture,
        reason: 'Planned trip',
      );
      await leaveService.approveLeaveRequest(id, reviewedBy: 'admin-1');

      await _pumpAttendanceScreen(
        tester,
        firestore: firestore,
        leaveService: leaveService,
      );

      expect(_statusTextIn('Aarav Sharma', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Aarav Sharma', 'On Leave'), findsNothing);
      expect(_absentButtonFor(tester, 'Aarav Sharma').onPressed, isNotNull);
    });

    testWidgets('staff attendance is completely unaffected by the Student Leave integration', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staffuser-1', 'Nurse Kavya');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(
        tester,
        firestore: firestore,
        leaveService: leaveService,
      );

      expect(find.text('Nurse Kavya'), findsOneWidget);
      expect(_statusTextIn('Nurse Kavya', 'Not Marked'), findsOneWidget);
      expect(_statusTextIn('Nurse Kavya', 'On Leave'), findsNothing);
      expect(_absentButtonFor(tester, 'Nurse Kavya').onPressed, isNotNull);
    });
  });
}
