import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'fee_component_model.dart';
import 'fee_month.dart';

/// Student-level global fee discounts (concessions).
///
/// A student has at most one configuration, stored as the map
/// `students.feeDiscount` ([StudentFeeDiscount]); none means no discount
/// (older students are unchanged). When a fee assignment is made, the
/// configuration that applies to its fee period is calculated here
/// ([FeeDiscountCalculator]) and its result stored on the assignment as a
/// snapshot (`student_fee_assignments.studentDiscount`,
/// [FeeDiscountSnapshot]). The snapshot, never the student's current
/// configuration, explains the assignment later.
///
/// Rules:
/// - Percentage: [value]% of the assignment's gross fee (`totalFee`).
/// - Fixed: [value] once per fee period, i.e. once per assignment (a
///   Monthly assignment is one month; a Term, One-time or mixed assignment
///   is one period), never once per component.
/// - Either way the discount is capped at the gross fee, so the net payable
///   is never negative.
/// - Amounts are calculated in paise and rounded half away from zero, the
///   precision FeeService compares amounts at.
/// - Applicable only while active and when the whole fee period lies in the
///   effective dates (both ends included): a Monthly assignment's month from
///   its first to its last day; any other assignment's assignment date.
/// - An assignment receives the student discount at most once: one that
///   already has a snapshot is never discounted again.
/// - An assignment with a manual (assignment-specific) discount is never
///   combined with the student discount: it is flagged for manual review.

enum FeeDiscountType {
  percentage('percentage', 'Percentage'),
  fixed('fixed', 'Fixed amount');

  const FeeDiscountType(this.key, this.label);
  final String key, label;

  static FeeDiscountType? parse(Object? v) => switch (v?.toString()) {
        'percentage' => percentage,
        'fixed' => fixed,
        _ => null,
      };
}

int _paise(double v) => (v * 100).round();
double _rupees(int p) => p / 100;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime? _date(Object? v) => v is Timestamp
    ? _dateOnly(v.toDate())
    : v is DateTime
        ? _dateOnly(v)
        : null;

String _dateLabel(DateTime d) => DateFormat('d MMM yyyy').format(d);

String _money(double v) {
  final whole = _paise(v) % 100 == 0;
  return '₹${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: whole ? 0 : 2).format(v)}';
}

/// The fee period an assignment is for: a Monthly assignment's month, or
/// (Term, One-time, mixed) the assignment date.
class FeeDiscountPeriod {
  FeeDiscountPeriod.month(this.feeMonth)
      : assert(FeeMonth.isValid(feeMonth)),
        start = DateTime(int.parse(feeMonth.substring(0, 4)), int.parse(feeMonth.substring(5))),
        end = DateTime(int.parse(feeMonth.substring(0, 4)), int.parse(feeMonth.substring(5)) + 1, 0);

  FeeDiscountPeriod.date(DateTime date)
      : feeMonth = '',
        start = _dateOnly(date),
        end = _dateOnly(date);

  /// `YYYY-MM`, or '' for a date period.
  final String feeMonth;
  final DateTime start, end;

  bool get isMonth => feeMonth.isNotEmpty;

  /// Stored on the snapshot: `month:2027-01` or `date:2026-08-20`.
  String get reference => isMonth ? 'month:$feeMonth' : 'date:${DateFormat('yyyy-MM-dd').format(start)}';

  String get label => isMonth ? FeeMonth.label(feeMonth) : 'assignment date ${_dateLabel(start)}';
}

