import 'package:cloud_firestore/cloud_firestore.dart';

/// Thrown when a non-admin role attempts to create/update/set-current/
/// (de)activate an Academic Year via [AcademicYearService] — enforced at the
/// service layer itself (not only by which screens a role's navigation
/// exposes), the same shape as [UnauthorizedSchoolSettingsException] in the
/// School Settings module. Reading academic years (the list, the current
/// year, a single year by id) is never role-gated — other modules across the
/// app (Attendance, Fees, Dashboard, ...) need to read the current academic
/// year regardless of the signed-in role, exactly like
/// [SchoolSettingsService.getSchoolIdentity] is open to every role while
/// only editing the record is Admin-only.
class UnauthorizedAcademicYearException implements Exception {
  UnauthorizedAcademicYearException(this.role);
  final String role;

  @override
  String toString() => 'You are not authorized to manage Academic Years.';
}

/// Field-level validation failure (missing name, missing dates, end date not
/// after start date, duplicate name) — never a Firestore/authorization
/// failure. Carries a human-readable [message] meant to be shown directly in
/// a SnackBar/form error, the same shape [ArgumentError] is used for in
/// SchoolSettingsService, but as its own domain type so callers can
/// distinguish "fix your input" from "overlaps another year" from
/// "not authorized" without parsing message text.
class AcademicYearValidationException implements Exception {
  AcademicYearValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when a candidate `[startDate, endDate]` range overlaps an existing
/// academic year for the same school — see [AcademicYearModel.overlaps] for
/// the exact (inclusive) overlap rule.
class AcademicYearOverlapException implements Exception {
  AcademicYearOverlapException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when an operation targets an academic year id that doesn't exist
/// (or doesn't belong to the given school — see the schoolId isolation note
/// on [AcademicYearService.getAcademicYearById]).
class AcademicYearNotFoundException implements Exception {
  AcademicYearNotFoundException(this.id);
  final String id;

  @override
  String toString() => 'Academic year "$id" was not found.';
}

/// Academic Year — the single source of truth for "which school year is
/// this" across the app (Students, Classes, Fees, Attendance, Leave,
/// Finance, Reports). A person (Student/Staff/Parent) is a permanent
/// identity; an Academic Year is a slice of *time/context* a person
/// participates in during a given year. This model only represents that
/// slice of time itself — it deliberately holds no student/staff/class
/// data, so nothing about a person's identity ever needs to change when a
/// new academic year is added or the current one changes.
///
/// [id] is a stable, Firestore-auto-generated document id — never derived
/// from [name] — so renaming a year (a display-text edit) can never change
/// its identity or break anything that references it by id.
class AcademicYearModel {
  const AcademicYearModel({
    required this.id,
    required this.schoolId,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.isCurrent,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  final String id;
  final String schoolId;
  final String name;
  /// Date-only (time-of-day is always normalized to midnight when stored —
  /// see [AcademicYearService]) — the first day this academic year covers,
  /// inclusive.
  final DateTime startDate;
  /// Date-only, inclusive — the last day this academic year covers.
  final DateTime endDate;
  /// At most one academic year per school may have this set — see
  /// [AcademicYearService.setCurrentAcademicYear].
  final bool isCurrent;
  /// False means "deactivated" (hidden from active use, e.g. as a target
  /// for "Set as Current") — never means deleted. Deactivating a year never
  /// touches any historical record that references it.
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  /// True if [date]'s calendar day falls within `[startDate, endDate]`
  /// inclusive — the basis for deriving "which academic year is this
  /// date-based record in" for Attendance/Leave/Calendar reporting without
  /// those records needing their own `academicYearId` field.
  bool containsDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  /// True if `[startDate, endDate]` and the given `[otherStart, otherEnd]`
  /// share any calendar day (inclusive on both ends) — the rule
  /// [AcademicYearService] enforces so academic years can never overlap.
  bool overlaps(DateTime otherStart, DateTime otherEnd) {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    final os = DateTime(otherStart.year, otherStart.month, otherStart.day);
    final oe = DateTime(otherEnd.year, otherEnd.month, otherEnd.day);
    return !e.isBefore(os) && !s.isAfter(oe);
  }

  factory AcademicYearModel.fromMap(String id, Map<String, dynamic> data) {
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

    return AcademicYearModel(
      id: id,
      schoolId: data['schoolId']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      startDate: parseDate(data['startDate'], DateTime(2000, 1, 1)),
      endDate: parseDate(data['endDate'], DateTime(2000, 1, 1)),
      isCurrent: data['isCurrent'] == true,
      isActive: data['isActive'] != false,
      createdAt: parseOptionalDate(data['createdAt']),
      updatedAt: parseOptionalDate(data['updatedAt']),
      createdBy: data['createdBy']?.toString(),
      updatedBy: data['updatedBy']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'schoolId': schoolId,
        'name': name,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'isCurrent': isCurrent,
        'isActive': isActive,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
      };
}

/// Field-level validation shared by the Academic Year form's own
/// [TextFormField.validator]s and [AcademicYearService]'s own re-check, the
/// same "single source of truth for validation" shape as
/// SchoolSettingsValidation.
class AcademicYearValidation {
  const AcademicYearValidation._();

  /// Null when valid. The display name is required (existing `academicYear`
  /// free-text fields on Class/Fee Structure/Student Fee Assignment already
  /// establish that this app shows a year as a name, not just raw dates) —
  /// see [suggestName] for the default value offered before an admin edits
  /// it.
  static String? validateName(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Academic Year name is required.';
    return null;
  }

  /// Null when valid. Requires strictly-after (at least one day) — a
  /// same-day start/end is rejected, matching "reject ... same start/end if
  /// the application requires at least one day" in the SETTINGS-02 spec.
  static String? validateDates(DateTime? start, DateTime? end) {
    if (start == null) return 'Start date is required.';
    if (end == null) return 'End date is required.';
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    if (!e.isAfter(s)) return 'End date must be after the start date.';
    return null;
  }

  /// The default display name offered for a `[start, end]` range, following
  /// the exact free-text convention already used by
  /// AdminClassModel/FeeStructureModel/StudentFeeAssignmentModel's own
  /// `academicYear` fields (e.g. `"2026-2027"`) — kept editable by the admin
  /// rather than enforced, since a school may prefer a different label.
  static String suggestName(DateTime start, DateTime end) {
    if (start.year == end.year) return '${start.year}';
    return '${start.year}-${end.year}';
  }
}
