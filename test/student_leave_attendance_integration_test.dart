// Coverage for the Student Leave -> Attendance integration:
//  - LeaveService.getStudentIdsOnApprovedLeave returns exactly the students
//    whose Approved leave range covers the queried date — not a day
//    before/after the range, not a Pending/Rejected request, and not a
//    Staff-subject request.
//  - The 5-working-day cap on student leave requests (shared with Staff
//    Leave via countWorkingDays), enforced in
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

  // ATT-02: Attendance History's range-based sibling of
  // getStudentIdsOnApprovedLeave — resolves an entire displayed week from
  // one getAllStudentLeaveRequests query instead of one call per date.
  group('LeaveService.getStudentIdsOnApprovedLeaveForRange', () {
    test('an approved leave on the exact historical date is included for that date', () async {
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

      final result = await service.getStudentIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result['2026-08-24'], contains('student-1'));
    });

    test('an approved leave spanning multiple historical dates shows on every covered date', () async {
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
        endDate: DateTime(2026, 8, 26),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStudentIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result['2026-08-23'], isNull);
      expect(result['2026-08-24'], contains('student-1'));
      expect(result['2026-08-25'], contains('student-1'));
      expect(result['2026-08-26'], contains('student-1'));
      expect(result['2026-08-27'], isNull);
    });

    test('a leave starting before the displayed week and ending inside it only marks the covered dates', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 8, 22),
        endDate: DateTime(2026, 8, 25),
        reason: 'Family event',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      // Displayed week starts on the 24th — the leave began two days
      // earlier, outside the window.
      final result = await service.getStudentIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result['2026-08-24'], contains('student-1'));
      expect(result['2026-08-25'], contains('student-1'));
      expect(result['2026-08-26'], isNull);
    });

    test('a leave that ends before the displayed week produces no On Leave dates in that window', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 8, 10),
        endDate: DateTime(2026, 8, 12),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStudentIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result, isEmpty);
    });

    test('a Pending student leave request never appears in the range map', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitStudentLeaveRequest(
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

      final result = await service.getStudentIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result, isEmpty);
    });

    test('a Rejected student leave request never appears in the range map', () async {
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
      await service.rejectLeaveRequest(id, reviewedBy: 'admin-1');

      final result = await service.getStudentIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result, isEmpty);
    });

    test('an approved Staff (not student) leave request never appears in the range map', () async {
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

      final result = await service.getStudentIdsOnApprovedLeaveForRange(
        startDate: DateTime(2026, 8, 24),
        endDate: DateTime(2026, 8, 30),
      );

      expect(result, isEmpty);
    });
  });

  // Student Leave now shares the exact same 5-working-day policy (and the
  // same countWorkingDays calculation) as Staff Leave — it no longer counts
  // calendar days, so Saturday/Sunday never count toward the limit.
  group('LeaveService.submitStudentLeaveRequest — 5-working-day cap', () {
    test('Mon-Fri (5 working days) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 11),
        reason: 'Family travel',
      );
      expect(id, isNotEmpty);
    });

    test('Mon-Sat (5 working days, weekend spillover) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 12),
        reason: 'Family travel running into Saturday',
      );
      expect(id, isNotEmpty);
    });

    test('Mon-Sun (5 working days, full weekend spillover) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 13),
        reason: 'Family travel running into the full weekend',
      );
      expect(id, isNotEmpty);
    });

    test('Fri-Tue (3 working days) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.casual,
        startDate: DateTime(2026, 9, 11),
        endDate: DateTime(2026, 9, 15),
        reason: 'Long weekend trip',
      );
      expect(id, isNotEmpty);
    });

    test('Mon to the following Mon (6 working days) is rejected', () async {
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
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2026, 9, 14),
          reason: 'Two work weeks',
        ),
        throwsArgumentError,
      );
    });

    test('a weekend-only range (0 working days) is rejected', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      expect(
        () => service.submitStudentLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Teacher Priya',
          requesterRole: LeaveRequesterRole.staff,
          studentId: 'student-1',
          studentName: 'Aarav',
          leaveType: LeaveType.casual,
          startDate: DateTime(2026, 9, 12),
          endDate: DateTime(2026, 9, 13),
          reason: 'Weekend only',
        ),
        throwsArgumentError,
      );
    });

    test('a range spanning multiple weekends but exceeding 5 working days is rejected', () async {
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
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2026, 9, 22),
          reason: 'Extended trip across three weeks',
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

    test('a rejected over-cap request writes nothing to Firestore', () async {
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
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2026, 9, 14),
          reason: 'Two work weeks',
        );
      } catch (_) {}

      final snap = await firestore.collection('staff_leave_requests').get();
      expect(snap.docs, isEmpty);
    });

    test(
        'a range that would have exceeded the old 5-calendar-day cap is now '
        'accepted under the shared 5-working-day policy', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      // Wed Sep 2 -> Tue Sep 8, 2026: 7 calendar days (over the old Student
      // Leave calendar-day cap) but only 5 working days (Wed-Fri, then
      // Mon-Tue, skipping the Sep 5-6 weekend) — accepted now that Student
      // Leave shares Staff Leave's working-day policy.
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 8),
        reason: 'Family travel spanning a weekend',
      );
      expect(id, isNotEmpty);
    });

    // Regression: an ordinary short Student Leave request (well within the
    // cap) still submits and can be taken through the full
    // Pending -> Approved lifecycle exactly as before this rule changed.
    test('regression: an ordinary short student leave request still submits and can be approved', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 8),
        endDate: DateTime(2026, 9, 9),
        reason: 'Fever',
      );

      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final all = await service.getAllStudentLeaveRequests();
      final approved = all.singleWhere((r) => r.id == id);
      expect(approved.status, LeaveStatus.approved);
    });
  });
}
