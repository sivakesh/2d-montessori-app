import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../admin/notifications/data/admin_notification_service.dart';
import '../../parent/data/parent_service.dart';
import '../models/leave_request_model.dart';

/// Thrown when an approve/reject is attempted on a request that is not
/// currently Pending — e.g. approving an already-Approved or already-
/// Rejected request. Kept as a dedicated type (rather than a bare
/// Exception/StateError) so calling UI code can show a specific message
/// without string-matching.
class InvalidLeaveStatusTransitionException implements Exception {
  InvalidLeaveStatusTransitionException(this.currentStatus);
  final String currentStatus;

  @override
  String toString() =>
      'Cannot change a leave request that is already $currentStatus.';
}

/// Thrown when a parent tries to submit a student leave request for a
/// student not actually linked to their account — the authorization check
/// itself lives in [LeaveService.submitStudentLeaveRequest], not in the UI,
/// so this can never be bypassed by a client sending an arbitrary studentId.
class UnauthorizedStudentLeaveException implements Exception {
  UnauthorizedStudentLeaveException(this.studentId);
  final String studentId;

  @override
  String toString() =>
      'You are not authorized to request leave for this student.';
}

/// Staff Leave and Student Leave share this one collection
/// (`staff_leave_requests` — kept as-is rather than renamed, since renaming
/// would orphan any already-written production documents) rather than two
/// separate collections. [LeaveRequestModel.subjectType] ('staff' | matched
/// against [LeaveSubjectType.staff]/[LeaveSubjectType.student]) is the
/// explicit discriminator every query below filters on, so a Staff Leave
/// screen can never accidentally show a Student Leave request or vice
/// versa. Approve/reject are subject-agnostic (`_reviewRequest` branches
/// only for the notification's wording/audience), since the Pending ->
/// Approved/Rejected lifecycle and its invalid-transition guard are
/// identical for both subjects.
class LeaveService {
  LeaveService({
    FirebaseFirestore? firestore,
    AdminNotificationService? notificationService,
    ParentService? parentService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _injectedNotificationService = notificationService,
        _injectedParentService = parentService;

  final FirebaseFirestore _firestore;
  final AdminNotificationService? _injectedNotificationService;
  final ParentService? _injectedParentService;

  AdminNotificationService get _notificationService =>
      _injectedNotificationService ?? AdminNotificationService();

  ParentService get _parentService =>
      _injectedParentService ?? ParentService(firestore: _firestore);

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection('staff_leave_requests');

  // ---------------------------------------------------------------------
  // Staff Leave (unchanged public signatures — existing callers/tests keep
  // working exactly as before).
  // ---------------------------------------------------------------------

  Future<String> submitLeaveRequest({
    required String requesterId,
    required String requesterName,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('End date cannot be before start date.');
    }
    final workingDays = countWorkingDays(startDate, endDate);
    if (workingDays == 0) {
      throw ArgumentError(
        'Staff leave must include at least one working day (Monday-Friday).',
      );
    }
    if (workingDays > StaffLeavePolicy.maxWorkingDays) {
      throw ArgumentError(
        'Staff leave cannot exceed ${StaffLeavePolicy.maxWorkingDays} working days.',
      );
    }
    final doc = _requests.doc();
    await doc.set({
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requesterRole': LeaveRequesterRole.staff,
      'subjectType': LeaveSubjectType.staff,
      'studentId': null,
      'studentName': null,
      'leaveType': leaveType,
      'startDate': startDate,
      'endDate': endDate,
      'reason': reason,
      'status': LeaveStatus.pending,
      'reviewedBy': null,
      'reviewedAt': null,
      'reviewRemarks': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Only this staff member's own leave — the query itself is scoped by
  /// `requesterId`, not fetched-then-filtered, so one staff member's
  /// requests are never even transferred to another staff member's client.
  /// Filtered to `subjectType == 'staff'` so a student leave request this
  /// same staff member submitted for a student never appears in "My
  /// Leave".
  Future<List<LeaveRequestModel>> getRequestsForStaff(
    String requesterId,
  ) async {
    final snap =
        await _requests.where('requesterId', isEqualTo: requesterId).get();
    final items = snap.docs
        .map((d) => LeaveRequestModel.fromMap(d.id, d.data()))
        .where((r) => r.subjectType == LeaveSubjectType.staff)
        .toList();
    _sortByCreatedAtDesc(items);
    return items;
  }

  /// Every staff member's own leave — Admin's Staff Leave management view.
  Future<List<LeaveRequestModel>> getAllRequests() async {
    final snap = await _requests.get();
    final items = snap.docs
        .map((d) => LeaveRequestModel.fromMap(d.id, d.data()))
        .where((r) => r.subjectType == LeaveSubjectType.staff)
        .toList();
    _sortByCreatedAtDesc(items);
    return items;
  }

  /// Staff ids with an Approved leave request whose `[startDate, endDate]`
  /// range includes [date] (inclusive on both ends) — the Staff Leave
  /// sibling of [getStudentIdsOnApprovedLeave], used by Attendance to show
  /// "On Leave" instead of Not Marked/Absent for exactly that date. Staff
  /// Leave has no separate "staffId" field — the requester of a
  /// `subjectType == 'staff'` request IS the staff member the leave is for
  /// (see [submitLeaveRequest]) — so [LeaveRequestModel.requesterId] is
  /// what identifies them here. Reuses [getAllRequests] (already scoped to
  /// `subjectType == 'staff'`) rather than a second query shape.
  Future<Set<String>> getStaffIdsOnApprovedLeave(DateTime date) async {
    final all = await getAllRequests();
    final day = DateTime(date.year, date.month, date.day);
    bool coversDay(LeaveRequestModel r) {
      final start = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
      final end = DateTime(r.endDate.year, r.endDate.month, r.endDate.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }

    return all
        .where((r) => r.status == LeaveStatus.approved && coversDay(r))
        .map((r) => r.requesterId)
        .toSet();
  }

  /// Range-based sibling of [getStaffIdsOnApprovedLeave] — used by
  /// Attendance History so a full displayed week can be resolved from the
  /// same single [getAllRequests] query instead of one call per displayed
  /// date. Returns, for every date in `[startDate, endDate]` (inclusive on
  /// both ends) that has at least one Approved staff leave covering it, the
  /// set of staff ids on leave that date — keyed by `yyyy-MM-dd`. A date
  /// with no approved staff leave is simply absent from the map rather than
  /// mapping to an empty set. Mirrors
  /// [getStudentIdsOnApprovedLeaveForRange] exactly, substituting
  /// requesterId for studentId.
  Future<Map<String, Set<String>>> getStaffIdsOnApprovedLeaveForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final all = await getAllRequests();
    final rangeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final rangeEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final dateFormat = DateFormat('yyyy-MM-dd');

    final result = <String, Set<String>>{};
    for (final r in all) {
      if (r.status != LeaveStatus.approved) continue;
      final leaveStart = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
      final leaveEnd = DateTime(r.endDate.year, r.endDate.month, r.endDate.day);
      var cursor = leaveStart.isAfter(rangeStart) ? leaveStart : rangeStart;
      final last = leaveEnd.isBefore(rangeEnd) ? leaveEnd : rangeEnd;
      while (!cursor.isAfter(last)) {
        (result[dateFormat.format(cursor)] ??= <String>{}).add(r.requesterId);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Student Leave.
  // ---------------------------------------------------------------------

  /// Submits a leave request for a student. [requesterRole] identifies who
  /// is submitting it:
  ///  - 'parent': [requesterId] must be an AppUser id whose linked children
  ///    (via [ParentService.getLinkedStudents]) actually include
  ///    [studentId] — checked here, server-side, before any write happens.
  ///    A client cannot bypass this by hiding/showing different students in
  ///    its own UI, since an arbitrary studentId is rejected regardless of
  ///    what the UI would have allowed.
  ///  - 'staff': any active student may be selected — staff already have
  ///    broad student access elsewhere (e.g. marking attendance for any
  ///    student), so no additional per-student check is applied.
  Future<String> submitStudentLeaveRequest({
    required String requesterId,
    required String requesterName,
    required String requesterRole,
    required String studentId,
    required String studentName,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    if (endDate.isBefore(startDate)) {
      throw ArgumentError('End date cannot be before start date.');
    }
    final workingDays = countWorkingDays(startDate, endDate);
    if (workingDays == 0) {
      throw ArgumentError(
        'Student leave must include at least one working day (Monday-Friday).',
      );
    }
    if (workingDays > StudentLeavePolicy.maxWorkingDays) {
      throw ArgumentError(
        'Student leave cannot exceed ${StudentLeavePolicy.maxWorkingDays} working days.',
      );
    }
    if (requesterRole == LeaveRequesterRole.parent) {
      final linked = await _parentService.getLinkedStudents(requesterId);
      final allowed = linked.any((s) => s.id == studentId);
      if (!allowed) {
        throw UnauthorizedStudentLeaveException(studentId);
      }
    }

    final doc = _requests.doc();
    await doc.set({
      'requesterId': requesterId,
      'requesterName': requesterName,
      'requesterRole': requesterRole,
      'subjectType': LeaveSubjectType.student,
      'studentId': studentId,
      'studentName': studentName,
      'leaveType': leaveType,
      'startDate': startDate,
      'endDate': endDate,
      'reason': reason,
      'status': LeaveStatus.pending,
      'reviewedBy': null,
      'reviewedAt': null,
      'reviewRemarks': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// A parent's own linked children's leave history — regardless of who
  /// submitted each request (a parent may want to see one a staff member
  /// filed on the child's behalf too). [parentUserId]'s linked-children set
  /// is resolved server-side via [ParentService], never trusted from the
  /// caller, so this can only ever return requests for students actually
  /// linked to this parent.
  Future<List<LeaveRequestModel>> getStudentRequestsForParent(
    String parentUserId,
  ) async {
    final linked = await _parentService.getLinkedStudents(parentUserId);
    if (linked.isEmpty) return [];
    final linkedIds = linked.map((s) => s.id).toSet();

    final snap = await _requests.get();
    final items = snap.docs
        .map((d) => LeaveRequestModel.fromMap(d.id, d.data()))
        .where((r) =>
            r.subjectType == LeaveSubjectType.student &&
            linkedIds.contains(r.studentId))
        .toList();
    _sortByCreatedAtDesc(items);
    return items;
  }

  /// Student leave requests a specific staff/parent user submitted — used
  /// by Staff's "Student Leave" tab to show only what they themselves
  /// filed, the same isolation shape as [getRequestsForStaff].
  Future<List<LeaveRequestModel>> getStudentRequestsSubmittedBy(
    String requesterId,
  ) async {
    final snap =
        await _requests.where('requesterId', isEqualTo: requesterId).get();
    final items = snap.docs
        .map((d) => LeaveRequestModel.fromMap(d.id, d.data()))
        .where((r) => r.subjectType == LeaveSubjectType.student)
        .toList();
    _sortByCreatedAtDesc(items);
    return items;
  }

  /// Every student leave request — Admin's Student Leave management view.
  Future<List<LeaveRequestModel>> getAllStudentLeaveRequests() async {
    final snap = await _requests.get();
    final items = snap.docs
        .map((d) => LeaveRequestModel.fromMap(d.id, d.data()))
        .where((r) => r.subjectType == LeaveSubjectType.student)
        .toList();
    _sortByCreatedAtDesc(items);
    return items;
  }

  /// Student ids with an Approved leave request whose [startDate, endDate]
  /// range includes [date] (inclusive on both ends) — used by Attendance to
  /// show "On Leave" instead of Not Marked/Absent for exactly that date,
  /// and only that date; a student's leave on any other day has no effect
  /// here. Reuses [getAllStudentLeaveRequests] rather than a second query
  /// shape, filtering client-side the same way that method's own callers
  /// already do for status.
  Future<Set<String>> getStudentIdsOnApprovedLeave(DateTime date) async {
    final all = await getAllStudentLeaveRequests();
    final day = DateTime(date.year, date.month, date.day);
    bool coversDay(LeaveRequestModel r) {
      final start = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
      final end = DateTime(r.endDate.year, r.endDate.month, r.endDate.day);
      return !day.isBefore(start) && !day.isAfter(end);
    }

    return all
        .where((r) => r.status == LeaveStatus.approved && coversDay(r))
        .map((r) => r.studentId)
        .whereType<String>()
        .toSet();
  }

  /// Range-based sibling of [getStudentIdsOnApprovedLeave] — used by
  /// Attendance History so a full displayed week can be resolved from the
  /// same single [getAllStudentLeaveRequests] query instead of one call per
  /// displayed date. Returns, for every date in `[startDate, endDate]`
  /// (inclusive on both ends) that has at least one Approved student leave
  /// covering it, the set of student ids on leave that date — keyed by
  /// `yyyy-MM-dd`. A date with no approved student leave is simply absent
  /// from the map rather than mapping to an empty set.
  Future<Map<String, Set<String>>> getStudentIdsOnApprovedLeaveForRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final all = await getAllStudentLeaveRequests();
    final rangeStart = DateTime(startDate.year, startDate.month, startDate.day);
    final rangeEnd = DateTime(endDate.year, endDate.month, endDate.day);
    final dateFormat = DateFormat('yyyy-MM-dd');

    final result = <String, Set<String>>{};
    for (final r in all) {
      if (r.status != LeaveStatus.approved) continue;
      final studentId = r.studentId;
      if (studentId == null) continue;
      final leaveStart = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
      final leaveEnd = DateTime(r.endDate.year, r.endDate.month, r.endDate.day);
      // Clip the leave's own range to the displayed range before iterating,
      // so a leave spanning far outside the displayed week never loops over
      // dates that will never be shown.
      var cursor = leaveStart.isAfter(rangeStart) ? leaveStart : rangeStart;
      final last = leaveEnd.isBefore(rangeEnd) ? leaveEnd : rangeEnd;
      while (!cursor.isAfter(last)) {
        (result[dateFormat.format(cursor)] ??= <String>{}).add(studentId);
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Shared: approve/reject (subject-agnostic lifecycle).
  // ---------------------------------------------------------------------

  void _sortByCreatedAtDesc(List<LeaveRequestModel> items) {
    items.sort((a, b) {
      final aDate = a.createdAt ?? DateTime(2000);
      final bDate = b.createdAt ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });
  }

  Future<LeaveRequestModel?> _getById(String id) async {
    final doc = await _requests.doc(id).get();
    final data = doc.data();
    if (data == null) return null;
    return LeaveRequestModel.fromMap(doc.id, data);
  }

  Future<void> _reviewRequest(
    String id, {
    required String newStatus,
    required String reviewedBy,
    String? remarks,
  }) async {
    final current = await _getById(id);
    if (current == null) {
      throw StateError('Leave request not found.');
    }
    if (current.status != LeaveStatus.pending) {
      throw InvalidLeaveStatusTransitionException(current.status);
    }
    await _requests.doc(id).update({
      'status': newStatus,
      'reviewedBy': reviewedBy,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewRemarks': remarks,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Best-effort notification via the existing notification
    // infrastructure — never lets a notification failure undo or mask the
    // approve/reject that already succeeded.
    try {
      final approved = newStatus == LeaveStatus.approved;
      final Map<String, dynamic> notificationData;
      if (current.isStudentLeave) {
        final studentName = current.studentName?.isNotEmpty == true
            ? current.studentName!
            : 'the student';
        final defaultMessage =
            "$studentName's leave request has been $newStatus.";
        if (current.requesterRole == LeaveRequesterRole.parent) {
          // Submitted by the parent — notify the Parents audience, targeted
          // to exactly this one student so it only reaches that student's
          // linked parent account(s), not every parent.
          notificationData = {
            'title': approved ? 'Leave request approved' : 'Leave request rejected',
            'message': remarks?.isNotEmpty == true ? remarks! : defaultMessage,
            'notificationType': 'Leave',
            'category': 'Student',
            'priority': 'Normal',
            'audience': 'Parents',
            'visibility': 'Parents',
            'status': 'Draft',
            'academicYear': '',
            'appliesToAllClasses': false,
            'applicableClassIds': const [],
            'applicableClassNames': const [],
            'appliesToAllStudents': false,
            'applicableStudentIds': [current.studentId ?? ''],
            'applicableStudentNames': [studentName],
            'appliesToAllStaff': false,
            'applicableStaffIds': const [],
            'applicableStaffNames': const [],
            'isPublic': false,
            'createdBy': reviewedBy,
            'createdByName': reviewedBy,
          };
        } else {
          // Submitted by a staff member on the student's behalf — notify
          // that staff member, the same way a staff leave decision does.
          notificationData = {
            'title': approved ? 'Student leave approved' : 'Student leave rejected',
            'message': remarks?.isNotEmpty == true ? remarks! : defaultMessage,
            'notificationType': 'Leave',
            'category': 'Student',
            'priority': 'Normal',
            'audience': 'Staff',
            'visibility': 'Staff',
            'status': 'Draft',
            'academicYear': '',
            'appliesToAllClasses': false,
            'applicableClassIds': const [],
            'applicableClassNames': const [],
            'appliesToAllStudents': false,
            'applicableStudentIds': const [],
            'applicableStudentNames': const [],
            'appliesToAllStaff': false,
            'applicableStaffIds': [current.requesterId],
            'applicableStaffNames': [current.requesterName],
            'isPublic': false,
            'createdBy': reviewedBy,
            'createdByName': reviewedBy,
          };
        }
      } else {
        notificationData = {
          'title': approved ? 'Leave request approved' : 'Leave request rejected',
          'message': remarks?.isNotEmpty == true
              ? remarks!
              : 'Your ${current.leaveType} request has been $newStatus.',
          'notificationType': 'Leave',
          'category': 'HR/Staff',
          'priority': 'Normal',
          'audience': 'Staff',
          'visibility': 'Staff',
          'status': 'Draft',
          'academicYear': '',
          'appliesToAllClasses': false,
          'applicableClassIds': const [],
          'applicableClassNames': const [],
          'appliesToAllStudents': false,
          'applicableStudentIds': const [],
          'applicableStudentNames': const [],
          'appliesToAllStaff': false,
          'applicableStaffIds': [current.requesterId],
          'applicableStaffNames': [current.requesterName],
          'isPublic': false,
          'createdBy': reviewedBy,
          'createdByName': reviewedBy,
        };
      }
      final notificationId =
          await _notificationService.createNotification(notificationData);
      await _notificationService.publishNotification(notificationId);
    } catch (_) {
      // Ignored — the approve/reject already succeeded.
    }
  }

  Future<void> approveLeaveRequest(
    String id, {
    required String reviewedBy,
    String? remarks,
  }) =>
      _reviewRequest(
        id,
        newStatus: LeaveStatus.approved,
        reviewedBy: reviewedBy,
        remarks: remarks,
      );

  Future<void> rejectLeaveRequest(
    String id, {
    required String reviewedBy,
    String? remarks,
  }) =>
      _reviewRequest(
        id,
        newStatus: LeaveStatus.rejected,
        reviewedBy: reviewedBy,
        remarks: remarks,
      );
}
