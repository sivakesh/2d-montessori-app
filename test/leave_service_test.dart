// Coverage for the Staff Leave Requests MVP (LeaveService +
// LeaveRequestModel):
//  - Submission and per-staff data isolation: a staff member only ever sees
//    their own requests (query scoped by requesterId, not client-filtered).
//  - Admin visibility across all staff.
//  - Approve/reject lifecycle, including the invalid-transition guard
//    (a request that is already Approved/Rejected cannot be reviewed again).
//  - Invalid date range (end before start) is rejected at submission time.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/leave/models/leave_request_model.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';

// Same rationale as calendar_service_test.dart / admin_notification_archive_test.dart:
// avoids AdminNotificationService touching real Storage/FilePicker platform
// singletons during the approve/reject best-effort notification.
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
  group('LeaveService — submission & isolation', () {
    test('9. Staff can submit a leave request, saved as Pending', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 10),
        endDate: DateTime(2026, 9, 11),
        reason: 'Fever',
      );

      final own = await service.getRequestsForStaff('staff-1');
      final created = own.singleWhere((r) => r.id == id);
      expect(created.status, LeaveStatus.pending);
      expect(created.leaveType, LeaveType.sick);
      expect(created.reason, 'Fever');
    });

    test('10. Staff sees their own requests', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.casual,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Personal work',
      );

      final own = await service.getRequestsForStaff('staff-1');
      expect(own, hasLength(1));
      expect(own.single.requesterId, 'staff-1');
    });

    test('11. Staff cannot see another staff member\'s requests', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );
      await service.submitLeaveRequest(
        requesterId: 'staff-2',
        requesterName: 'Ravi',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 3),
        endDate: DateTime(2026, 9, 4),
        reason: 'Family function',
      );

      final staffOneRequests = await service.getRequestsForStaff('staff-1');
      expect(staffOneRequests, hasLength(1));
      expect(staffOneRequests.every((r) => r.requesterId == 'staff-1'), isTrue);
      expect(staffOneRequests.any((r) => r.requesterId == 'staff-2'), isFalse);
    });

    test('12. Admin can see every staff member\'s leave requests', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );
      await service.submitLeaveRequest(
        requesterId: 'staff-2',
        requesterName: 'Ravi',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 3),
        endDate: DateTime(2026, 9, 4),
        reason: 'Family function',
      );

      final all = await service.getAllRequests();
      expect(all.map((r) => r.requesterId).toSet(), {'staff-1', 'staff-2'});
    });
  });

  group('LeaveService — approve/reject lifecycle', () {
    test('13. Admin can approve a Pending request', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );

      await service.approveLeaveRequest(id, reviewedBy: 'admin-1', remarks: 'Approved, get well soon');

      final all = await service.getAllRequests();
      final approved = all.singleWhere((r) => r.id == id);
      expect(approved.status, LeaveStatus.approved);
      expect(approved.reviewedBy, 'admin-1');
      expect(approved.reviewRemarks, 'Approved, get well soon');
    });

    test('14. Admin can reject a Pending request', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.casual,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 2),
        reason: 'Trip',
      );

      await service.rejectLeaveRequest(id, reviewedBy: 'admin-1', remarks: 'Staffing shortage that week');

      final all = await service.getAllRequests();
      final rejected = all.singleWhere((r) => r.id == id);
      expect(rejected.status, LeaveStatus.rejected);
      expect(rejected.reviewRemarks, 'Staffing shortage that week');
    });

    test('15. Approved/rejected status persists across re-fetches', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final refetched = await service.getRequestsForStaff('staff-1');
      expect(refetched.singleWhere((r) => r.id == id).status, LeaveStatus.approved);
    });

    test('16. An already-Approved request cannot be approved or rejected again', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      expect(
        () => service.approveLeaveRequest(id, reviewedBy: 'admin-1'),
        throwsA(isA<InvalidLeaveStatusTransitionException>()),
      );
      expect(
        () => service.rejectLeaveRequest(id, reviewedBy: 'admin-1'),
        throwsA(isA<InvalidLeaveStatusTransitionException>()),
      );

      // Status is unaffected by the rejected attempt above.
      final all = await service.getAllRequests();
      expect(all.singleWhere((r) => r.id == id).status, LeaveStatus.approved);
    });

    test('16b. An already-Rejected request cannot be approved', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.casual,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Trip',
      );
      await service.rejectLeaveRequest(id, reviewedBy: 'admin-1');

      expect(
        () => service.approveLeaveRequest(id, reviewedBy: 'admin-1'),
        throwsA(isA<InvalidLeaveStatusTransitionException>()),
      );
    });
  });

  group('LeaveService — validation', () {
    test('18. Submitting with an end date before the start date is rejected', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);

      expect(
        () => service.submitLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Asha',
          leaveType: LeaveType.sick,
          startDate: DateTime(2026, 9, 10),
          endDate: DateTime(2026, 9, 5),
          reason: 'Invalid range',
        ),
        throwsArgumentError,
      );
    });
  });

  // countWorkingDays is the single source of truth Staff Leave's 5-day cap
  // is built on — it must count only Monday-Friday, never Saturday/Sunday,
  // regardless of how the range happens to be shaped.
  group('countWorkingDays', () {
    test('Mon-Fri is 5 working days', () {
      expect(
        countWorkingDays(DateTime(2026, 9, 7), DateTime(2026, 9, 11)),
        5,
      );
    });

    test('Mon-Sat is 5 working days (Saturday not counted)', () {
      expect(
        countWorkingDays(DateTime(2026, 9, 7), DateTime(2026, 9, 12)),
        5,
      );
    });

    test('Mon-Sun is 5 working days (Saturday and Sunday not counted)', () {
      expect(
        countWorkingDays(DateTime(2026, 9, 7), DateTime(2026, 9, 13)),
        5,
      );
    });

    test('Fri-Tue is 3 working days (weekend in the middle skipped)', () {
      expect(
        countWorkingDays(DateTime(2026, 9, 11), DateTime(2026, 9, 15)),
        3,
      );
    });

    test('Mon to the following Mon is 6 working days', () {
      expect(
        countWorkingDays(DateTime(2026, 9, 7), DateTime(2026, 9, 14)),
        6,
      );
    });

    test('a weekend-only range is 0 working days', () {
      expect(
        countWorkingDays(DateTime(2026, 9, 12), DateTime(2026, 9, 13)),
        0,
      );
    });

    test('a range spanning multiple weekends counts only the weekdays in it', () {
      // Mon Sep 7 -> Tue Sep 22: three partial/full weeks, two weekends
      // (Sep 12-13 and Sep 19-20) sitting inside the range.
      expect(
        countWorkingDays(DateTime(2026, 9, 7), DateTime(2026, 9, 22)),
        12,
      );
    });
  });

  group('LeaveService.submitLeaveRequest — 5-working-day cap', () {
    test('Mon-Fri (5 working days) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 11),
        reason: 'Full working week off',
      );
      expect(id, isNotEmpty);
    });

    test('Mon-Sat (5 working days, weekend spillover) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 12),
        reason: 'Week off running into Saturday',
      );
      expect(id, isNotEmpty);
    });

    test('Mon-Sun (5 working days, full weekend spillover) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.earned,
        startDate: DateTime(2026, 9, 7),
        endDate: DateTime(2026, 9, 13),
        reason: 'Week off running into the full weekend',
      );
      expect(id, isNotEmpty);
    });

    test('Fri-Tue (3 working days) is accepted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
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
        () => service.submitLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Asha',
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
        () => service.submitLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Asha',
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
        () => service.submitLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Asha',
          leaveType: LeaveType.earned,
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2026, 9, 22),
          reason: 'Extended trip across three weeks',
        ),
        throwsArgumentError,
      );
    });

    test('a rejected over-cap request writes nothing to Firestore', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      try {
        await service.submitLeaveRequest(
          requesterId: 'staff-1',
          requesterName: 'Asha',
          leaveType: LeaveType.earned,
          startDate: DateTime(2026, 9, 7),
          endDate: DateTime(2026, 9, 14),
          reason: 'Two work weeks',
        );
      } catch (_) {}

      final snap = await firestore.collection('staff_leave_requests').get();
      expect(snap.docs, isEmpty);
    });

    // Regression: short, everyday leave requests (well within the cap)
    // submit and can still be taken through the full Pending -> Approved
    // lifecycle exactly as before this rule was added.
    test('regression: an ordinary short leave request still submits and can be approved', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 8),
        endDate: DateTime(2026, 9, 9),
        reason: 'Fever',
      );

      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      final all = await service.getAllRequests();
      final approved = all.singleWhere((r) => r.id == id);
      expect(approved.status, LeaveStatus.approved);
    });
  });
}