/// A student's discount configuration (`students.feeDiscount`).
class StudentFeeDiscount {
  const StudentFeeDiscount({
    required this.id,
    required this.type,
    required this.value,
    required this.effectiveFrom,
    this.effectiveUntil,
    this.reason = '',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Identifies this configuration's terms; a new id is given whenever the
  /// type, value or dates change (snapshots record which terms they used).
  final String id;

  /// null when the stored type isn't recognised (never applicable).
  final FeeDiscountType? type;
  final double value;

  /// Calendar dates (local midnight). [effectiveFrom] null only for an
  /// invalid stored record (never applicable).
  final DateTime? effectiveFrom, effectiveUntil;
  final String reason;
  final bool isActive;
  final DateTime? createdAt, updatedAt;

  static const field = 'feeDiscount';

  /// The configuration stored in a student's data, or null when none.
  static StudentFeeDiscount? fromStudent(Map<String, dynamic>? student) => fromMap(student?[field]);

  static StudentFeeDiscount? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final v = m['value'];
    DateTime? ts(Object? x) => x is Timestamp ? x.toDate() : x is DateTime ? x : null;
    return StudentFeeDiscount(
      id: m['id']?.toString() ?? '',
      type: FeeDiscountType.parse(m['type']),
      value: v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? double.nan,
      effectiveFrom: _date(m['effectiveFrom']),
      effectiveUntil: _date(m['effectiveUntil']),
      reason: m['reason']?.toString() ?? '',
      isActive: m['isActive'] == true,
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }

  /// Without createdAt/updatedAt (the service sets those).
  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type?.key,
        'value': value,
        'effectiveFrom': effectiveFrom == null ? null : Timestamp.fromDate(_dateOnly(effectiveFrom!)),
        'effectiveUntil': effectiveUntil == null ? null : Timestamp.fromDate(_dateOnly(effectiveUntil!)),
        'reason': reason.trim(),
        'isActive': isActive,
      };

  static final firstDate = DateTime(2000), lastDate = DateTime(2100, 12, 31);

  /// Why these terms can't be saved, or null.
  static String? validate({required FeeDiscountType? type, required double? value, required DateTime? effectiveFrom, DateTime? effectiveUntil}) {
    if (type == null) return 'Choose the discount type (percentage or fixed amount).';
    if (value == null || !value.isFinite) return 'Enter the discount value as a number.';
    if (value <= 0) return 'The discount value must be greater than 0.';
    if (type == FeeDiscountType.percentage && value > 100) return 'A percentage discount cannot be more than 100%.';
    if (_paise(value) <= 0) return 'The discount value must be at least 0.01.';
    if (effectiveFrom == null) return 'Choose the date the discount is effective from.';
    bool outside(DateTime d) => d.isBefore(firstDate) || d.isAfter(lastDate);
    if (outside(effectiveFrom)) return 'Effective From must be a date from 2000 to 2100.';
    if (effectiveUntil != null) {
      if (outside(effectiveUntil)) return 'Effective Until must be a date from 2000 to 2100.';
      if (_dateOnly(effectiveUntil).isBefore(_dateOnly(effectiveFrom))) return 'Effective Until cannot be earlier than Effective From.';
    }
    return null;
  }

  String? get error => validate(type: type, value: value, effectiveFrom: effectiveFrom, effectiveUntil: effectiveUntil);
  bool get isValid => error == null;

  /// Whether the same discount terms (not the reason or active state).
  bool sameTerms(StudentFeeDiscount o) =>
      type == o.type && _paise(value) == _paise(o.value) && effectiveFrom == o.effectiveFrom && effectiveUntil == o.effectiveUntil;

  /// Applies to [period]: active, valid, and the whole period within the
  /// effective dates.
  bool appliesTo(FeeDiscountPeriod period) => notApplicableReason(period) == null;

  /// Why it doesn't apply to [period], or null when it does.
  String? notApplicableReason(FeeDiscountPeriod period) {
    if (!isValid) return 'The student discount configuration is invalid (${error!}).';
    if (!isActive) return 'The student discount is inactive.';
    if (period.start.isBefore(effectiveFrom!)) return '${_cap(period.label)} is before the discount is effective (from ${_dateLabel(effectiveFrom!)}).';
    if (effectiveUntil != null && period.end.isAfter(effectiveUntil!)) {
      return '${_cap(period.label)} is after the discount ends (until ${_dateLabel(effectiveUntil!)}).';
    }
    return null;
  }

  /// "10%" or "₹500 per fee period".
  String get valueLabel => switch (type) {
        FeeDiscountType.percentage => '${_num(value)}%',
        FeeDiscountType.fixed => '${_money(value)} per fee period',
        null => 'Invalid',
      };

  String get datesLabel => effectiveFrom == null
      ? 'No effective date'
      : effectiveUntil == null
          ? 'From ${_dateLabel(effectiveFrom!)} (no end date)'
          : '${_dateLabel(effectiveFrom!)} – ${_dateLabel(effectiveUntil!)}';

  /// "10% · From 1 Jan 2027 (no end date) · Active".
  String get summary => '$valueLabel · $datesLabel · ${isActive ? 'Active' : 'Inactive'}';

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const noneLabel = 'No student fee discount';
}

/// One component's share of an assignment's student discount.
class FeeDiscountAllocation {
  const FeeDiscountAllocation({required this.name, required this.gross, required this.discount});
  final String name;
  final double gross, discount;

  Map<String, dynamic> toMap() => {'name': name, 'gross': gross, 'discount': discount};

  static FeeDiscountAllocation fromMap(Map m) => FeeDiscountAllocation(
        name: m['name']?.toString() ?? '',
        gross: (m['gross'] as num?)?.toDouble() ?? 0,
        discount: (m['discount'] as num?)?.toDouble() ?? 0,
      );
}

class FeeDiscountCalculation {
  const FeeDiscountCalculation({required this.gross, required this.discount, required this.allocation});
  final double gross, discount;
  double get net => _rupees(_paise(gross) - _paise(discount));

