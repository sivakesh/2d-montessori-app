import '../../admin/settings/models/academic_year_model.dart';
import 'fee_due_date.dart';
import 'fee_month.dart';

/// One month of a recurring monthly assignment: the fee month, the
/// academic year that month belongs to, and its own due date.
class FeeMonthPlan {
  const FeeMonthPlan({required this.feeMonth, required this.academicYearId, required this.academicYear, required this.dueDate});

  final String feeMonth, academicYearId, academicYear;
  final DateTime dueDate;
}

/// The due-date rule for a recurring monthly assignment: the same [day] of
/// every month (a shorter month uses its last day), in the fee month itself
/// ([monthOffset] 0) or the following month (1).
class FeeDueRule {
  const FeeDueRule({required this.day, this.monthOffset = 0}) : assert(monthOffset == 0 || monthOffset == 1);

  final int day;
  final int monthOffset;

  /// The due date for [feeMonth] (`YYYY-MM`).
  DateTime dueFor(String feeMonth) {
    final (first, _) = FeeDueDate.monthRange(feeMonth);
    final month = DateTime(first.year, first.month + monthOffset);
    return FeeDueDate.dayInMonth(month.year, month.month, day)!;
  }

  String get description =>
      'Day $day of ${monthOffset == 0 ? 'each fee month' : 'the month after each fee month'} (a shorter month uses its last day)';
}

abstract final class FeeMonthRange {
  /// The `YYYY-MM` after [feeMonth].
  static String next(String feeMonth) {
    final (first, _) = FeeDueDate.monthRange(feeMonth);
    final d = DateTime(first.year, first.month + 1);
    return FeeMonth.of(d.year, d.month);
  }

  /// Every month from [start] to [end], both included; empty when [end]
  /// is before [start] or either isn't a month.
  static List<String> months(String start, String end) {
    if (!FeeMonth.isValid(start) || !FeeMonth.isValid(end) || end.compareTo(start) < 0) return const [];
    final out = <String>[];
    for (var m = start; m.compareTo(end) <= 0; m = next(m)) {
      out.add(m);
    }
    return out;
  }

  /// "June 2026 – March 2027 (10 monthly assignments)".
  static String summary(List<String> months) {
    if (months.isEmpty) return '';
    final n = months.length;
    final span = n == 1 ? FeeMonth.label(months.first) : '${FeeMonth.label(months.first)} – ${FeeMonth.label(months.last)}';
    return '$span ($n monthly ${n == 1 ? 'assignment' : 'assignments'})';
  }

  /// The academic year among [years] whose dates contain [feeMonth]'s
  /// first day, or null.
  static AcademicYearModel? yearOf(String feeMonth, Iterable<AcademicYearModel> years) {
    final (first, _) = FeeDueDate.monthRange(feeMonth);
    for (final y in years) {
      final start = FeeDueDate.dateOnly(y.startDate), end = FeeDueDate.dateOnly(y.endDate);
      if (!first.isBefore(DateTime(start.year, start.month)) && !first.isAfter(end)) return y;
    }
    return null;
  }

  /// One plan per month from [start] to [end]: each month's own academic
  /// year (from [years]) and due date (from [rule]). Throws a StateError,
  /// before anything is written, when the range is empty or reversed or a
  /// month falls in no configured academic year.
  static List<FeeMonthPlan> plan(String start, String end, Iterable<AcademicYearModel> years, FeeDueRule rule) {
    final list = months(start, end);
    if (list.isEmpty) throw StateError('Assign Until must be the same as or after the Start Fee Month.');
    return [
      for (final m in list)
        if (yearOf(m, years) case final y?)
          FeeMonthPlan(feeMonth: m, academicYearId: y.id, academicYear: y.name, dueDate: rule.dueFor(m))
        else
          throw StateError('${FeeMonth.label(m)} is not in any configured academic year.'),
    ];
  }
}
