// ATT-06 completion: Staff Leave -> Attendance integration. Mirrors
// student_leave_attendance_integration_test.dart's coverage of
// getStudentIdsOnApprovedLeave(ForRange), but for the Staff-Leave siblings
// getStaffIdsOnApprovedLeave(ForRange) — LeaveService-level, no widgets.
//
// Staff Leave has no separate "staffId" field: a subjectType == 'staff'
// request's own requesterId IS the staff member the leave is for (see
// LeaveService.submitLeaveRequest), so these methods key off requesterId.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/leave/models/leave_request_model.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';

class _UnusedFilePicker extends FilePicker {}

LeaveService _service(FakeFirebaseFirestore firestore) => LeaveService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
    );

void main() {
  group('LeaveService.getStaffIdsOnApprovedLeave', () {
    test('includes a staff member whose approved leave range covers the exact queried date', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final onLeaveStart = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 10));
      final onLeaveMiddle = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 11));
      final onLeaveEnd = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 12));

      expect(onLeaveStart, contains('staff-1'));
      expect(onLeaveMiddle, contains('staff-1'));
      expect(onLeaveEnd, contains('staff-1'));
    });

    test('excludes the staff member on a date one day before or after the approved range', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 12),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final dayBefore = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 9));
      final dayAfter = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 13));

      expect(dayBefore, isNot(contains('staff-1')));
      expect(dayAfter, isNot(contains('staff-1')));
    });

    test('excludes a Pending (not yet approved) staff leave request', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 10),
        reason: 'Fever',
      );

      final onLeave = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 10));
      expect(onLeave, isEmpty);
    });

    test('excludes a Rejected staff leave request', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 10),
        reason: 'Fever',
      );
      await service.rejectLeaveRequest(id, reviewedBy: 'admin-1');

      final onLeave = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 10));
      expect(onLeave, isEmpty);
    });

    test('an approved Student (not staff) leave request never appears here', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 10),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      // Even though the submitting staff member ('staff-1') matches, this
      // is a Student Leave request (subjectType == 'student') — it must
      // never be misread as that staff member's own leave.
      final onLeave = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 9, 10));
      expect(onLeave, isEmpty);
    });

    test('an approved leave on one date does not affect a different, unrelated date', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 10),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final unrelatedDate = await service.getStaffIdsOnApprovedLeave(DateTime(2026, 10, 1));
      expect(unrelatedDate, isEmpty);
    });
  });

  group('LeaveService.getStaffIdsOnApprovedLeaveForRange', () {
    test('an approved leave on the exact historical date is included for that date', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 24),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStaffIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result['2026-08-24'], contains('staff-1'));
    });

    test('an approved leave spanning multiple historical dates shows on every covered date', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 26),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStaffIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result['2026-08-23'], isNull);
      expect(result['2026-08-24'], contains('staff-1'));
      expect(result['2026-08-25'], contains('staff-1'));
      expect(result['2026-08-26'], contains('staff-1'));
      expect(result['2026-08-27'], isNull);
    });

    test('a date before the approved range is not On Leave', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 25),
        endDate: DateTime(2026, 8, 26),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStaffIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result['2026-08-24'], isNull);
    });

    test('a date after the approved range is not On Leave', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 26),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStaffIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result['2026-08-27'], isNull);
    });

    test('a Pending staff leave request never appears in the range map', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 24),
        reason: 'Fever',
      );

      final result = await service.getStaffIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result, isEmpty);
    });

    test('a Rejected staff leave request never appears in the range map', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 24),
        reason: 'Fever',
      );
      await service.rejectLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStaffIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result, isEmpty);
    });

    test('an approved Student (not staff) leave request never appears in the range map', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 24),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStaffIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result, isEmpty);
    });
  });
}
