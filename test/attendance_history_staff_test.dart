// ATT-06 completion: Staff Attendance parity — the Attendance -> History
// tab previously showed Students only. This covers the new Staff History
// section: same week/date structure, same Present/Absent/On Leave/"-"
// resolution pipeline, reusing resolveAttendanceDisplayStatus exactly like
// the Student History section does (see
// attendance_history_leave_integration_test.dart for the Student-side
// coverage this mirrors). Pumps the real AttendanceScreen.
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

DateTime _startOfWeek(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

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

Future<void> _seedAttendanceOn(
  FakeFirebaseFirestore firestore,
  DateTime date, {
  required String entityType,
  required String entityId,
  required String status,
}) async {
  final dateKey = DateFormat('yyyy-MM-dd').format(date);
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

Future<void> _approveStaffLeave(
  LeaveService service, {
  required String staffId,
  required String staffName,
  required DateTime startDate,
  required DateTime endDate,
}) async {
  final id = await service.submitLeaveRequest(
    requesterId: staffId,
    requesterName: staffName,
    leaveType: LeaveType.sick,
    startDate: startDate,
    endDate: endDate,
    reason: 'Fever',
  );
  await service.approveLeaveRequest(id, reviewedBy: 'admin-1');
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

Future<void> _goToHistoryTab(WidgetTester tester) async {
  await tester.tap(find.text('History'));
  await tester.pumpAndSettle();
}

// Staff History cells are keyed `history-cell-staff_{staffId}_{yyyy-MM-dd}`
// — distinct from the Student History cells' `history-cell_{...}` keys, so
// the two sections' cells are never ambiguous with each other.
Finder _staffDayCell(String staffId, DateTime weekStart, int dayIndex) {
  final date = weekStart.add(Duration(days: dayIndex));
  final dateKey = DateFormat('yyyy-MM-dd').format(date);
  return find.byKey(ValueKey('history-cell-staff_${staffId}_$dateKey'));
}

Finder _studentDayCell(String studentId, DateTime weekStart, int dayIndex) {
  final date = weekStart.add(Duration(days: dayIndex));
  final dateKey = DateFormat('yyyy-MM-dd').format(date);
  return find.byKey(ValueKey('history-cell_${studentId}_$dateKey'));
}

void main() {
  group('AttendanceScreen History tab — Staff section (ATT-06 completion)', () {
    testWidgets('a Staff History section/table exists alongside the Students section', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(find.text('Students'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('K Tanvi'), findsOneWidget);
      expect(find.text('Malini'), findsOneWidget);
      expect(find.byType(DataTable), findsNWidgets(2));
    });

    testWidgets('a Present staff attendance record shows the existing Present indicator', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      await _seedAttendanceOn(firestore, weekStart, entityType: 'staff', entityId: 'staff-2', status: 'present');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
    });

    testWidgets('an Absent staff attendance record shows the existing Absent indicator', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      await _seedAttendanceOn(firestore, weekStart, entityType: 'staff', entityId: 'staff-2', status: 'absent');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.byIcon(Icons.cancel)),
        findsOneWidget,
      );
    });

    testWidgets('an approved staff leave with no attendance record shows On Leave, using the same blue indicator as Student History', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await _approveStaffLeave(leaveService, staffId: 'staff-2', staffName: 'Malini', startDate: weekStart, endDate: weekStart);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.text('On Leave')),
        findsOneWidget,
      );
    });

    testWidgets('a staff member with no attendance record and no leave shows "-"', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.text('-')),
        findsOneWidget,
      );
    });

    testWidgets('On Leave only appears on the covered dates, not before or after', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      // Monday-Wednesday.
      await _approveStaffLeave(
        leaveService,
        staffId: 'staff-2',
        staffName: 'Malini',
        startDate: weekStart,
        endDate: weekStart.add(const Duration(days: 2)),
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _staffDayCell('staff-2', weekStart, 1), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _staffDayCell('staff-2', weekStart, 2), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _staffDayCell('staff-2', weekStart, 3), matching: find.text('-')), findsOneWidget);
      expect(
        find.descendant(of: find.byType(DataTable).last, matching: find.text('On Leave')),
        findsNWidgets(3),
      );
    });

    testWidgets('navigating to the previous week reloads Staff History against the newly selected range', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final previousWeekMonday = weekStart.subtract(const Duration(days: 7));
      final leaveService = _leaveService(firestore);
      await _approveStaffLeave(
        leaveService,
        staffId: 'staff-2',
        staffName: 'Malini',
        startDate: previousWeekMonday,
        endDate: previousWeekMonday,
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      // Currently displayed (this) week has no staff leave covering it.
      expect(
        find.descendant(of: find.byType(DataTable).last, matching: find.text('On Leave')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _staffDayCell('staff-2', previousWeekMonday, 0), matching: find.text('On Leave')),
        findsOneWidget,
      );
    });

    testWidgets('navigating to the next week reloads Staff History (from a previous week back to the current one)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await _approveStaffLeave(leaveService, staffId: 'staff-2', staffName: 'Malini', startDate: weekStart, endDate: weekStart);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);
      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();

      // Previous week has no leave covering it.
      expect(
        find.descendant(of: find.byType(DataTable).last, matching: find.text('On Leave')),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Next week'));
      await tester.pumpAndSettle();

      // Back on the current week — the leave covering its Monday reappears.
      expect(
        find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.text('On Leave')),
        findsOneWidget,
      );
    });

    testWidgets('Student History continues to work correctly alongside the new Staff section', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      await _seedAttendanceOn(firestore, weekStart, entityType: 'student', entityId: 'student-1', status: 'present');
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _studentDayCell('student-1', weekStart, 0), matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
    });

    testWidgets('Student Leave never produces an On Leave indicator in the Staff History section (isolation)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      final id = await leaveService.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        leaveType: LeaveType.sick,
        startDate: weekStart,
        endDate: weekStart,
        reason: 'Fever',
      );
      await leaveService.approveLeaveRequest(id, reviewedBy: 'admin-1');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _studentDayCell('student-1', weekStart, 0), matching: find.text('On Leave')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.text('On Leave')),
        findsNothing,
      );
    });

    testWidgets('Staff Leave never produces an On Leave indicator in the Students History section (isolation)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      await _seedStaff(firestore, 'staff-2', 'Malini');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await _approveStaffLeave(leaveService, staffId: 'staff-2', staffName: 'Malini', startDate: weekStart, endDate: weekStart);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _staffDayCell('staff-2', weekStart, 0), matching: find.text('On Leave')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _studentDayCell('student-1', weekStart, 0), matching: find.text('On Leave')),
        findsNothing,
      );
    });
  });
}
