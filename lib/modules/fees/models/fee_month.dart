import 'fee_structure_model.dart';

/// The month a Monthly fee assignment is for, stored on the assignment
/// (and copied to its receipts and transactions) as `feeMonth`: the
/// calendar month as `YYYY-MM`, e.g. `2027-01`. The year is the one the
/// month falls in within the assignment's academic year, so "January" in
/// 2026–2027 is `2027-01`. Assignments made before months were recorded
/// have none (`''`); none is ever inferred.
abstract final class FeeMonth {
  static const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  static final _pattern = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$');

  static bool isValid(String value) => _pattern.hasMatch(value);

  static String of(int year, int month) => '$year-${month.toString().padLeft(2, '0')}';

  /// The month number (1–12) of [value], or null.
  static int? monthOf(String value) => switch (_pattern.firstMatch(value)) { final m? => int.parse(m.group(2)!), _ => null };

  /// "January 2027", or '' when [value] isn't a fee month.
  static String label(String value) {
    final m = _pattern.firstMatch(value);
    if (m == null) return '';
    return '${names[int.parse(m.group(2)!) - 1]} ${m.group(1)}';
  }

  /// [month] (1–12) as the fee month within the academic year running from
  /// [start] to [end] (the first such calendar month), or null when that
  /// month isn't in the range.
  static String? inAcademicYear(int month, DateTime start, DateTime end) {
    var d = DateTime(start.year, start.month);
    final last = DateTime(end.year, end.month);
    while (!d.isAfter(last)) {
      if (d.month == month) return of(d.year, d.month);
      d = DateTime(d.year, d.month + 1);
    }
    return null;
  }

  /// Whether assignments of [structure] are for one month: every component
  /// is monthly. A structure with no components, or mixing monthly with
  /// term or one-time components, is not (its assignments stay as before).
  static bool isMonthlyStructure(FeeStructureModel structure) =>
      structure.components.isNotEmpty && structure.components.every((c) => c.frequency == 'monthly');
}