  /// Per component; the shares add up exactly to [discount].
  final List<FeeDiscountAllocation> allocation;
}

abstract final class FeeDiscountCalculator {
  /// The label of the single allocation line used when the components can't
  /// be matched to the gross fee.
  static const wholeFee = 'Whole fee';

  /// The discount [d] gives on [gross] (the assignment's `totalFee`),
  /// allocated over [components] (the fee structure's). [d] must be valid.
  static FeeDiscountCalculation calculate(StudentFeeDiscount d, double gross, List<FeeComponentModel> components) {
    assert(d.isValid);
    final grossP = _paise(gross);
    if (grossP <= 0) return FeeDiscountCalculation(gross: gross, discount: 0, allocation: const []);
    final discountP = switch (d.type!) {
      // Multiply first: exact for whole and half percentages.
      FeeDiscountType.percentage => (grossP * d.value / 100).round(),
      FeeDiscountType.fixed => _paise(d.value),
    }
        .clamp(0, grossP);
    return FeeDiscountCalculation(gross: gross, discount: _rupees(discountP), allocation: allocate(discountP, grossP, components));
  }

  /// Allocation policy: proportional to each component's amount, in paise.
  /// Each component first gets the whole paise of its exact share; the
  /// paise left over (fewer than the number of components) go one each to
  /// the components with the largest remaining fractions, ties to the
  /// earlier component. No component gets more than its own amount, and
  /// the shares add up exactly to [discountP].
  ///
  /// When the components (amounts above zero) don't add up to the gross fee
  /// (an assignment whose fee differs from its structure's components), the
  /// discount is recorded as one [wholeFee] line instead of guessing.
  static List<FeeDiscountAllocation> allocate(int discountP, int grossP, List<FeeComponentModel> components) {
    final parts = [for (final c in components) if (_paise(c.amount) > 0) (c.name.trim().isEmpty ? 'Component' : c.name.trim(), _paise(c.amount))];
    if (parts.isEmpty || parts.fold(0, (s, p) => s + p.$2) != grossP) {
      return [FeeDiscountAllocation(name: wholeFee, gross: _rupees(grossP), discount: _rupees(discountP))];
    }
    final shares = <int>[];
    final remainders = <(int, int)>[]; // (remainder numerator, index)
    for (final (i, (_, amount)) in parts.indexed) {
      final exact = discountP * amount; // share = exact / grossP
      shares.add(exact ~/ grossP);
      remainders.add((exact % grossP, i));
    }
    var left = discountP - shares.fold(0, (s, v) => s + v);
    remainders.sort((a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2));
    for (final (_, i) in remainders) {
      if (left == 0) break;
      shares[i]++;
      left--;
    }
    return [
      for (final (i, (name, amount)) in parts.indexed) FeeDiscountAllocation(name: name, gross: _rupees(amount), discount: _rupees(shares[i])),
    ];
  }
}

/// How an assignment's student discount was applied.
enum FeeDiscountSource {
  /// When the assignment was created.
  assignment('assignment'),

  /// Afterwards, by Apply Student Discounts to Existing Fees.
  existing('existing');

  const FeeDiscountSource(this.key);
  final String key;
}

/// The student discount recorded on an assignment
/// (`student_fee_assignments.studentDiscount`): the terms used, the period,
/// the amount and its allocation, and when, by whom and how it was applied.
/// For an existing assignment it also keeps the figures before the change
/// (its audit record).
class FeeDiscountSnapshot {
  const FeeDiscountSnapshot({
    required this.configId,
    required this.type,
    required this.value,
    required this.effectiveFrom,
    this.effectiveUntil,
    this.reason = '',
    required this.periodReference,
    required this.gross,
    required this.amount,
    required this.allocation,
    required this.source,
    this.appliedAt,
    this.appliedBy = '',
    this.operationId = '',
    this.previous,
  });

  static const field = 'studentDiscount';

  final String configId;
  final FeeDiscountType? type;
  final double value;
  final DateTime? effectiveFrom, effectiveUntil;
  final String reason;
  final String periodReference;
  final double gross, amount;
  final List<FeeDiscountAllocation> allocation;
  final FeeDiscountSource source;
  final DateTime? appliedAt;
  final String appliedBy;

  /// Apply to Existing Fees: the run's id.
  final String operationId;

  /// Apply to Existing Fees: `discountAmount`, `payableAmount`, `paidAmount`,
  /// `balanceAmount` and `status` before the change.
  final Map<String, dynamic>? previous;

