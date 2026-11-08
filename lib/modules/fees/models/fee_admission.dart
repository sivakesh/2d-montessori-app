import '../../admin/students/models/admission_date.dart';
import 'fee_due_date.dart';
import 'fee_month.dart';

/// Whether a student can be given a new fee assignment, by their Admission
/// Date (`students.admissionDate`). An eligibility rule for new
/// assignments only: existing assignments are never changed by it.
enum FeeAdmissionStatus {
  eligible,

  /// Admitted after the fee month ends (Monthly) or after the assignment
  /// date (Term / One-time).
  notYetAdmitted,

  /// No admission date recorded: not assumed eligible. Automatic
  /// assignments (Full Class, recurring, sync) skip the student for manual
  /// review.
  notRecorded,
}

abstract final class FeeAdmission {
  /// Monthly: eligible for [feeMonth] (`YYYY-MM`) when admitted on or
  /// before its last calendar day. The admission month is charged in full
  /// (no proration).
  static FeeAdmissionStatus forMonth(DateTime? admitted, String feeMonth) {
    if (admitted == null) return FeeAdmissionStatus.notRecorded;
    final (_, last) = FeeDueDate.monthRange(feeMonth);
    return AdmissionDate.dateOnly(admitted).isAfter(last) ? FeeAdmissionStatus.notYetAdmitted : FeeAdmissionStatus.eligible;
  }

  /// Term / One-time (no fee month): eligible when admitted on or before
  /// [assignmentDate], the date the assignment is made.
  static FeeAdmissionStatus forDate(DateTime? admitted, DateTime assignmentDate) {
    if (admitted == null) return FeeAdmissionStatus.notRecorded;
    return AdmissionDate.dateOnly(admitted).isAfter(AdmissionDate.dateOnly(assignmentDate))
        ? FeeAdmissionStatus.notYetAdmitted
        : FeeAdmissionStatus.eligible;
  }

  /// [forMonth] for a fee month, [forDate] otherwise.
  static FeeAdmissionStatus check(DateTime? admitted, {required String feeMonth, required DateTime assignmentDate}) =>
      feeMonth.isEmpty ? forDate(admitted, assignmentDate) : forMonth(admitted, feeMonth);

  /// The first fee month [admitted] is eligible for.
  static String firstMonth(DateTime admitted) => FeeMonth.of(admitted.year, admitted.month);

  /// Why a new assignment is refused for a student admitted on [admitted].
  static String notYetAdmittedMessage(String student, DateTime admitted, {required String feeMonth, required DateTime assignmentDate}) {
    final who = student.trim().isEmpty ? 'This student' : student.trim();
    final on = AdmissionDate.label(admitted);
    return feeMonth.isEmpty
        ? '$who was admitted on $on, after the assignment date (${AdmissionDate.label(assignmentDate)}), so this fee can’t be assigned yet.'
        : '$who was admitted on $on, after ${FeeMonth.label(feeMonth)} ends, so that month can’t be assigned. '
            'The first eligible month is ${FeeMonth.label(firstMonth(admitted))}.';
  }

  static const notRecordedMessage = 'Admission date not recorded: skipped for manual review. Record the admission date (Students → Edit) to include them.';
}
