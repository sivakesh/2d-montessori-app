import 'package:cloud_firestore/cloud_firestore.dart';

/// A student's status within one academic year's enrollment. Plain string
/// constants (not a Dart `enum`), matching every other status/category
/// field in this codebase (LeaveStatus, CalendarEventStatus,
/// AdminNotificationModel.status, ...).
class StudentEnrollmentStatus {
  static const active = 'Active';
  static const completed = 'Completed';
  static const withdrawn = 'Withdrawn';

  static const all = [active, completed, withdrawn];
}

/// Thrown when a role other than Admin/Staff attempts to create/update a
/// [StudentEnrollmentModel] via [StudentEnrollmentService] — enforced at the
/// service layer, the same shape as [UnauthorizedAcademicYearException]. The
/// allowed-role set is Admin *and* Staff (not Admin-only) because the audit
/// found Student/Class editing already has no Admin-only restriction
/// anywhere in the live app (Staff shares the exact same
/// AdminStudentForm/AdminStudentService access as Admin) — this service
/// follows that existing permission boundary rather than inventing a
/// stricter one Staff never had.
class UnauthorizedStudentEnrollmentException implements Exception {
  UnauthorizedStudentEnrollmentException(this.role);
  final String role;

  @override
  String toString() => 'You are not authorized to manage student enrollment.';
}

/// Field-level validation failure (missing studentId/academicYearId/
/// classId, invalid status).
class StudentEnrollmentValidationException implements Exception {
  StudentEnrollmentValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when creating an Active enrollment for a (studentId,
/// academicYearId) pair that already has one — the "at most one active
/// enrollment per student per academic year" rule.
class DuplicateActiveEnrollmentException implements Exception {
  DuplicateActiveEnrollmentException({required this.studentId, required this.academicYearId});
  final String studentId;
  final String academicYearId;

  @override
  String toString() =>
      'This student already has an active enrollment for this academic year.';
}

class StudentEnrollmentNotFoundException implements Exception {
  StudentEnrollmentNotFoundException(this.id);
  final String id;

  @override
  String toString() => 'Enrollment "$id" was not found.';
}

/// A student's placement in one class for one academic year — the
/// historical relationship `AcademicYear -> Class -> Student` is expressed
/// through this join record, not by rewriting [AdminClassModel] or
/// `Student.classId` themselves. `Student` remains one permanent identity;
/// this record is what lets that one identity have a different class in
/// every academic year without ever being duplicated.
///
/// [academicYearId] always references the canonical
/// [AcademicYearModel] by id — never a free-text year string like
/// AdminClassModel/FeeStructureModel's own loose `academicYear` field — so
/// this relationship stays correct even if a year's display name is later
/// edited.
class StudentEnrollmentModel {
  const StudentEnrollmentModel({
    required this.id,
    required this.schoolId,
    required this.studentId,
    required this.academicYearId,
    required this.classId,
    required this.status,
    required this.enrollmentDate,
    this.leavingDate,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final String id;
  final String schoolId;
  final String studentId;
  final String academicYearId;
  final String classId;
  final String status;
  final DateTime enrollmentDate;
  final DateTime? leavingDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  bool get isActive => status == StudentEnrollmentStatus.active;

  factory StudentEnrollmentModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic v, DateTime fallback) {
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      return fallback;
    }

    DateTime? parseOptionalDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return StudentEnrollmentModel(
      id: id,
      schoolId: data['schoolId']?.toString() ?? '',
      studentId: data['studentId']?.toString() ?? '',
      academicYearId: data['academicYearId']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      status: data['status']?.toString() ?? StudentEnrollmentStatus.active,
      enrollmentDate: parseDate(data['enrollmentDate'], DateTime(2000, 1, 1)),
      leavingDate: parseOptionalDate(data['leavingDate']),
      createdAt: parseOptionalDate(data['createdAt']),
      updatedAt: parseOptionalDate(data['updatedAt']),
      createdBy: data['createdBy']?.toString(),
      updatedBy: data['updatedBy']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'schoolId': schoolId,
        'studentId': studentId,
        'academicYearId': academicYearId,
        'classId': classId,
        'status': status,
        'enrollmentDate': Timestamp.fromDate(enrollmentDate),
        'leavingDate': leavingDate != null ? Timestamp.fromDate(leavingDate!) : null,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
      };
}