  /// The snapshot for [d]'s [calc] on [period]. `appliedAt` is written as a
  /// server timestamp by [toMap].
  static FeeDiscountSnapshot of(
    StudentFeeDiscount d,
    FeeDiscountCalculation calc,
    FeeDiscountPeriod period, {
    required FeeDiscountSource source,
    String appliedBy = '',
    String operationId = '',
    Map<String, dynamic>? previous,
  }) =>
      FeeDiscountSnapshot(
        configId: d.id,
        type: d.type,
        value: d.value,
        effectiveFrom: d.effectiveFrom,
        effectiveUntil: d.effectiveUntil,
        reason: d.reason,
        periodReference: period.reference,
        gross: calc.gross,
        amount: calc.discount,
        allocation: calc.allocation,
        source: source,
        appliedBy: appliedBy,
        operationId: operationId,
        previous: previous,
      );

  static FeeDiscountSnapshot? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final applied = m['appliedAt'];
    return FeeDiscountSnapshot(
      configId: m['configId']?.toString() ?? '',
      type: FeeDiscountType.parse(m['type']),
      value: (m['value'] as num?)?.toDouble() ?? 0,
      effectiveFrom: _date(m['effectiveFrom']),
      effectiveUntil: _date(m['effectiveUntil']),
      reason: m['reason']?.toString() ?? '',
      periodReference: m['period']?.toString() ?? '',
      gross: (m['gross'] as num?)?.toDouble() ?? 0,
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      allocation: [for (final a in (m['allocation'] as List? ?? const [])) if (a is Map) FeeDiscountAllocation.fromMap(a)],
      source: m['source'] == FeeDiscountSource.existing.key ? FeeDiscountSource.existing : FeeDiscountSource.assignment,
      appliedAt: applied is Timestamp ? applied.toDate() : applied is DateTime ? applied : null,
      appliedBy: m['appliedBy']?.toString() ?? '',
      operationId: m['operationId']?.toString() ?? '',
      previous: m['previous'] is Map ? Map<String, dynamic>.from(m['previous'] as Map) : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'configId': configId,
        'type': type?.key,
        'value': value,
        'effectiveFrom': effectiveFrom == null ? null : Timestamp.fromDate(effectiveFrom!),
        'effectiveUntil': effectiveUntil == null ? null : Timestamp.fromDate(effectiveUntil!),
        'reason': reason,
        'period': periodReference,
        'gross': gross,
        'amount': amount,
        'allocation': [for (final a in allocation) a.toMap()],
        'source': source.key,
        'appliedAt': appliedAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(appliedAt!),
        'appliedBy': appliedBy,
        if (operationId.isNotEmpty) 'operationId': operationId,
        'previous': ?previous,
      };

  /// This snapshot's discount recalculated on a revised gross fee [gross]
  /// (an explicit fee revision, FeeRevision): its own terms, never the
  /// student's current configuration. A percentage follows the gross; a
  /// fixed amount stays, capped at the gross. Allocated over [components]
  /// as when it was applied. Everything else (terms, period, source, when
  /// and by whom it was applied, the earlier figures) is kept.
  FeeDiscountSnapshot recalculatedFor(double gross, List<FeeComponentModel> components) {
    final grossP = _paise(gross);
    final discountP = grossP <= 0
        ? 0
        : switch (type) {
            FeeDiscountType.percentage => (grossP * value / 100).round(),
            FeeDiscountType.fixed => _paise(value),
            // Unrecognised terms: the amount recorded, as it was.
            null => _paise(amount),
          }
            .clamp(0, grossP < 0 ? 0 : grossP);
    return FeeDiscountSnapshot(
      configId: configId,
      type: type,
      value: value,
      effectiveFrom: effectiveFrom,
      effectiveUntil: effectiveUntil,
      reason: reason,
      periodReference: periodReference,
      gross: _rupees(grossP),
      amount: _rupees(discountP),
      allocation: grossP <= 0 ? const [] : FeeDiscountCalculator.allocate(discountP, grossP, components),
      source: source,
      appliedAt: appliedAt,
      appliedBy: appliedBy,
      operationId: operationId,
      previous: previous,
    );
  }

  /// "Student discount 10% (₹500)" / "Student discount ₹500 per fee period (₹500)".
  String get label {
    final terms = switch (type) {
      FeeDiscountType.percentage => '${StudentFeeDiscount._num(value)}%',
      FeeDiscountType.fixed => '${_money(value)} per fee period',
      null => 'discount',
    };
    return '$terms (${_money(amount)})';
  }
}
