import 'fee_discount.dart';
import 'fee_month.dart';
import 'fee_structure_model.dart';
import 'student_fee_assignment_model.dart';

/// Fees → Apply Student Discounts to Existing Fees.
///
/// Every live assignment of a student who has a discount configuration is
/// classified ([FeeDiscountApply.classify]) into one category; only
/// [FeeDiscountApplyCategory.eligible] ones are changed, and only after the
/// administrator confirms. Collected amounts, receipts, transactions and
/// Finance are never touched: the discount reduces what is still payable.

enum FeeDiscountApplyCategory {
  eligible('Eligible'),
  fullyPaid('Fully paid (excluded)'),
  outsideDates('Not applicable: outside the effective dates or inactive'),
  alreadyProcessed('Already has a student discount'),
  manualReview('Needs manual review');

  const FeeDiscountApplyCategory(this.label);
  final String label;
}

int _p(double v) => (v * 100).round();
double _r(int p) => p / 100;

class FeeDiscountApplyItem {
  const FeeDiscountApplyItem({
    required this.assignment,
    required this.category,
    required this.reason,
    this.config,
    this.period,
    this.calculation,
  });

  final StudentFeeAssignmentModel assignment;
  final FeeDiscountApplyCategory category;
  final String reason;

  /// The student's configuration when classified.
  final StudentFeeDiscount? config;
  final FeeDiscountPeriod? period;

  /// Eligible: the discount to add.
  final FeeDiscountCalculation? calculation;

  double get gross => assignment.totalFee;
  double get existingDiscount => assignment.discountAmount;
  double get collected => assignment.paidAmount;
  double get outstanding => assignment.balanceAmount;

  /// The additional discount (0 unless eligible).
  double get proposed => calculation?.discount ?? 0;
  double get revisedPayable => _r(_p(assignment.payableAmount) - _p(proposed));
  double get revisedOutstanding => _r(_p(outstanding) - _p(proposed));

  /// Status after the change: paid when nothing is left outstanding.
  String get revisedStatus => _p(revisedOutstanding) <= 0
      ? 'paid'
      : _p(collected) > 0
          ? 'partial'
          : 'unpaid';

  String get periodLabel {
    final month = FeeMonth.label(assignment.feeMonth);
    if (month.isNotEmpty) return month;
    if (period case final p?) return p.label;
    return 'Period not recorded';
  }

  FeeDiscountApplyItem withReason(String r) =>
      FeeDiscountApplyItem(assignment: assignment, category: category, reason: r, config: config, period: period, calculation: calculation);
}

class FeeDiscountApplyPreview {
  FeeDiscountApplyPreview(this.items);

  /// Every assignment of a student with a discount configuration, sorted by
  /// student name.
  final List<FeeDiscountApplyItem> items;

  List<FeeDiscountApplyItem> of(FeeDiscountApplyCategory c) => [for (final i in items) if (i.category == c) i];
  int count(FeeDiscountApplyCategory c) => items.where((i) => i.category == c).length;
  List<FeeDiscountApplyItem> get eligible => of(FeeDiscountApplyCategory.eligible);

  double gross(FeeDiscountApplyCategory c) => _sum(c, (i) => i.gross);
  double outstanding(FeeDiscountApplyCategory c) => _sum(c, (i) => i.outstanding);
  double get totalProposed => _sum(FeeDiscountApplyCategory.eligible, (i) => i.proposed);
  double _sum(FeeDiscountApplyCategory c, double Function(FeeDiscountApplyItem) f) => _r(of(c).fold(0, (s, i) => s + _p(f(i))));
}

class FeeDiscountApplyResult {
  const FeeDiscountApplyResult({
    required this.operationId,
    required this.applied,
    required this.skipped,
    required this.failed,
    this.errors = const [],
  });

  /// Recorded on every assignment this run changed.
  final String operationId;
  final List<FeeDiscountApplyItem> applied;

  /// Changed since the preview (re-checked and not written), with why.
  final List<FeeDiscountApplyItem> skipped;

  /// In a transaction that failed: nothing written for them.
  final List<FeeDiscountApplyItem> failed;
  final List<String> errors;

  double get totalApplied => _r(applied.fold(0, (s, i) => s + _p(i.proposed)));

  String get message => 'Applied the student discount to ${applied.length} ${applied.length == 1 ? 'assignment' : 'assignments'}, '
      'skipped ${skipped.length} (changed since the preview), failed ${failed.length}.';
}

