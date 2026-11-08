import 'package:flutter/foundation.dart';

import 'fee_collection_record.dart';
import 'student_fee_assignment_model.dart';

/// One student's fee account for a period (one academic year, or all):
/// their assignments, each with its own payments, the totals, and a
/// timeline. Built read-only from data already stored; nothing is
/// recalculated into the records or written back.
///
/// Calculation rules (each figure is a sum over the assignments shown):
/// - Total assigned: each assignment's original fee (`totalFee`).
/// - Total discounts: each assignment's `discountAmount`.
/// - Net payable: each assignment's `payableAmount`.
/// - Total collected: each assignment's recorded `paidAmount` (Collect adds
///   to it, Void takes the voided amount back off), so a voided payment
///   is never in it, and each payment counts once, against its own
///   assignment.
/// - Outstanding: each assignment's recorded `balanceAmount`, as in Dues.
/// - [completedPaymentsTotal]: the completed (not voided) payments listed,
///   each receipt once. When it differs from Total collected, the view
///   says so instead of changing either figure.
/// Monthly assignments stay separate: each month is its own assignment
/// with its own figures and payments.
@immutable
class StudentFeeHistory {
  const StudentFeeHistory._(this.assignments, this.paymentsByAssignment, this.unlinked);

  /// [assignments]: the student's assignments for the period (oldest
  /// first is applied here). [records]: payments for those assignments;
  /// any for another assignment are ignored, and a receipt seen twice
  /// counts once. [unlinked]: the student's payments with no assignment to
  /// go by — listed apart, never counted.
  factory StudentFeeHistory.of(
    Iterable<StudentFeeAssignmentModel> assignments,
    Iterable<FeeCollectionRecord> records, {
    Iterable<FeeCollectionRecord> unlinked = const [],
  }) {
    final list = assignments.toList()
      ..sort((a, b) {
        final da = a.assignedAt, db = b.assignedAt;
        if (da == null || db == null) return da == null ? (db == null ? 0 : 1) : -1;
        return da.compareTo(db);
      });
    final byId = {for (final a in list) a.id: <FeeCollectionRecord>[]};
    final seen = <String>{};
    for (final r in records) {
      final bucket = byId[r.receipt.assignmentId];
      if (bucket != null && seen.add(r.receipt.id)) bucket.add(r);
    }
    return StudentFeeHistory._(
      List.unmodifiable(list),
      {for (final e in byId.entries) e.key: List.unmodifiable(e.value)},
      List.unmodifiable([for (final r in unlinked) if (seen.add(r.receipt.id)) r]),
    );
  }

  final List<StudentFeeAssignmentModel> assignments;
  final Map<String, List<FeeCollectionRecord>> paymentsByAssignment;
  final List<FeeCollectionRecord> unlinked;

  double _sum(double Function(StudentFeeAssignmentModel a) f) => assignments.fold(0, (s, a) => s + f(a));

  double get totalAssigned => _sum((a) => a.totalFee);
  double get totalDiscounts => _sum((a) => a.discountAmount);

  /// The student-discount part of [totalDiscounts].
  double get totalStudentDiscounts => _sum((a) => a.studentDiscountAmount);
  double get netPayable => _sum((a) => a.payableAmount);
  double get totalCollected => _sum((a) => a.paidAmount);
  double get outstanding => _sum((a) => a.balanceAmount);

  Iterable<FeeCollectionRecord> get _allPayments => paymentsByAssignment.values.expand((p) => p);
  double get completedPaymentsTotal => _allPayments.where((r) => r.counts).fold(0, (s, r) => s + r.receipt.amount);
  int get paymentCount => _allPayments.length;
  int get cancelledCount => _allPayments.where((r) => r.isVoided).length;

  /// Whether the listed completed payments add up to Total collected (to
  /// the paisa).
  bool get paymentsMatchCollected => (completedPaymentsTotal * 100).round() == (totalCollected * 100).round();

  /// Every assignment, payment and void, in date order (oldest first); the
  /// events with no recorded date come last, in their own order. A payment
  /// is dated by its payment date and a void by its void date, never by
  /// any other date. Completed payments that left a balance on their
  /// assignment are partial payments.
  List<FeeTimelineEvent> get timeline {
    final events = <FeeTimelineEvent>[];
    for (final a in assignments) {
      events.add(FeeTimelineEvent(FeeTimelineKind.assigned, a.assignedAt, a));
      var paid = 0.0;
      final payments = [...paymentsByAssignment[a.id]!];
      for (final r in payments) {
        if (r.isVoided) {
          events.add(FeeTimelineEvent(FeeTimelineKind.cancelledPayment, r.receipt.paymentDate, a, r));
          events.add(FeeTimelineEvent(FeeTimelineKind.voided, r.voidedAt, a, r));
        } else {
          paid += r.receipt.amount;
          final partial = ((a.payableAmount - paid) * 100).round() > 0;
          events.add(FeeTimelineEvent(partial ? FeeTimelineKind.partialPayment : FeeTimelineKind.payment, r.receipt.paymentDate, a, r));
        }
      }
    }
    final dated = events.where((e) => e.date != null).toList();
    final undated = events.where((e) => e.date == null).toList();
    // A stable sort: same-day events keep their order (assigned, then its
    // payments in order, then voids).
    final order = {for (var i = 0; i < dated.length; i++) dated[i]: i};
    dated.sort((x, y) {
      final byDate = x.date!.compareTo(y.date!);
      return byDate != 0 ? byDate : order[x]!.compareTo(order[y]!);
    });
    return [...dated, ...undated];
  }
}

enum FeeTimelineKind { assigned, payment, partialPayment, cancelledPayment, voided }

@immutable
class FeeTimelineEvent {
  const FeeTimelineEvent(this.kind, this.date, this.assignment, [this.record]);

  final FeeTimelineKind kind;

  /// The event's own recorded date; null when none was recorded.
  final DateTime? date;
  final StudentFeeAssignmentModel assignment;
  final FeeCollectionRecord? record;

  String get title => switch (kind) {
        FeeTimelineKind.assigned => 'Fee assigned',
        FeeTimelineKind.payment => 'Payment (paid in full)',
        FeeTimelineKind.partialPayment => 'Partial payment',
        FeeTimelineKind.cancelledPayment => 'Payment, later voided',
        FeeTimelineKind.voided => 'Payment voided',
      };
}
