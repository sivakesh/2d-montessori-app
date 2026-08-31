// AY-IMPLEMENT-03 coverage: AcademicYearDateRange, the shared value object
// every date-derived module (Attendance, Leave, Calendar, Finance, Mood
// Check-ins) uses to answer "does this record belong to this Academic
// Year" from the record's own date field, without adding an
// `academicYearId` field anywhere. Module-specific query-support tests
// live in their own test files.
import 'package:flutter_test/flutter_test.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_date_range.dart';
import 'package:montessori_app/modules/admin/settings/models/academic_year_model.dart';

AcademicYearModel _year({DateTime? start, DateTime? end}) {
  return AcademicYearModel(
    id: 'ay-1',
    schoolId: 'default_school',
    name: '2026-2027',
    startDate: start ?? DateTime(2026, 6, 1),
    endDate: end ?? DateTime(2027, 3, 30),
    isCurrent: true,
    isActive: true,
    createdAt: null,
    updatedAt: null,
  );
}

void main() {
  group('AcademicYearDateRange (AY-IMPLEMENT-03)', () {
    test('1. Start date is included', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      expect(range.contains(DateTime(2026, 6, 1)), isTrue);
    });

    test('2. End date is included', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      expect(range.contains(DateTime(2027, 3, 30)), isTrue);
    });

    test('3. Date before start is excluded', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      expect(range.contains(DateTime(2026, 5, 31)), isFalse);
    });

    test('4. Date after end is excluded', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      expect(range.contains(DateTime(2027, 3, 31)), isFalse);
    });

    test('5. Date in the middle is included', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      expect(range.contains(DateTime(2026, 12, 25)), isTrue);
    });

    test('6. Date normalization does not introduce timezone/time-of-day boundary errors', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      // A record timestamped late in the evening on the start date, or
      // just after midnight on the end date, must still be included —
      // only the calendar day matters, never the time-of-day component.
      expect(range.contains(DateTime(2026, 6, 1, 23, 59, 59)), isTrue);
      expect(range.contains(DateTime(2027, 3, 30, 0, 0, 1)), isTrue);
      // Conversely, a time-of-day component must never smuggle a truly
      // out-of-range day into the range (e.g. 23:59 the day before start).
      expect(range.contains(DateTime(2026, 5, 31, 23, 59, 59)), isFalse);
    });

    test('contains() agrees exactly with AcademicYearModel.containsDate() for every case above', () {
      final year = _year();
      final range = AcademicYearDateRange.fromAcademicYear(year);
      final probes = [
        DateTime(2026, 6, 1),
        DateTime(2027, 3, 30),
        DateTime(2026, 5, 31),
        DateTime(2027, 3, 31),
        DateTime(2026, 12, 25),
        DateTime(2026, 6, 1, 23, 59, 59),
        DateTime(2027, 3, 30, 0, 0, 1),
      ];
      for (final probe in probes) {
        expect(range.contains(probe), year.containsDate(probe), reason: 'disagreement at $probe');
      }
    });

    test('queryUpperBound is the exclusive instant immediately after the last inclusive day', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      expect(range.queryUpperBound, DateTime(2027, 3, 31));
      // A Timestamp query using `isLessThan: queryUpperBound` must still
      // include a record timestamped at 23:59:59 on the end date — the
      // exact bug this getter exists to prevent.
      final lateOnEndDate = DateTime(2027, 3, 30, 23, 59, 59);
      expect(lateOnEndDate.isBefore(range.queryUpperBound), isTrue);
      // ...and correctly exclude the instant the next day begins.
      final startOfNextDay = DateTime(2027, 3, 31);
      expect(startOfNextDay.isBefore(range.queryUpperBound), isFalse);
    });

    test('start/end expose the resolved AcademicYear identity', () {
      final range = AcademicYearDateRange.fromAcademicYear(_year());
      expect(range.academicYearId, 'ay-1');
      expect(range.academicYearName, '2026-2027');
    });
  });
}
