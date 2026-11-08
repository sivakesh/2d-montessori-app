import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// A student's Admission Date (`students.admissionDate`): optional, a
/// Firestore Timestamp holding the chosen local calendar date (midnight).
/// Never defaulted or inferred: older records without one read as null and
/// show [notRecorded].
abstract final class AdmissionDate {
  static const notRecorded = 'Admission date not recorded';

  /// The earliest and latest dates the picker offers and saves accept.
  static final first = DateTime(1990), last = DateTime(2100, 12, 31);

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The stored value as a calendar date, or null (missing or not a date).
  static DateTime? parse(Object? value) => value is Timestamp
      ? dateOnly(value.toDate())
      : value is DateTime
          ? dateOnly(value)
          : null;

  /// "15 Aug 2026", or [notRecorded].
  static String label(DateTime? d) => d == null ? notRecorded : DateFormat('d MMM yyyy').format(d);

  /// Why [d] can't be saved, or null.
  static String? error(DateTime? d) =>
      d != null && (d.isBefore(first) || d.isAfter(last)) ? 'Admission date must be a date from 1990 to 2100.' : null;
}
