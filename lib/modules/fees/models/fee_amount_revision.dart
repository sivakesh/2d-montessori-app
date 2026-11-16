import 'package:cloud_firestore/cloud_firestore.dart';

import 'fee_component_model.dart';
import 'fee_discount.dart';
import 'student_fee_assignment_model.dart';

/// Revising the fee amount of an existing assignment (FeeService
/// .reviseAssignmentFee), whatever has been collected against it.
///
/// Rules:
/// - The assignment's own saved amounts are authoritative: editing a fee
///   structure never changes an existing assignment; an administrator
///   revises one explicitly, starting from its saved amount or the
///   structure's current amount, and the result is saved on the assignment.
/// - Collected (`paidAmount`, kept by every collection, edit and void
///   together with its receipt) is never changed, and no receipt, fee
///   transaction or Finance entry is read or written.
/// - Payable = revised gross − discount; outstanding = payable − collected,
///   never below 0; status paid (nothing outstanding), partial (something
///   collected) or unpaid, as everywhere in FeeService.
/// - Collected above the revised payable is the excess: shown as a credit
///   held, never refunded, reduced or moved automatically (there is no
///   credit or refund model; the school settles it outside the app).
/// - A student discount is recalculated from its own snapshot terms on the
///   revised gross (a percentage follows the gross; a fixed amount stays,
///   capped at the gross); never re-read from the student, never applied
///   twice, never combined with a manual discount. Otherwise the manual
///   discount is kept unless a new one is given.
/// - Amounts are compared and calculated in paise.
abstract final class FeeRevision {
  static int paise(double v) => (v * 100).round();
  static double rupees(int p) => p / 100;

  /// Stored on the assignment: the revision counter (0 or absent: never
  /// revised) and the history, newest last.
  static const revisionField = 'feeRevision';
  static const historyField = 'feeRevisions';

  static const maxAmount = 100000000.0;

  /// Where the revised gross came from.
  static const fromStructure = 'structure';
  static const entered = 'manual';

  /// The figures [a] would have with gross [totalFee] and (no student
  /// discount) manual discount [manualDiscount] (null: its current one).
  /// [components]: its fee structure's, to allocate a student discount.
  static FeeRevisionFigures figures(
    StudentFeeAssignmentModel a, {
    required double totalFee,
    double? manualDiscount,
    List<FeeComponentModel> components = const [],
  }) {
    // Not a number (or too large to be one): 0, with its error.
    final grossP = totalFee.isFinite && totalFee <= maxAmount ? paise(totalFee) : 0;
    final collectedP = paise(a.paidAmount);
    String? error;
    if (!totalFee.isFinite || grossP <= 0) error = 'Enter a fee amount greater than 0.';
    if (totalFee > maxAmount) error = 'The fee amount is too large.';

    FeeDiscountSnapshot? snapshot;
    var studentP = 0, manualP = 0;
    if (a.studentDiscount case final s?) {
      if (manualDiscount != null && paise(manualDiscount) != 0) {
        error ??= 'This assignment has the student discount ${s.label}; it is not combined with a manual discount.';
      }
      if (error == null) {
        snapshot = s.recalculatedFor(totalFee, components);
        studentP = paise(snapshot.amount);
      }
    } else {
      final m = manualDiscount ?? a.manualDiscountAmount;
      manualP = m.isFinite && m.abs() <= maxAmount ? paise(m) : 0;
      if (!m.isFinite) {
        error ??= 'Enter the discount as a number (0 or more).';
      } else if (manualP < 0) {
        error ??= 'The discount cannot be negative.';
      }
      if (error == null && manualP > grossP) error = 'The discount cannot be more than the fee amount.';
    }
    final discountP = studentP + manualP;
    final payableP = grossP - discountP;
    final outstandingP = payableP - collectedP;
    return FeeRevisionFigures(
      totalFee: rupees(grossP),
      studentDiscount: rupees(studentP),
      manualDiscount: rupees(manualP),
      discount: rupees(discountP),
      payable: rupees(payableP),
      collected: rupees(collectedP),
      outstanding: rupees(outstandingP < 0 ? 0 : outstandingP),
      excess: rupees(outstandingP < 0 ? -outstandingP : 0),
      status: outstandingP <= 0
          ? 'paid'
          : collectedP > 0
              ? 'partial'
              : 'unpaid',
      snapshot: snapshot,
      error: error,
    );
  }