abstract final class FeeDiscountApply {
  /// Classifies [a] for [student] (the student's record; null when it
  /// can't be found) and [structure] (its fee structure, null when it
  /// can't be found). Checks, in order:
  /// 1. already has a student discount: never applied twice;
  /// 2. fully paid: excluded;
  /// 3. the student's configuration: missing or invalid (manual review),
  ///    inactive (not applicable);
  /// 4. the fee period: the fee month, or (Term, One-time, mixed) the
  ///    assignment date `assignedAt`. A Monthly structure's assignment with
  ///    no month, an unknown structure or no assignment date: manual review
  ///    (never inferred);
  /// 5. the effective dates: not applicable;
  /// 6. figures that don't reconcile (payable ≠ fee − discount, or
  ///    collected + outstanding ≠ payable): manual review;
  /// 7. a manual discount already recorded: manual review (not combined);
  /// 8. a discount larger than the outstanding amount (collected would
  ///    exceed the revised payable; no refund or credit is created):
  ///    manual review;
  /// 9. otherwise eligible.
  static FeeDiscountApplyItem classify(StudentFeeAssignmentModel a, Map<String, dynamic>? student, FeeStructureModel? structure) {
    FeeDiscountApplyItem item(FeeDiscountApplyCategory c, String reason, {StudentFeeDiscount? config, FeeDiscountPeriod? period, FeeDiscountCalculation? calc}) =>
        FeeDiscountApplyItem(assignment: a, category: c, reason: reason, config: config, period: period, calculation: calc);
    const review = FeeDiscountApplyCategory.manualReview;

    if (a.studentDiscount case final s?) {
      return item(FeeDiscountApplyCategory.alreadyProcessed, 'Already has the student discount ${s.label}; it is never applied twice.');
    }
    if (_p(a.balanceAmount) <= 0 && _p(a.totalFee) > 0) {
      return item(FeeDiscountApplyCategory.fullyPaid, 'Fully paid: collected amounts are never changed.');
    }
    if (student == null) return item(review, 'The student record was not found.');
    final config = StudentFeeDiscount.fromStudent(student);
    if (config == null) return item(review, 'The student no longer has a discount configuration.');
    if (!config.isValid) return item(review, 'The student discount configuration is invalid: ${config.error}', config: config);
    if (!config.isActive) return item(FeeDiscountApplyCategory.outsideDates, 'The student discount is inactive.', config: config);
    if (_p(a.totalFee) <= 0) return item(review, 'The assignment has no fee amount recorded.', config: config);

    final FeeDiscountPeriod period;
    if (FeeMonth.isValid(a.feeMonth)) {
      period = FeeDiscountPeriod.month(a.feeMonth);
    } else if (a.feeMonth.isNotEmpty) {
      return item(review, 'The fee month "${a.feeMonth}" is not a month.', config: config);
    } else if (structure == null) {
      return item(review, 'Its fee structure was not found, so its fee period is unknown.', config: config);
    } else if (FeeMonth.isMonthlyStructure(structure)) {
      return item(review, 'A monthly fee with no fee month recorded: set its month first.', config: config);
    } else if (a.assignedAt == null) {
      return item(review, 'No assignment date is recorded, so its fee period is unknown.', config: config);
    } else {
      period = FeeDiscountPeriod.date(a.assignedAt!);
    }
    if (config.notApplicableReason(period) case final why?) return item(FeeDiscountApplyCategory.outsideDates, why, config: config, period: period);

    if (_p(a.payableAmount) != _p(a.totalFee) - _p(a.discountAmount) || _p(a.paidAmount) + _p(a.balanceAmount) != _p(a.payableAmount)) {
      return item(review, 'Its recorded figures do not reconcile (payable, collected and outstanding); check it first.', config: config, period: period);
    }
    if (_p(a.discountAmount) > 0) {
      return item(review, 'It already has an assignment-specific discount of ${_money(a.discountAmount)}; the student discount is not combined with it.',
          config: config, period: period);
    }
    final calc = FeeDiscountCalculator.calculate(config, a.totalFee, structure?.components ?? const []);
    if (_p(calc.discount) <= 0) return item(FeeDiscountApplyCategory.outsideDates, 'The discount works out to nothing on this fee.', config: config, period: period);
    if (_p(calc.discount) > _p(a.balanceAmount)) {
      return item(
        review,
        'The discount ${_money(calc.discount)} is more than the outstanding ${_money(a.balanceAmount)}: '
        '${_money(a.paidAmount)} already collected would exceed the revised payable ${_money(_r(_p(a.payableAmount) - _p(calc.discount)))}. '
        'No refund or credit is created automatically.',
        config: config,
        period: period,
      );
    }
    return item(FeeDiscountApplyCategory.eligible, 'Eligible: ${config.valueLabel} for ${period.label}.', config: config, period: period, calc: calc);
  }

  static String _money(double v) => '₹${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';
}
