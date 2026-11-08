import 'package:intl/intl.dart';

import '../../admin/settings/models/academic_year_months.dart';
import 'finance_ledger_entry_model.dart';
import 'ledger_period.dart';

/// Finance Dashboard → Monthly Income and Expenses: each month of the
/// current academic year (through today), from the Finance Ledger entries
/// by their `transactionDate`, with the Ledger's own Profit / Loss
/// calculation (LedgerPeriodSummary: cancelled entries excluded, income and
/// expense by `entryType`). Entries dated before the year's start or after
/// today are left out. No account, opening or closing balance is used.
/// Read-only.
class FinanceMonthlyTotals {
  FinanceMonthlyTotals._(this.window, this.byMonth);

  factory FinanceMonthlyTotals.of(List<FinanceLedgerEntryModel> entries, AcademicYearMonths window) {
    final inWindow = [for (final e in entries) if (window.contains(e.transactionDate)) e];
    return FinanceMonthlyTotals._(window, {
      for (final m in window.months)
        m: LedgerPeriodSummary.of(inWindow, LedgerPeriod.month(AcademicYearMonths.monthStart(m).year, AcademicYearMonths.monthStart(m).month)),
    });
  }

  final AcademicYearMonths window;
  final Map<String, LedgerPeriodSummary> byMonth;

  List<String> get months => window.months;
  double incomeIn(String m) => byMonth[m]?.totalIncome ?? 0;
  double expensesIn(String m) => byMonth[m]?.totalExpenses ?? 0;
  bool get isEmpty => months.every((m) => (incomeIn(m) * 100).round() == 0 && (expensesIn(m) * 100).round() == 0);

  /// For the Ledger drill-down from [month]'s bar: which days the bar
  /// counts and that the Ledger shows the whole calendar month. The bar
  /// stops at today in the current month and starts at the academic year's
  /// first day in its first month; the Ledger's month is always complete,
  /// so the two can differ there. Wording only: no figure changes.
  String drillDownNote(String month) {
    final label = AcademicYearMonths.label(month);
    if (!window.isPartial(month)) return 'The chart bar and the Ledger both cover all of $label.';
    final (from, to) = window.daysOf(month);
    final first = AcademicYearMonths.monthStart(month);
    final startsLate = from != first;
    final endsEarly = to != DateTime(first.year, first.month + 1, 0);
    String d(DateTime x) => DateFormat('d MMM yyyy').format(x);
    final bar = startsLate && endsEarly
        ? 'The chart bar counts ${d(from)} (the academic year’s start) to ${d(to)} (today)'
        : startsLate
            ? 'The chart bar counts from ${d(from)}, when the academic year starts'
            : 'The chart bar counts transactions through today, ${d(to)}';
    return '$bar. The Ledger below shows all of $label, so its totals can be higher'
        '${endsEarly ? ' if entries are dated later this month' : ''}.';
  }
}
