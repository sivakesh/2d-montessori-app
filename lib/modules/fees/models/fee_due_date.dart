import 'package:intl/intl.dart';

import 'fee_month.dart';
import 'fee_structure_model.dart';
import 'student_fee_assignment_model.dart';

/// A due date the Assign Fee dialog offers before the administrator
/// chooses: [date] (null when the structure can't determine one, so a date
/// must be chosen) and [note], which says where it came from or why there
/// is none.
class FeeDueDefault {
  const FeeDueDefault(this.date, this.note);
  final DateTime? date;
  final String note;
}

/// Assignment due dates (`student_fee_assignments.dueDate`, a calendar
/// date stored at local midnight) and the overdue rule.
abstract final class FeeDueDate {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// "5 Jan 2027".
  static String label(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// Day [day] of [month] in [year]; a day the month doesn't have (the
  /// 31st in February) is that month's last day. Null for a day that is no
  /// day of any month (below 1 or above 31).
  static DateTime? dayInMonth(int year, int month, int day) {
    if (day < 1 || day > 31) return null;
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day > last ? last : day);
  }

  /// The first and last day of [feeMonth].
  static (DateTime, DateTime) monthRange(String feeMonth) {
    final y = int.parse(feeMonth.substring(0, 4)), m = FeeMonth.monthOf(feeMonth)!;
    return (DateTime(y, m), DateTime(y, m + 1, 0));
  }

  /// The default due date for a new assignment of [structure], from its
  /// components' own configuration (`dueDayOfMonth` for a Monthly
  /// component, `dueDate` for a Term or One-time one):
  /// - Monthly (every component monthly): their Due Day of Month in
  ///   [feeMonth] (the last day for a shorter month), when they all set the
  ///   same valid day.
  /// - Term and One-time: their Default Due Date, when they all set the
  ///   same one.
  /// - Mixed: the Term/One-time components' shared Default Due Date, when
  ///   any monthly Due Day of Month agrees with it (falls on that date). A
  ///   mixed assignment has no fee month, so a monthly due day alone gives
  ///   no date; different dates, or a day that doesn't fall on the date,
  ///   conflict and give none.
  /// Components with nothing set never conflict. Anything else (none set,
  /// a conflict, an invalid day, or no month chosen yet) gives no date, so
  /// one must be chosen; the [FeeDueDefault.note] says why. Never derived
  /// from the creation date, a term name or the academic year.
  static FeeDueDefault defaultFor(FeeStructureModel structure, String feeMonth) {
    final days = {for (final c in structure.components) if (c.frequency == 'monthly' && c.dueDayOfMonth != null) c.dueDayOfMonth!};
    final sortedDays = (days.toList()..sort()).join(', ');
    final badDay = days.where((d) => d < 1 || d > 31).firstOrNull;
    if (FeeMonth.isMonthlyStructure(structure)) {
      if (days.isEmpty) return const FeeDueDefault(null, 'This fee structure has no due day of month set. Choose the due date.');
      if (days.length > 1) return FeeDueDefault(null, 'This fee structure’s components have different due days ($sortedDays). Choose the due date.');
      final day = days.single;
      if (badDay != null) return FeeDueDefault(null, 'This fee structure’s due day ($day) is not a day of the month. Choose the due date.');
      if (feeMonth.isEmpty) return FeeDueDefault(null, 'Choose the fee month: the due date defaults to day $day of it.');
      final (first, _) = monthRange(feeMonth);
      final date = dayInMonth(first.year, first.month, day)!;
      return FeeDueDefault(
        date,
        date.day == day
            ? 'Defaults to the structure’s due day ($day). You can change it.'
            : '${FeeMonth.label(feeMonth)} has no day $day, so it defaults to its last day. You can change it.',
      );
    }
    final dates = {for (final c in structure.components) if (c.frequency != 'monthly' && c.dueDate != null) dateOnly(c.dueDate!)};
    final mixed = structure.components.any((c) => c.frequency == 'monthly');
    if (dates.length > 1) {
      final list = (dates.toList()..sort()).map(label).join(', ');
      return FeeDueDefault(null, 'This fee structure’s components have different due dates ($list). Choose the due date for this assignment.');
    }
    if (mixed && days.isNotEmpty) {
      if (days.length > 1) {
        return FeeDueDefault(null, 'This fee structure’s monthly components have different due days ($sortedDays). Choose the due date for this assignment.');
      }
      final day = days.single;
      if (badDay != null) return FeeDueDefault(null, 'This fee structure’s monthly due day ($day) is not a day of the month. Choose the due date.');
      if (dates.isEmpty) {
        return FeeDueDefault(null,
            'This fee structure mixes monthly and term or one-time components, so it has no fee month for the monthly due day ($day). Choose the due date for this assignment.');
      }
      final date = dates.single;
      if (dayInMonth(date.year, date.month, day) != date) {
        return FeeDueDefault(null,
            'This fee structure’s due dates conflict: the monthly due day ($day) does not fall on the term or one-time due date (${label(date)}). Choose the due date for this assignment.');
      }
    }
    if (dates.length == 1) return FeeDueDefault(dates.single, 'Defaults to the structure’s due date. You can change it.');
    return const FeeDueDefault(null, 'This fee structure has no default due date set. Choose the due date for this fee.');
  }

  /// Why [structure]'s components' due-date configuration gives no shared
  /// default (a mixed structure whose dates or days conflict), or null.
  /// Shown on the structure itself; nothing is changed.
  static String? configurationConflict(FeeStructureModel structure) {
    if (FeeMonth.isMonthlyStructure(structure)) {
      final days = {for (final c in structure.components) if (c.dueDayOfMonth != null) c.dueDayOfMonth!};
      return days.length > 1 ? defaultFor(structure, '').note : null;
    }
    final configured = structure.components.any((c) => c.frequency == 'monthly' ? c.dueDayOfMonth != null : c.dueDate != null);
    if (!configured) return null;
    final d = defaultFor(structure, '');
    return d.date == null ? d.note : null;
  }

  /// Overdue, worked out when read (nothing is written when a date
  /// passes): an outstanding balance and a due date before [today]'s
  /// local calendar day. Due today, due later, paid in full, no due date,
  /// or cancelled: not overdue. The stored `status` is never consulted
  /// beyond 'cancelled'; a voided payment is already back in the balance.
  static bool isOverdue(StudentFeeAssignmentModel a, DateTime today) {
    final due = a.dueDate;
    if (due == null || a.status == 'cancelled') return false;
    if ((a.balanceAmount * 100).round() <= 0) return false;
    return dateOnly(due).isBefore(dateOnly(today));
  }

  /// The number of distinct students with at least one overdue assignment
  /// among [assignments].
  static int overdueStudents(Iterable<StudentFeeAssignmentModel> assignments, DateTime today) =>
      {for (final a in assignments) if (isOverdue(a, today)) a.studentId}.length;
}
