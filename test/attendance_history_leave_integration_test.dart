// ATT-02: Staff -> Attendance -> History was ignoring approved Student
// Leave entirely — a historical date with no attendance record always
// rendered "-", even for a student on an Approved leave covering that exact
// date. The Today tab already resolved this correctly (see
// attendance_screen_leave_integration_test.dart); this file covers the
// same resolution extended across the History tab's displayed week,
// pumping the REAL AttendanceScreen rather than re-testing the pure helper
// in isolation.
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

Future<String> _approveStudentLeave(
  LeaveService service, {
  required String studentId,
  required String studentName,
  required DateTime startDate,
  required DateTime endDate,
}) async {
  final id = await service.submitStudentLeaveRequest(
    requesterId: 'staff-1',
    requesterName: 'Teacher Priya',
    requesterRole: LeaveRequesterRole.staff,
    studentId: studentId,
    studentName: studentName,
    leaveType: LeaveType.sick,
    startDate: startDate,
    endDate: endDate,
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

Future<void> _goToHistoryTab(WidgetTester tester) async {
  await tester.tap(find.text('History'));
  await tester.pumpAndSettle();
}

// Locates one History date cell by the ValueKey attendance_screen.dart
// stamps on it (`history-cell_{studentId}_{yyyy-MM-dd}`) — DataCell isn't a
// Widget subtype so it can't be found via find.byType, and DataTable gives
// no other structural way to address a single cell by column. [dayIndex] 0
// == Monday of [weekStart] (always a Monday — the displayed
// _selectedHistoryWeekStart), matching weekDays in _buildHistoryTab.
Finder _dayCell(String studentId, DateTime weekStart, int dayIndex) {
  final date = weekStart.add(Duration(days: dayIndex));
  final dateKey = DateFormat('yyyy-MM-dd').format(date);
  return find.byKey(ValueKey('history-cell_${studentId}_$dateKey'));
}

Finder _onLeavePillsInTable() =>
    find.descendant(of: find.byType(DataTable), matching: find.text('On Leave'));

void main() {
  group('AttendanceScreen History tab — Student Leave integration (ATT-02)', () {
    testWidgets('an approved leave on the exact historical date (no attendance record) shows On Leave', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        startDate: weekStart,
        endDate: weekStart,
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(
        find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.text('On Leave')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _dayCell('student-1', weekStart, 1), matching: find.text('-')),
        findsOneWidget,
      );
      expect(_onLeavePillsInTable(), findsOneWidget);
    });

    testWidgets('an approved leave spanning multiple historical dates shows On Leave on every covered date only', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'Tannil Adonis');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'Tannil Adonis',
        startDate: weekStart,
        endDate: weekStart.add(const Duration(days: 2)),
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 1), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 2), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 3), matching: find.text('-')), findsOneWidget);
      expect(_onLeavePillsInTable(), findsNWidgets(3));
    });

    testWidgets('a leave starting before the displayed week and ending inside it only marks the covered dates', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        startDate: weekStart.subtract(const Duration(days: 2)),
        endDate: weekStart.add(const Duration(days: 1)),
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 1), matching: find.text('On Leave')), findsOneWidget);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 2), matching: find.text('-')), findsOneWidget);
      expect(_onLeavePillsInTable(), findsNWidgets(2));
    });

    testWidgets('a leave that ends before the displayed week produces no On Leave indicators', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        startDate: weekStart.subtract(const Duration(days: 10)),
        endDate: weekStart.subtract(const Duration(days: 8)),
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(_onLeavePillsInTable(), findsNothing);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.text('-')), findsOneWidget);
    });

    testWidgets('a Pending student leave request stays "-" in History', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      await leaveService.submitStudentLeaveRequest(
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

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(_onLeavePillsInTable(), findsNothing);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.text('-')), findsOneWidget);
    });

    testWidgets('a Rejected student leave request stays "-" in History', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
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
      await leaveService.rejectLeaveRequest(id, reviewedBy: 'admin-1');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(_onLeavePillsInTable(), findsNothing);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.text('-')), findsOneWidget);
    });

    testWidgets('a Present attendance record is not overwritten by an approved leave on the same date', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      await _seedAttendanceOn(
        firestore,
        weekStart,
        entityType: 'student',
        entityId: 'student-1',
        status: 'present',
      );
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        startDate: weekStart,
        endDate: weekStart,
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.byIcon(Icons.check_circle)), findsOneWidget);
      expect(_onLeavePillsInTable(), findsNothing);
    });

    testWidgets('an Absent attendance record is not overwritten by an approved leave on the same date', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      await _seedAttendanceOn(
        firestore,
        weekStart,
        entityType: 'student',
        entityId: 'student-1',
        status: 'absent',
      );
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        startDate: weekStart,
        endDate: weekStart,
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.byIcon(Icons.cancel)), findsOneWidget);
      expect(_onLeavePillsInTable(), findsNothing);
    });

    testWidgets('an approved Staff (not student) leave never produces an On Leave indicator in Student Attendance History', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final leaveService = _leaveService(firestore);
      final id = await leaveService.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: weekStart,
        endDate: weekStart,
        reason: 'Fever',
      );
      await leaveService.approveLeaveRequest(id, reviewedBy: 'admin-1');

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(_onLeavePillsInTable(), findsNothing);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.text('-')), findsOneWidget);
    });

    testWidgets('existing Present/Absent History indicators keep working exactly as before when there is no leave at all', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      await _seedAttendanceOn(
        firestore,
        weekStart,
        entityType: 'student',
        entityId: 'student-1',
        status: 'present',
      );
      await _seedAttendanceOn(
        firestore,
        weekStart.add(const Duration(days: 1)),
        entityType: 'student',
        entityId: 'student-1',
        status: 'absent',
      );
      final leaveService = _leaveService(firestore);

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      expect(find.descendant(of: _dayCell('student-1', weekStart, 0), matching: find.byIcon(Icons.check_circle)), findsOneWidget);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 1), matching: find.byIcon(Icons.cancel)), findsOneWidget);
      expect(find.descendant(of: _dayCell('student-1', weekStart, 2), matching: find.text('-')), findsOneWidget);
      expect(_onLeavePillsInTable(), findsNothing);
    });

    testWidgets('navigating to the previous History week re-resolves leave against the newly selected range', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final weekStart = _startOfWeek(DateTime.now().toLocal());
      final previousWeekMonday = weekStart.subtract(const Duration(days: 7));
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        startDate: previousWeekMonday,
        endDate: previousWeekMonday,
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      await _goToHistoryTab(tester);

      // Currently displayed week (this week) has no leave covering it.
      expect(_onLeavePillsInTable(), findsNothing);

      await tester.tap(find.byTooltip('Previous week'));
      await tester.pumpAndSettle();

      // Now showing last week — the leave on its Monday must appear.
      expect(_onLeavePillsInTable(), findsOneWidget);
      expect(
        find.descendant(
          of: _dayCell('student-1', previousWeekMonday, 0),
          matching: find.text('On Leave'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('regression: Today tab On Leave behavior remains intact alongside the History fix', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _seedStudent(firestore, 'student-1', 'K Tanvi');
      final today = DateTime.now().toLocal();
      final leaveService = _leaveService(firestore);
      await _approveStudentLeave(
        leaveService,
        studentId: 'student-1',
        studentName: 'K Tanvi',
        startDate: today,
        endDate: today,
      );

      await _pumpAttendanceScreen(tester, firestore: firestore, leaveService: leaveService);
      // Default tab is "Today" — no need to switch.
      final todayCard = find.ancestor(of: find.text('K Tanvi'), matching: find.byType(Card)).first;
      expect(find.descendant(of: todayCard, matching: find.text('On Leave')), findsOneWidget);
    });
  });
}
