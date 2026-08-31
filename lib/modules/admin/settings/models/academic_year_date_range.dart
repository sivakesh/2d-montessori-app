import 'academic_year_model.dart';

/// AY-IMPLEMENT-03: the shared building block every date-derived module
/// (Attendance, Leave, Calendar, Finance, Mood Check-ins) uses to answer
/// "does this record belong to this Academic Year" purely from the
/// record's own date field — never by adding an `academicYearId` field to
/// that record. Academic Year is context applied at query/report time for
/// these modules, not a field that belongs on every date-stamped document
/// (see AY-AUDIT-02's classification: Attendance/Leave/Calendar/general
/// Finance/Mood Check-ins are all "B — Date-Derived").
///
/// Wraps [AcademicYearModel.startDate]/[endDate] as a date-only, inclusive
/// `[start, end]` range. [contains] reuses the exact same day-only
/// comparison as [AcademicYearModel.containsDate], so a range built from a
/// given year can never disagree with the model it came from.
class AcademicYearDateRange {
  AcademicYearDateRange.fromAcademicYear(AcademicYearModel year)
      : academicYearId = year.id,
        academicYearName = year.name,
        start = _dateOnly(year.startDate),
        end = _dateOnly(year.endDate);

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  final String academicYearId;
  final String academicYearName;

  /// Inclusive lower bound, normalized to midnight of the first day.
  final DateTime start;

  /// Inclusive upper bound, normalized to midnight of the last day. Safe to
  /// use directly for a date-only comparison ([contains]) or a
  /// date-*string*-keyed Firestore query (e.g. Attendance's own
  /// `yyyy-MM-dd` `date` field). Do **not** use this directly as an
  /// `isLessThanOrEqualTo` bound in a Firestore range query against a
  /// Timestamp field that may carry a time-of-day component (a leave
  /// `startDate`, a calendar `date`, a payment `paymentDate`, ...) — since
  /// [end] is midnight, that would silently exclude any record timestamped
  /// later that same day. Use [queryUpperBound] instead for that case.
  final DateTime end;

  /// True if [date]'s calendar day falls within `[start, end]` inclusive.
  bool contains(DateTime date) {
    final d = _dateOnly(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// The exclusive upper bound for a Firestore Timestamp range query
  /// (`isLessThan: queryUpperBound`) — the instant immediately after the
  /// last inclusive day, so every moment of [end] itself is still
  /// included, exactly the way [MoodCheckinService]'s own existing
  /// `_todayQuery()` already computes "the rest of today" as `start.add(1
  /// day)` used with `isLessThan`.
  DateTime get queryUpperBound => end.add(const Duration(days: 1));
}
