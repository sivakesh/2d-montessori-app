// Coverage for the Student Leave -> Attendance integration:
//  - LeaveService.getStudentIdsOnApprovedLeave returns exactly the students
//    whose Approved leave range covers the queried date — not a day
//    before/after the range, not a Pending/Rejected request, and not a
//    Staff-subject request.
//  - The 5-calendar-day cap on student leave requests, enforced in
//    LeaveService.submitStudentLeaveRequest (the UI's own dialog-level
//    validation is exercised in calendar_leave_responsive_test.dart /
//    parent_student_leave_test.dart via the actual submit flow).
//
// See attendance_summary_test.dart for resolveAttendanceDisplayStatus,
// the pure "how should this show on the row" decision that consumes this
// service's output.
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
  group('LeaveService.getStudentIdsOnApprovedLeave', () {
    test('includes a student whose approved leave range covers the exact queried date', () async {
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
        endDate: DateTime(2026, 9, 12),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final onLeaveStart = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 10));
      final onLeaveMiddle = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 11));
      final onLeaveEnd = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 12));

      expect(onLeaveStart, contains('student-1'));
      expect(onLeaveMiddle, contains('student-1'));
      expect(onLeaveEnd, contains('student-1'));
    });

    test('excludes the student on a date one day before or after the approved range', () async {
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
        endDate: DateTime(2026, 9, 12),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final dayBefore = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 9));
      final dayAfter = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 13));

      expect(dayBefore, isNot(contains('student-1')));
      expect(dayAfter, isNot(contains('student-1')));
    });

    test('excludes a Pending (not yet approved) student leave request', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitStudentLeaveRequest(
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

      final onLeave = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 10));
      expect(onLeave, isEmpty);
    });

    test('excludes a Rejected student leave request', () async {
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
      await service.rejectLeaveRequest(id, reviewedBy: 'admin-1');

      final onLeave = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 10));
      expect(onLeave, isEmpty);
    });

    test('an approved Staff (not student) leave request never appears here', () async {
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

      final onLeave = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 9, 10));
      expect(onLeave, isEmpty);
    });

    test('an approved leave on one date does not affect a different, unrelated date', () async {
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

      final unrelatedDate = await service.getStudentIdsOnApprovedLeave(DateTime(2026, 10, 1));
      expect(unrelatedDate, isEmpty);
    });
  });

  group('LeaveService.submitStudentLeaveRequest — 5-calendar-day cap', () {
    test('exactly 5 inclusive days is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 5),
        reason: 'Family travel',
      );
      expect(id, isNotEmpty);
    });

    test('6 inclusive days is rejected', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      expect(
        () => service.submitStudentLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Teacher Priya',
          requesterRole: LeaveRequesterRole.staff,
          studentId: 'student-1',
          studentName: 'Aarav',
          leaveType: LeaveType.earned,
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 6),
          reason: 'Family travel',
        ),
        throwsArgumentError,
      );
    });

    test('a single-day request (start == end) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );
      expect(id, isNotEmpty);
    });

    test('a rejected over-limit request writes nothing to Firestore', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      try {
        await service.submitStudentLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Teacher Priya',
          requesterRole: LeaveRequesterRole.staff,
          studentId: 'student-1',
          studentName: 'Aarav',
          leaveType: LeaveType.earned,
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 20),
          reason: 'Long trip',
        );
      } catch (_) {}

      final snap = await firestore.collection('staff_leave_requests').get();
      expect(snap.docs, isEmpty);
    });

    test('the 5-day cap does not apply to Staff Leave (only Student Leave)', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 20),
        reason: 'Long personal trip',
      );
      expect(id, isNotEmpty);
    });
  });
}
