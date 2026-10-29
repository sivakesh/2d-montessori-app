import 'package:flutter/foundation.dart';

/// An accreditation's issue or expiry date, as the school enters it: a
/// year (`2024`), a month (`2024-03`) or a day (`2024-03-05`). Shown as
/// entered, never turned into a status such as "valid" or "expired".
@immutable
class AccreditationDate {
  const AccreditationDate(this.year, [this.month, this.day]);

  final int year;
  final int? month;
  final int? day;

  static final _pattern = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$');

  /// [value] as a date, or null when it isn't one of the three forms (or
  /// names no real day).
  static AccreditationDate? tryParse(String value) {
    final m = _pattern.firstMatch(value.trim());
    if (m == null) return null;
    final year = int.parse(m[1]!);
    final month = m[2] == null ? null : int.parse(m[2]!);
    final day = m[3] == null ? null : int.parse(m[3]!);
    if (year < 1900 || year > 2200 || (month != null && (month < 1 || month > 12))) return null;
    if (day != null) {
      final date = DateTime.utc(year, month!, day);
      if (date.month != month || date.day != day) return null;
    }
    return AccreditationDate(year, month, day);
  }

  /// The first and last day this date covers (`2024` is 1 January to
  /// 31 December 2024).
  DateTime get first => DateTime.utc(year, month ?? 1, day ?? 1);
  DateTime get last => day != null ? first : DateTime.utc(year, (month ?? 12) + 1, 0);

  /// This date with [monthName] (1–12, in the visitor's language).
  String format(String Function(int month) monthName) => switch ((month, day)) {
        (null, _) => '$year',
        (final m?, null) => '${monthName(m)} $year',
        (final m?, final d?) => '$d ${monthName(m)} $year',
      };
}
