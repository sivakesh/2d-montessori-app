import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import 'finance_ledger_entry_model.dart';

/// The period the Finance -> Ledger tab shows: one calendar month, or all
/// time. A month holds every entry whose `transactionDate`, in the device's
/// local time (the same time the Ledger shows), falls on any day from its
/// first to its last, inclusive. This is the same calendar-day placement
/// FinanceService.watchDashboardSummary uses for a period: an entry with no
/// transaction date can't be placed in a month and appears in All time only.
@immutable
class LedgerPeriod {
  const LedgerPeriod.month(int this.year, int this.month) : assert(month >= 1 && month <= 12);
  const LedgerPeriod.allTime()
      : year = null,
        month = null;

  /// The month containing [date].
  factory LedgerPeriod.of(DateTime date) => LedgerPeriod.month(date.year, date.month);

  final int? year;
  final int? month;

  bool get isAllTime => year == null;

  /// The month before or after this one (All time stays All time).
  LedgerPeriod get previous => isAllTime ? this : LedgerPeriod.of(DateTime(year!, month! - 1));
  LedgerPeriod get next => isAllTime ? this : LedgerPeriod.of(DateTime(year!, month! + 1));

  /// First and last day of the month (null for All time).
  DateTime? get firstDay => isAllTime ? null : DateTime(year!, month!);
  DateTime? get lastDay => isAllTime ? null : DateTime(year!, month! + 1, 0);

  /// Whether an entry dated [date] belongs to this period.
  bool contains(DateTime? date) => isAllTime || (date != null && date.year == year && date.month == month);

  /// "November 2026", or "All time".
  String get label => isAllTime ? 'All time' : DateFormat('MMMM yyyy').format(firstDay!);

  @override
  bool operator ==(Object other) => other is LedgerPeriod && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => 'LedgerPeriod($label)';
}

/// Income, expenses and profit/loss of the ledger entries in one
/// [LedgerPeriod], from the existing classification: `entryType` 'income'
/// or 'expense' and the stored `amount`. Cancelled entries (voided income,
/// reversed payments) count in neither total, exactly as in
/// FinanceService.watchDashboardSummary. Each money movement is one ledger
/// entry, so nothing is counted twice. Account opening balances are stored
/// on the accounts, never as ledger entries, so they are not income; the
/// ledger has no transfer entries. Independent of any closing balance.
@immutable
class LedgerPeriodSummary {
  const LedgerPeriodSummary({required this.totalIncome, required this.totalExpenses});

  factory LedgerPeriodSummary.of(Iterable<FinanceLedgerEntryModel> entries, LedgerPeriod period) {
    var income = 0.0;
    var expenses = 0.0;
    for (final e in entries) {
      if (e.status == 'cancelled' || !period.contains(e.transactionDate)) continue;
      if (e.entryType == 'income') {
        income += e.amount;
      } else if (e.entryType == 'expense') {
        expenses += e.amount;
      }
    }
    return LedgerPeriodSummary(totalIncome: income, totalExpenses: expenses);
  }

  final double totalIncome;
  final double totalExpenses;

  /// Total income minus total expenses: positive is a profit (surplus),
  /// negative a loss (deficit).
  double get profitLoss => totalIncome - totalExpenses;

  /// To the paisa, so floating-point noise is never shown as a loss.
  bool get isBreakEven => (profitLoss * 100).round() == 0;
  bool get isProfit => !isBreakEven && profitLoss > 0;
  bool get isLoss => !isBreakEven && profitLoss < 0;
}

/// The non-cancelled ledger entries with no transaction date. They count in
/// current (all-time) balances but can't be placed in a month, so
/// month-end balances leave them out
/// (FinanceService.watchDashboardSummary with a `periodEnd`); this says
/// how many and how much, for the disclosure beside those balances.
@immutable
class UndatedLedgerEntries {
  const UndatedLedgerEntries({required this.count, required this.net});

  factory UndatedLedgerEntries.of(Iterable<FinanceLedgerEntryModel> entries) {
    var count = 0;
    var net = 0.0;
    for (final e in entries) {
      if (e.status == 'cancelled' || e.transactionDate != null) continue;
      count++;
      // The balance rule: income in, anything else out.
      net += e.entryType == 'income' ? e.amount : -e.amount;
    }
    return UndatedLedgerEntries(count: count, net: net);
  }

  final int count;

  /// Their effect on the balances: income minus everything else.
  final double net;
}
