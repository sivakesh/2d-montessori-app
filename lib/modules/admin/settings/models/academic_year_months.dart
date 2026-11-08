import 'package:intl/intl.dart';

import 'academic_year_date_range.dart';
import 'academic_year_model.dart';

/// The calendar months of an academic year up to today, for the monthly
/// dashboard charts: from the year's first day to whichever comes first,
/// its last day or today (inclusive calendar days, as
/// [AcademicYearDateRange.contains]). Future days and months are never
/// included; the current month counts only through today.
class AcademicYearMonths {
  AcademicYearMonths(this.year, DateTime today)
      : range = AcademicYearDateRange.fromAcademicYear(year),
        today = DateTime(today.year, today.month, today.day);

  final AcademicYearModel year;
  final AcademicYearDateRange range;
  final DateTime today;

  DateTime get start => range.start;

  /// The last day counted: the year's last day, or today if earlier.
  DateTime get end => today.isBefore(range.end) ? today : range.end;

  /// The year hasn't started yet: no months.
  bool get notStarted => today.isBefore(range.start);

  /// Each month from the start month through [end]'s month, as `YYYY-MM`.
  List<String> get months => notStarted
      ? const []
      : [for (var m = DateTime(start.year, start.month); !m.isAfter(end); m = DateTime(m.year, m.month + 1)) key(m)];

  /// Whether [d]'s calendar day is within [start]–[end].
  bool contains(DateTime? d) {
    if (d == null || notStarted) return false;
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// [d] counts in [month]: within the window and in that calendar month.
  bool containsIn(String month, DateTime? d) => contains(d) && key(d!) == month;

  /// The first and last counted day of [month] (the window clips the year's
  /// first month and the current one).
  (DateTime, DateTime) daysOf(String month) {
    final first = monthStart(month);
    final last = DateTime(first.year, first.month + 1, 0);
    return (first.isBefore(start) ? start : first, last.isAfter(end) ? end : last);
  }

  /// Whether [month] is counted for only part of it.
  bool isPartial(String month) {
    final (from, to) = daysOf(month);
    final first = monthStart(month);
    return from != first || to != DateTime(first.year, first.month + 1, 0);
  }

  static String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  static DateTime monthStart(String key) => DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(5)));
  static String label(String key) => DateFormat('MMMM yyyy').format(monthStart(key));
  static String shortLabel(String key) => DateFormat('MMM').format(monthStart(key));
}
