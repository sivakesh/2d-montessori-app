// Coverage for the Student Leave extension to LeaveService/LeaveRequestModel:
//  - Parent submission is authorized server-side against the parent's
//    actual linked children (ParentService.getLinkedStudents), not merely
//    hidden in a UI picker — an arbitrary/unrelated studentId is rejected
//    even though the caller supplies it directly to the service.
//  - Staff can submit for any student, and can only see the student-leave
//    requests they themselves submitted.
//  - Admin sees every student leave request, independent of Staff Leave.
//  - Approve/reject reuse the exact same lifecycle/guard as Staff Leave.
//  - Existing Staff Leave (subjectType == 'staff') stays fully isolated
//    from Student Leave requests sharing the same collection.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/notifications/data/admin_notification_service.dart';
import 'package:montessori_app/modules/leave/models/leave_request_model.dart';
import 'package:montessori_app/modules/leave/services/leave_service.dart';
import 'package:montessori_app/modules/parent/data/parent_service.dart';

class _UnusedFilePicker extends FilePicker {}

LeaveService _service(FakeFirebaseFirestore firestore) => LeaveService(
      firestore: firestore,
      notificationService: AdminNotificationService(
        firestore: firestore,
        storage: MockFirebaseStorage(),
        filePicker: _UnusedFilePicker(),
      ),
      parentService: ParentService(firestore: firestore),
    );

Future<void> _linkChild(
  FakeFirebaseFirestore firestore, {
  required String parentId,
  required String studentId,
  required String studentName,
  bool isActive = true,
}) async {
  await firestore.collection('students').doc(studentId).set({
    'name': studentName,
    'isActive': isActive,
  });
  await firestore.collection('user_student_links').add({
    'userId': parentId,
    'studentId': studentId,
  });
}

