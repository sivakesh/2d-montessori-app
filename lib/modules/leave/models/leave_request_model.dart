import 'package:cloud_firestore/cloud_firestore.dart';

/// Fixed leave-type list, shared by both Staff Leave and Student Leave —
/// a student absence request ("Sick Leave", "Casual Leave", etc.) uses the
/// exact same vocabulary as a staff one, so there is no separate list.
class LeaveType {
  static const sick = 'Sick Leave';
  static const casual = 'Casual Leave';
  static const earned = 'Earned Leave';
  static const other = 'Other';

  static const all = [sick, casual, earned, other];
}

/// Simple lifecycle: Pending -> Approved | Rejected. There is no "Cancelled"
/// state — the MVP spec calls for it only if genuinely required, and no
/// existing workflow here needs a withdrawal, so it's left out rather than
/// added speculatively.
class LeaveStatus {
  static const pending = 'Pending';
  static const approved = 'Approved';
  static const rejected = 'Rejected';
}

/// What the request is *about* — a staff member's own absence, or a
/// student's. The two subjects share one Firestore collection (see
/// LeaveService's doc comment for why), so every query must filter on this
/// field explicitly rather than relying on which other fields happen to be
/// populated.
class LeaveSubjectType {
  static const staff = 'staff';
  static const student = 'student';
}

/// Who submitted the request — a staff member (for their own leave, or on
/// behalf of a student) or a parent (on behalf of their linked child).
class LeaveRequesterRole {
  static const staff = 'staff';
  static const parent = 'parent';
}

/// A student leave request may span at most this many calendar days
/// (inclusive of both the start and end date) — enforced in both
/// [LeaveService.submitStudentLeaveRequest] and the submission dialog, so
/// neither a UI slip nor a direct service call can create a longer one.
class StudentLeavePolicy {
  static const maxDays = 5;
}

class LeaveRequestModel {
  LeaveRequestModel({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.requesterRole,
    required this.subjectType,
    required this.studentId,
    required this.studentName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.reviewRemarks,
  });

  final String id;
  final String requesterId;
  final String requesterName;
  /// 'staff' | 'parent' — who submitted this request.
  final String requesterRole;
  /// 'staff' | 'student' — who the leave is *for*.
  final String subjectType;
  /// Populated only when [subjectType] is 'student'.
  final String? studentId;
  final String? studentName;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewRemarks;

  bool get isStudentLeave => subjectType == LeaveSubjectType.student;

  factory LeaveRequestModel.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return LeaveRequestModel(
      id: id,
      requesterId: map['requesterId']?.toString() ?? '',
      requesterName: map['requesterName']?.toString() ?? '',
      // Every request written before Student Leave existed is a staff
      // member's own leave, submitted by that same staff member — so
      // both default to 'staff' for old documents that never had these
      // fields, keeping them correctly classified without a migration.
      requesterRole: map['requesterRole']?.toString() ?? LeaveRequesterRole.staff,
      subjectType: map['subjectType']?.toString() ?? LeaveSubjectType.staff,
      studentId: map['studentId']?.toString(),
      studentName: map['studentName']?.toString(),
      leaveType: map['leaveType']?.toString() ?? LeaveType.other,
      startDate: parseDate(map['startDate']) ?? DateTime(2000),
      endDate: parseDate(map['endDate']) ?? DateTime(2000),
      reason: map['reason']?.toString() ?? '',
      status: map['status']?.toString() ?? LeaveStatus.pending,
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      reviewedBy: map['reviewedBy']?.toString(),
      reviewedAt: parseDate(map['reviewedAt']),
      reviewRemarks: map['reviewRemarks']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'requesterId': requesterId,
        'requesterName': requesterName,
        'requesterRole': requesterRole,
        'subjectType': subjectType,
        'studentId': studentId,
        'studentName': studentName,
        'leaveType': leaveType,
        'startDate': startDate,
        'endDate': endDate,
        'reason': reason,
        'status': status,
        'reviewedBy': reviewedBy,
        'reviewedAt': reviewedAt,
        'reviewRemarks': reviewRemarks,
      };
}
