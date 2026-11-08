import 'package:flutter/foundation.dart';

import '../../admin/settings/models/academic_year_model.dart';
import 'fee_receipt_model.dart';
import 'fee_student.dart';
import 'student_fee_assignment_model.dart';

/// The Fees module's shared Academic Year / Class / Student filter, applied
/// the same way by Assignments, Collections, Receipts, Dues and Students.
/// Every match uses stored ids: nothing is inferred from a display name.
///
/// - Academic year: an assignment's own `academicYearId`. An older
///   assignment saved before that id existed is matched by its own stored
///   `academicYear` label, exactly equal to the year's name (the app's
///   existing rule for records without an id, as for classes); one with
///   neither shows only under All Academic Years.
/// - Class: the class the assignment was made under (its own `classId`),
///   so a past year's assignment stays with the class it belonged to. On
///   the Students tab, the student's current class.
/// - Student: the stable `studentId`.
/// - Fee month: the assignment's own stored `feeMonth` (never a creation
///   or payment date). Term, One-time and other non-monthly fees have no
///   month and are never hidden by a month (they are listed in their own
///   section); an older Monthly assignment with no month recorded matches
///   only All Months. [monthlyStructureIds] says which structures are
///   Monthly (FeeMonth.isMonthlyStructure); a structure not known to be
///   Monthly counts as non-monthly.
/// - Receipts: through their linked assignment (`assignmentId`). A receipt
///   whose assignment can't be found has no year or class to go by, so it
///   shows only under All Academic Years, All Classes and All Months
///   (matched by its own `studentId` for the Student filter).
@immutable
class FeeListFilter {
  const FeeListFilter({this.year, this.classId, this.studentId, this.feeMonth, this.monthlyStructureIds = const {}});

  /// null: All Academic Years.
  final AcademicYearModel? year;

  /// null: All Classes / All Students.
  final String? classId, studentId;

  /// `YYYY-MM`; null: All Months.
  final String? feeMonth;

  final Set<String> monthlyStructureIds;

  /// Whether [a] is for [feeMonth]: its own month, or any month for a
  /// non-monthly fee (which has none).
  bool assignmentInMonth(StudentFeeAssignmentModel a) {
    final month = feeMonth;
    if (month == null || a.feeMonth == month) return true;
    return a.feeMonth.isEmpty && !monthlyStructureIds.contains(a.feeStructureId);
  }

  bool assignmentInYear(StudentFeeAssignmentModel a) {
    final y = year;
    if (y == null) return true;
    if (a.academicYearId.isNotEmpty) return a.academicYearId == y.id;
    final label = a.academicYear.trim().toLowerCase();
    return label.isNotEmpty && label == y.name.trim().toLowerCase();
  }

  bool matchesAssignment(StudentFeeAssignmentModel a) =>
      assignmentInYear(a) &&
      (classId == null || a.classId == classId) &&
      (studentId == null || a.studentId == studentId) &&
      assignmentInMonth(a);

  /// [linked] is the receipt's assignment, or null when it can't be found.
  bool matchesReceipt(FeeReceiptModel r, StudentFeeAssignmentModel? linked) {
    if (linked != null) return matchesAssignment(linked);
    if (year != null || classId != null || feeMonth != null) return false;
    return studentId == null || r.studentId == studentId;
  }

  /// Students tab: by the student's current class and id. The academic
  /// year never hides a student; it selects which year's fees are shown.
  bool matchesStudent(FeeStudent s) => (classId == null || s.classId == classId) && (studentId == null || s.id == studentId);
}

/// Whether [student] belongs to [classId] for the Student filter: their
/// current class, or a class they have a fee assignment under (a past
/// year's class).
bool studentInClass(String studentId, String currentClassId, String classId, Iterable<StudentFeeAssignmentModel> assignments) =>
    currentClassId == classId || assignments.any((a) => a.studentId == studentId && a.classId == classId);