void main() {
  group('Parent Student Leave', () {
    test('11. Parent can submit leave for a linked child', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      final service = _service(firestore);

      final id = await service.submitStudentLeaveRequest(
        requesterId: 'parent-1',
        requesterName: 'Parent One',
        requesterRole: LeaveRequesterRole.parent,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 2),
        reason: 'Fever',
      );

      final requests = await service.getStudentRequestsForParent('parent-1');
      final created = requests.singleWhere((r) => r.id == id);
      expect(created.status, LeaveStatus.pending);
      expect(created.subjectType, LeaveSubjectType.student);
      expect(created.requesterRole, LeaveRequesterRole.parent);
      expect(created.studentId, 'student-1');
    });

    test('12. Parent with multiple children can submit for each linked child', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-2', studentName: 'Diya');
      final service = _service(firestore);

      await service.submitStudentLeaveRequest(
        requesterId: 'parent-1',
        requesterName: 'Parent One',
        requesterRole: LeaveRequesterRole.parent,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );
      await service.submitStudentLeaveRequest(
        requesterId: 'parent-1',
        requesterName: 'Parent One',
        requesterRole: LeaveRequesterRole.parent,
        studentId: 'student-2',
        studentName: 'Diya',
        leaveType: LeaveType.casual,
        startDate: DateTime(2026, 9, 3),
        endDate: DateTime(2026, 9, 3),
        reason: 'Family function',
      );

      final requests = await service.getStudentRequestsForParent('parent-1');
      expect(requests.map((r) => r.studentId).toSet(), {'student-1', 'student-2'});
    });

    test('13. Parent cannot submit leave for a student not linked to their account', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      // student-2 exists but is linked to a different parent.
      await _linkChild(firestore, parentId: 'parent-2', studentId: 'student-2', studentName: 'Kabir');
      final service = _service(firestore);

      expect(
        () => service.submitStudentLeaveRequest(
          requesterId: 'parent-1',
          requesterName: 'Parent One',
          requesterRole: LeaveRequesterRole.parent,
          studentId: 'student-2',
          studentName: 'Kabir',
          leaveType: LeaveType.sick,
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 1),
          reason: 'Attempted cross-account request',
        ),
        throwsA(isA<UnauthorizedStudentLeaveException>()),
      );

      // Nothing was written.
      final snap = await firestore.collection('staff_leave_requests').get();
      expect(snap.docs, isEmpty);
    });

    test('13b. Parent cannot submit leave for a completely arbitrary/unrelated student id', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      final service = _service(firestore);

      expect(
        () => service.submitStudentLeaveRequest(
          requesterId: 'parent-1',
          requesterName: 'Parent One',
          requesterRole: LeaveRequesterRole.parent,
          studentId: 'does-not-exist',
          studentName: 'Nobody',
          leaveType: LeaveType.sick,
          startDate: DateTime(2026, 9, 1),
          endDate: DateTime(2026, 9, 1),
          reason: 'Arbitrary id',
        ),
        throwsA(isA<UnauthorizedStudentLeaveException>()),
      );
    });

    test('14. Parent sees only their own children\'s leave requests, not another parent\'s child', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      await _linkChild(firestore, parentId: 'parent-2', studentId: 'student-2', studentName: 'Kabir');
      final service = _service(firestore);

      await service.submitStudentLeaveRequest(
        requesterId: 'parent-1',
        requesterName: 'Parent One',
        requesterRole: LeaveRequesterRole.parent,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Fever',
      );
      await service.submitStudentLeaveRequest(
        requesterId: 'parent-2',
        requesterName: 'Parent Two',
        requesterRole: LeaveRequesterRole.parent,
        studentId: 'student-2',
        studentName: 'Kabir',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Fever',
      );

      final parentOneRequests = await service.getStudentRequestsForParent('parent-1');
      expect(parentOneRequests, hasLength(1));
      expect(parentOneRequests.single.studentId, 'student-1');
    });

    test('15. Leave validation: end date before start date is rejected', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      final service = _service(firestore);

      expect(
        () => service.submitStudentLeaveRequest(
          requesterId: 'parent-1',
          requesterName: 'Parent One',
          requesterRole: LeaveRequesterRole.parent,
          studentId: 'student-1',
          studentName: 'Aarav',
          leaveType: LeaveType.sick,
          startDate: DateTime(2026, 9, 10),
          endDate: DateTime(2026, 9, 5),
          reason: 'Invalid range',
        ),
        throwsArgumentError,
      );
    });

    test('A parent with zero linked children has an empty leave history, no error', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final requests = await service.getStudentRequestsForParent('parent-with-no-children');
      expect(requests, isEmpty);
    });
  });

  group('Staff Student Leave', () {
    test('18. Staff can submit a student leave request for any active student', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('students').doc('student-9').set({'name': 'Meera', 'isActive': true});
      final service = _service(firestore);

      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-9',
        studentName: 'Meera',
        leaveType: LeaveType.other,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Field trip conflict',
      );

      final submitted = await service.getStudentRequestsSubmittedBy('staff-1');
      final created = submitted.singleWhere((r) => r.id == id);
      expect(created.subjectType, LeaveSubjectType.student);
      expect(created.requesterRole, LeaveRequesterRole.staff);
      expect(created.studentName, 'Meera');
    });

    test('19. Staff sees only the student leave requests they themselves submitted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Illness reported to school',
      );
      await service.submitStudentLeaveRequest(
        requesterId: 'staff-2',
        requesterName: 'Teacher Raj',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-2',
        studentName: 'Kabir',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Illness reported to school',
      );

      final staffOneRequests = await service.getStudentRequestsSubmittedBy('staff-1');
      expect(staffOneRequests, hasLength(1));
      expect(staffOneRequests.single.studentId, 'student-1');
    });

    test('20. A staff member\'s "My Leave" (staff-subject) list never includes student-subject requests they submitted', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Personal illness',
      );
      await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Student illness',
      );

      final myOwnLeave = await service.getRequestsForStaff('staff-1');
      expect(myOwnLeave, hasLength(1));
      expect(myOwnLeave.single.subjectType, LeaveSubjectType.staff);

      final myStudentLeave = await service.getStudentRequestsSubmittedBy('staff-1');
      expect(myStudentLeave, hasLength(1));
      expect(myStudentLeave.single.subjectType, LeaveSubjectType.student);
    });
  });

  group('Admin Student Leave', () {
    test('21. Admin sees every student leave request, independent of Staff Leave', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      await service.submitLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 1),
        reason: 'Personal illness',
      );
      await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Student illness',
      );

      final allStaff = await service.getAllRequests();
      final allStudent = await service.getAllStudentLeaveRequests();
      expect(allStaff, hasLength(1));
      expect(allStaff.every((r) => r.subjectType == LeaveSubjectType.staff), isTrue);
      expect(allStudent, hasLength(1));
      expect(allStudent.every((r) => r.subjectType == LeaveSubjectType.student), isTrue);
    });

    test('22. Admin can approve a pending student leave request', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Student illness',
      );

      await service.approveLeaveRequest(id, reviewedBy: 'admin-1', remarks: 'Noted');

      final all = await service.getAllStudentLeaveRequests();
      final approved = all.singleWhere((r) => r.id == id);
      expect(approved.status, LeaveStatus.approved);
    });

    test('23. Admin can reject a pending student leave request', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'parent-1',
        requesterName: 'Parent One',
        requesterRole: LeaveRequesterRole.parent,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.casual,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 3),
        reason: 'Family trip',
      );

      await service.rejectLeaveRequest(id, reviewedBy: 'admin-1', remarks: 'Too close to exams');

      final all = await service.getAllStudentLeaveRequests();
      final rejected = all.singleWhere((r) => r.id == id);
      expect(rejected.status, LeaveStatus.rejected);
      expect(rejected.reviewRemarks, 'Too close to exams');
    });

    test('24. An already-decided student leave request cannot be reviewed again', () async {
      final firestore = FakeFirebaseFirestore();
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Teacher Priya',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Student illness',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1');

      expect(
        () => service.rejectLeaveRequest(id, reviewedBy: 'admin-1'),
        throwsA(isA<InvalidLeaveStatusTransitionException>()),
      );
    });

    test('25. Review remarks persist for a student leave request', () async {
      final firestore = FakeFirebaseFirestore();
      await _linkChild(firestore, parentId: 'parent-1', studentId: 'student-1', studentName: 'Aarav');
      final service = _service(firestore);
      final id = await service.submitStudentLeaveRequest(
        requesterId: 'parent-1',
        requesterName: 'Parent One',
        requesterRole: LeaveRequesterRole.parent,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Fever',
      );
      await service.approveLeaveRequest(id, reviewedBy: 'admin-1', remarks: 'Get well soon');

      final refetched = await service.getAllStudentLeaveRequests();
      expect(refetched.singleWhere((r) => r.id == id).reviewRemarks, 'Get well soon');
    });
  });

  group('Regression — existing Staff Leave', () {
    test('26. Existing Staff Leave submission still works exactly as before', () async {
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
      final own = await service.getRequestsForStaff('staff-1');
      expect(own.singleWhere((r) => r.id == id).status, LeaveStatus.pending);
    });

    test('27. Existing Staff Leave isolation still works with student leave in the same collection', () async {
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
        startDate: DateTime(2026, 9, 5),
        endDate: DateTime(2026, 9, 6),
        reason: 'Family function',
      );
      await service.submitStudentLeaveRequest(
        requesterId: 'staff-1',
        requesterName: 'Asha',
        requesterRole: LeaveRequesterRole.staff,
        studentId: 'student-1',
        studentName: 'Aarav',
        leaveType: LeaveType.sick,
        startDate: DateTime(2026, 9, 2),
        endDate: DateTime(2026, 9, 2),
        reason: 'Student illness',
      );

      final staffOneRequests = await service.getRequestsForStaff('staff-1');
      expect(staffOneRequests, hasLength(1));
      expect(staffOneRequests.every((r) => r.requesterId == 'staff-1'), isTrue);
      expect(staffOneRequests.any((r) => r.requesterId == 'staff-2'), isFalse);
      expect(staffOneRequests.every((r) => r.subjectType == LeaveSubjectType.staff), isTrue);
    });
  });
}