  /// Whether [f] differs from [a]'s saved gross or discount.
  static bool changes(StudentFeeAssignmentModel a, FeeRevisionFigures f) =>
      paise(f.totalFee) != paise(a.totalFee) || paise(f.discount) != paise(a.discountAmount);

  static const concurrentMessage =
      'This assignment was changed since you opened it (by a collection, an edit or another revision), so the revision was not saved. '
      'Close this, open it again and review the figures.';
}

/// An assignment's figures for a revised gross (FeeRevision.figures).
class FeeRevisionFigures {
  const FeeRevisionFigures({
    required this.totalFee,
    required this.studentDiscount,
    required this.manualDiscount,
    required this.discount,
    required this.payable,
    required this.collected,
    required this.outstanding,
    required this.excess,
    required this.status,
    this.snapshot,
    this.error,
  });

  final double totalFee, studentDiscount, manualDiscount, discount, payable, collected, outstanding, excess;
  final String status;

  /// The recalculated student discount, if it has one.
  final FeeDiscountSnapshot? snapshot;

  /// Why these figures can't be saved, or null.
  final String? error;
}

/// One revision of an assignment's fee amount: its audit record, kept on the
/// assignment (`feeRevisions`, newest last), written in the same
/// transaction as the amounts it changed.
class FeeAmountRevision {
  const FeeAmountRevision({
    required this.revision,
    required this.previousTotalFee,
    required this.newTotalFee,
    required this.previousDiscount,
    required this.newDiscount,
    required this.previousPayable,
    required this.newPayable,
    required this.collected,
    required this.previousStatus,
    required this.newStatus,
    required this.excess,
    required this.source,
    required this.reason,
    required this.revisedBy,
    required this.revisedByName,
    required this.revisedAt,
    this.structureAmount,
  });

  /// 1 for the first revision, then 2, 3 …
  final int revision;
  final double previousTotalFee, newTotalFee, previousDiscount, newDiscount, previousPayable, newPayable;

  /// Collected when it was revised (never changed by it).
  final double collected;
  final String previousStatus, newStatus;

  /// Collected above the new payable (a credit held), or 0.
  final double excess;

  /// FeeRevision.fromStructure or FeeRevision.entered.
  final String source;

  /// The fee structure's amount at the time, when it was the starting point.
  final double? structureAmount;
  final String reason, revisedBy, revisedByName;
  final DateTime? revisedAt;

  Map<String, dynamic> toMap() => {
        'revision': revision,
        'previousTotalFee': previousTotalFee,
        'newTotalFee': newTotalFee,
        'previousDiscount': previousDiscount,
        'newDiscount': newDiscount,
        'previousPayable': previousPayable,
        'newPayable': newPayable,
        'collected': collected,
        'previousStatus': previousStatus,
        'newStatus': newStatus,
        'excess': excess,
        'source': source,
        'structureAmount': ?structureAmount,
        'reason': reason,
        'revisedBy': revisedBy,
        'revisedByName': revisedByName,
        // A client time: a server timestamp can't go inside a list (the
        // assignment's `lastRevisedAt` is the server's).
        'revisedAt': revisedAt,
      };

  static FeeAmountRevision? fromMap(Object? raw) {
    if (raw is! Map) return null;
    double n(Object? v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    final at = raw['revisedAt'];
    return FeeAmountRevision(
      revision: (raw['revision'] as num?)?.toInt() ?? 0,
      previousTotalFee: n(raw['previousTotalFee']),
      newTotalFee: n(raw['newTotalFee']),
      previousDiscount: n(raw['previousDiscount']),
      newDiscount: n(raw['newDiscount']),
      previousPayable: n(raw['previousPayable']),
      newPayable: n(raw['newPayable']),
      collected: n(raw['collected']),
      previousStatus: raw['previousStatus']?.toString() ?? '',
      newStatus: raw['newStatus']?.toString() ?? '',
      excess: n(raw['excess']),
      source: raw['source']?.toString() ?? FeeRevision.entered,
      structureAmount: raw['structureAmount'] is num ? (raw['structureAmount'] as num).toDouble() : null,
      reason: raw['reason']?.toString() ?? '',
      revisedBy: raw['revisedBy']?.toString() ?? '',
      revisedByName: raw['revisedByName']?.toString() ?? '',
      revisedAt: at is Timestamp ? at.toDate() : at is DateTime ? at : null,
    );
  }
}
