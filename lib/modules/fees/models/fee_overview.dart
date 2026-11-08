import 'package:flutter/foundation.dart';

import 'fee_due_date.dart';
import 'fee_list_filter.dart';
import 'fee_receipt_model.dart';
import 'student_fee_assignment_model.dart';

/// The Fees screen's overview cards, computed from the records the screen
/// already holds, for the shared filter. Each metric keeps the definition
/// FeeService.getDashboardSummary uses (with no filter the figures are the
/// same):
///
/// - Total Expected / Collected / Outstanding: the sums of `payableAmount`
///   / `paidAmount` / `balanceAmount` over the assignments matching the
///   filter (academic year, class recorded on the assignment, student).
/// - Collection %: Total Collected / Total Expected, both over that same
///   set of assignments.
/// - Overdue Students: the number of distinct students with at least one
///   of those assignments overdue on [today] (FeeDueDate.isOverdue: an
///   outstanding balance and a due date before today; assignments without
///   a due date are never overdue). The stored `status` is not used.
/// - Today's Collection: active receipts with a payment date of [today],
///   whatever academic year they are for (a date-based figure). Class and
///   student apply through each receipt's linked assignment; with a class
///   chosen, a receipt with no linked assignment has no class and isn't
///   counted, and with only a student chosen it is matched by its own
///   `studentId` (FeeListFilter.matchesReceipt).
@immutable
class FeeOverview {
  const FeeOverview({
    required this.totalExpected,
    required this.totalCollected,
    required this.outstanding,
    required this.overdue,
    required this.todayCollection,
  });

  factory FeeOverview.of({
    required Iterable<StudentFeeAssignmentModel> assignments,
    required Iterable<FeeReceiptModel> receipts,
    required FeeListFilter filter,
    required DateTime today,
  }) {
    final all = assignments.toList();
    final shown = all.where(filter.matchesAssignment).toList();
    double sum(double Function(StudentFeeAssignmentModel a) f) => shown.fold(0, (s, a) => s + f(a));
    final byId = {for (final a in all) a.id: a};
    // Today's Collection ignores the academic year.
    final todayFilter = FeeListFilter(classId: filter.classId, studentId: filter.studentId);
    final todayTotal = receipts
        .where((r) {
          final d = r.paymentDate;
          return d != null && d.year == today.year && d.month == today.month && d.day == today.day && todayFilter.matchesReceipt(r, byId[r.assignmentId]);
        })
        .fold<double>(0, (s, r) => s + r.amount);
    return FeeOverview(
      totalExpected: sum((a) => a.payableAmount),
      totalCollected: sum((a) => a.paidAmount),
      outstanding: sum((a) => a.balanceAmount),
      overdue: FeeDueDate.overdueStudents(shown, today),
      todayCollection: todayTotal,
    );
  }

  final double totalExpected, totalCollected, outstanding, todayCollection;
  final int overdue;

  double get collectionPercent => totalExpected == 0 ? 0 : (totalCollected / totalExpected) * 100;
}
