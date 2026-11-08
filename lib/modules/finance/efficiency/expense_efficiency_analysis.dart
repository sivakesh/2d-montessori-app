import 'package:intl/intl.dart';

import '../../admin/settings/models/academic_year_date_range.dart';
import '../../admin/settings/models/academic_year_model.dart';
import '../models/finance_ledger_entry_model.dart';
import '../models/ledger_period.dart';
import 'expense_efficiency_models.dart';

/// Finance → Expense Efficiency figures, built once from the ledger
/// entries (the same `watchLedger()` list the Ledger tab uses), the
/// assessments and the targets, and shown on screen and in the PDF from
/// this same object (so the two always agree). Read-only.
///
/// Formulas, for the selected period:
/// - Actual: income and expenses exactly as the Ledger's Profit / Loss
///   (LedgerPeriodSummary: non-cancelled entries by `entryType`, by their
///   `transactionDate`'s calendar day). Actual Operating Surplus = Income −
///   Actual Expenses.
/// - Identified Potential Savings = Σ avoidable amounts of non-cancelled
///   Waste / Avoidable and Excessive expenses, each capped at the expense's
///   current amount. Necessary, Useful and Under Review add nothing.
/// - Adjusted Operating Surplus = Actual Operating Surplus + Identified
///   Potential Savings (hypothetical).
/// - Target Expenses = Σ over expense categories and months of the
///   category's monthly target where one applies to that whole month,
///   otherwise the category's actual spending in that month (a missing
///   target is never zero). Target Operating Surplus = Income − Target
///   Expenses.
/// Amounts are summed in paise.

enum EfficiencyPeriodKind { month, financialYear, custom }

/// The selected period: a calendar month, a financial (academic) year, or
/// an inclusive custom date range. Days are local calendar days, as in the
/// Ledger.
class EfficiencyPeriod {
  EfficiencyPeriod.month(int year, int month)
      : kind = EfficiencyPeriodKind.month,
        start = DateTime(year, month),
        end = DateTime(year, month + 1, 0),
        year = null;

  EfficiencyPeriod.financialYear(AcademicYearModel this.year)
      : kind = EfficiencyPeriodKind.financialYear,
        start = AcademicYearDateRange.fromAcademicYear(year).start,
        end = AcademicYearDateRange.fromAcademicYear(year).end;

  EfficiencyPeriod.custom(DateTime from, DateTime to)
      : kind = EfficiencyPeriodKind.custom,
        start = DateTime(from.year, from.month, from.day),
        end = DateTime(to.year, to.month, to.day),
        year = null,
        assert(!to.isBefore(from));

  final EfficiencyPeriodKind kind;
  final DateTime start, end;

  /// For a financial year.
  final AcademicYearModel? year;

  bool contains(DateTime? d) {
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  /// Every month the period touches, in order (`YYYY-MM`).
  List<String> get months => [
        for (var m = DateTime(start.year, start.month); !m.isAfter(end); m = DateTime(m.year, m.month + 1)) monthKey(m),
      ];

  /// Whether the period covers [month] from its first to its last day.
  bool coversWholeMonth(String month) {
    final first = monthStart(month);
    final last = DateTime(first.year, first.month + 1, 0);
    return !first.isBefore(start) && !last.isAfter(end);
  }

  String get label => switch (kind) {
        EfficiencyPeriodKind.month => DateFormat('MMMM yyyy').format(start),
        EfficiencyPeriodKind.financialYear => 'Financial year ${year!.name} (${_d(start)} – ${_d(end)})',
        EfficiencyPeriodKind.custom => '${_d(start)} – ${_d(end)}',
      };

  static String _d(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// Income and expenses as the Ledger's Profit / Loss: a month through
  /// LedgerPeriodSummary for that LedgerPeriod; any other range by the same
  /// calculation over the entries dated in it.
  LedgerPeriodSummary summary(Iterable<FinanceLedgerEntryModel> entries) => kind == EfficiencyPeriodKind.month
      ? LedgerPeriodSummary.of(entries, LedgerPeriod.month(start.year, start.month))
      : LedgerPeriodSummary.of(entries.where((e) => contains(e.transactionDate)), const LedgerPeriod.allTime());

  /// The month before (month), or the range of equal length just before
  /// (custom). A financial year's previous year comes from [previousYear].
  EfficiencyPeriod? get previous => switch (kind) {
        EfficiencyPeriodKind.month => EfficiencyPeriod.month(start.year, start.month - 1),
        EfficiencyPeriodKind.custom => EfficiencyPeriod.custom(
            start.subtract(Duration(days: end.difference(start).inDays + 1)), start.subtract(const Duration(days: 1))),
        EfficiencyPeriodKind.financialYear => null,
      };

  /// A month: the same month a year earlier.
  EfficiencyPeriod? get sameMonthLastYear => kind == EfficiencyPeriodKind.month ? EfficiencyPeriod.month(start.year - 1, start.month) : null;

  /// The financial year before [year] among [years] (latest start before it).
  static AcademicYearModel? previousYear(AcademicYearModel year, List<AcademicYearModel> years) {
    final earlier = [for (final y in years) if (y.startDate.isBefore(year.startDate)) y]..sort((a, b) => b.startDate.compareTo(a.startDate));
    return earlier.isEmpty ? null : earlier.first;
  }
}

/// Narrowing filters for the expense lists and category figures. The
/// surplus figures (Actual, Adjusted, Target) always cover every income and
/// expense entry in the period, so Actual always equals the Ledger.
class EfficiencyFilter {
  const EfficiencyFilter({this.categoryId, this.assessment, this.status = EfficiencyStatusFilter.all});
  final String? categoryId;
  final ExpenseAssessmentCategory? assessment;
  final EfficiencyStatusFilter status;

  bool get isEmpty => categoryId == null && assessment == null && status == EfficiencyStatusFilter.all;
}

enum EfficiencyStatusFilter {
  all('All'),
  assessed('Assessed'),
  notAssessed('Not assessed'),
  needsReview('Needs review'),
  cancelled('Cancelled');

  const EfficiencyStatusFilter(this.label);
  final String label;
}

/// One expense ledger entry with its assessment.
class EfficiencyItem {
  EfficiencyItem(this.entry, this.assessment);

  final FinanceLedgerEntryModel entry;

  /// null: not assessed (shown as Under Review).
  final ExpenseAssessment? assessment;

  String get id => entry.id;
  bool get cancelled => entry.status == 'cancelled';
  ExpenseAssessmentCategory get category => assessment?.category ?? ExpenseAssessmentCategory.underReview;

  /// Assessed: an assessment other than Under Review.
  bool get isAssessed => assessment != null && category != ExpenseAssessmentCategory.underReview;

  String get categoryKey => entry.categoryId.isNotEmpty ? entry.categoryId : (entry.categoryName.isNotEmpty ? 'name:${entry.categoryName}' : '');
  String get categoryName => entry.categoryName.isNotEmpty ? entry.categoryName : 'Uncategorised';

  int get amountP => paiseOf(entry.amount);
  int get recordedAvoidableP => category.hasAvoidable ? paiseOf(assessment!.avoidableAmount) : 0;

  /// Counted toward savings: never when cancelled, never above the current
  /// amount, never negative.
  int get countedAvoidableP => cancelled ? 0 : recordedAvoidableP.clamp(0, amountP < 0 ? 0 : amountP);
  double get countedAvoidable => rupeesOf(countedAvoidableP);

  /// The recorded avoidable amount is more than the expense's current
  /// amount (it was edited down): only the current amount is counted.
  bool get avoidableExceedsAmount => recordedAvoidableP > amountP;

  /// The expense amount changed since it was assessed.
  bool get amountChanged => assessment != null && paiseOf(assessment!.amountAtAssessment) != amountP;

  bool get needsReview => !cancelled && (avoidableExceedsAmount || (amountChanged && category.hasAvoidable));

  String? get reviewReason {
    if (cancelled) return null;
    if (avoidableExceedsAmount) {
      return 'The recorded avoidable amount ${efficiencyMoney(rupeesOf(recordedAvoidableP))} is more than the current expense amount '
          '${efficiencyMoney(entry.amount)} (edited since); only ${efficiencyMoney(countedAvoidable)} is counted. Review the assessment.';
    }
    if (amountChanged && category.hasAvoidable) {
      return 'The expense amount changed from ${efficiencyMoney(assessment!.amountAtAssessment)} to ${efficiencyMoney(entry.amount)} since it was assessed.';
    }
    return null;
  }
}

/// Per expense category: actual, target and the target scenario.
class EfficiencyCategoryRow {
  EfficiencyCategoryRow(this.key, this.name);
  final String key, name;
  int actualP = 0, targetP = 0, actualInTargetedP = 0, scenarioP = 0, avoidableP = 0;
  int targetedMonths = 0, untargetedMonths = 0, overTargetMonths = 0, wasteCount = 0, excessiveCount = 0;
  final Map<String, int> monthlyActualP = {};

  double get actual => rupeesOf(actualP);
  double get target => rupeesOf(targetP);
  bool get hasTarget => targetedMonths > 0;
  bool get fullyTargeted => hasTarget && untargetedMonths == 0;

  /// Over (+) or under (−) target, over the targeted months only.
  double? get difference => hasTarget ? rupeesOf(actualInTargetedP - targetP) : null;
  double? get variancePercent => hasTarget && targetP > 0 ? (actualInTargetedP - targetP) / targetP * 100 : null;
  double get scenario => rupeesOf(scenarioP);

  String get targetLabel => !hasTarget
      ? 'Target not set'
      : fullyTargeted
          ? efficiencyMoney(target)
          : '${efficiencyMoney(target)} ($targetedMonths of ${targetedMonths + untargetedMonths} months)';
}

class EfficiencyMonthRow {
  EfficiencyMonthRow(this.month);
  final String month;
  int incomeP = 0, expensesP = 0, avoidableP = 0, targetScenarioP = 0;
  String get label => monthLabel(month);
}

/// A comparison of two periods' actual figures.
class EfficiencyComparison {
  EfficiencyComparison({required this.title, required this.current, required this.other, required this.otherLabel, required this.incomplete});
  final String title, otherLabel;
  final EfficiencySnapshot current, other;

  /// The other period may be missing data: no entries in it, or it starts
  /// before the earliest dated ledger entry.
  final bool incomplete;
}

class EfficiencySnapshot {
  const EfficiencySnapshot({required this.income, required this.expenses, required this.savings, required this.entries});
  final double income, expenses, savings;
  final int entries;
  double get surplus => rupeesOf(paiseOf(income) - paiseOf(expenses));
}

class ExpenseEfficiencyReport {
  ExpenseEfficiencyReport._({
    required this.period,
    required this.filter,
    required this.income,
    required this.expenses,
    required this.allItems,
    required this.items,
    required this.categories,
    required this.months,
    required this.orphans,
    required this.undatedExpenses,
  });

  final EfficiencyPeriod period;
  final EfficiencyFilter filter;

  /// Ledger Profit / Loss figures for the period (all entries).
  final double income, expenses;

  /// Every expense entry dated in the period (cancelled ones included,
  /// marked), and the ones matching [filter].
  final List<EfficiencyItem> allItems, items;

  /// Expense categories (all of the period's expenses), by actual spend.
  final List<EfficiencyCategoryRow> categories;
  final List<EfficiencyMonthRow> months;

  /// Assessments whose transaction no longer exists in the ledger or is no
  /// longer an expense: never counted, listed for review.
  final List<ExpenseAssessment> orphans;

  /// Non-cancelled expenses without a transaction date: can't be placed in
  /// a period (as in the Ledger), so in no period's totals.
  final int undatedExpenses;

  List<EfficiencyItem> get _valid => [for (final i in allItems) if (!i.cancelled) i];

  // ------------------------------------------------ actual / adjusted / target
  double get actualSurplus => rupeesOf(paiseOf(income) - paiseOf(expenses));
  double get potentialSavings => rupeesOf(_valid.fold(0, (s, i) => s + i.countedAvoidableP));
  double get adjustedSurplus => rupeesOf(paiseOf(actualSurplus) + paiseOf(potentialSavings));
  double get targetExpenses => rupeesOf(categories.fold(0, (s, c) => s + c.scenarioP));
  double get targetSurplus => rupeesOf(paiseOf(income) - paiseOf(targetExpenses));
  List<EfficiencyCategoryRow> get untargetedCategories => [for (final c in categories) if (!c.fullyTargeted) c];
  List<EfficiencyCategoryRow> get targetedCategories => [for (final c in categories) if (c.hasTarget) c];

  // ------------------------------------------------ assessment totals (filtered)
  List<EfficiencyItem> get _validFiltered => [for (final i in items) if (!i.cancelled) i];
  double total(ExpenseAssessmentCategory c) => rupeesOf(_validFiltered.where((i) => i.category == c).fold(0, (s, i) => s + i.amountP));
  int count(ExpenseAssessmentCategory c) => _validFiltered.where((i) => i.category == c).length;
  double get filteredExpenses => rupeesOf(_validFiltered.fold(0, (s, i) => s + i.amountP));
  double get filteredSavings => rupeesOf(_validFiltered.fold(0, (s, i) => s + i.countedAvoidableP));
  int get assessedCount => _validFiltered.where((i) => i.isAssessed).length;
  int get unassessedCount => _validFiltered.where((i) => !i.isAssessed).length;
  double get assessedAmount => rupeesOf(_validFiltered.where((i) => i.isAssessed).fold(0, (s, i) => s + i.amountP));
  double get unassessedAmount => rupeesOf(_validFiltered.where((i) => !i.isAssessed).fold(0, (s, i) => s + i.amountP));
  double get coveragePercent => _validFiltered.isEmpty ? 0 : assessedCount / _validFiltered.length * 100;
  List<EfficiencyItem> get needsReview => [for (final i in allItems) if (i.needsReview) i];
  int get cancelledCount => allItems.where((i) => i.cancelled).length;

  // ------------------------------------------------ insights (observations, rule-based)
  List<EfficiencyCategoryRow> get highestSpend => [for (final c in categories) if (c.actualP > 0) c].take(5).toList();
  List<EfficiencyCategoryRow> get mostWaste =>
      ([for (final c in categories) if (c.wasteCount > 0) c]..sort((a, b) => b.wasteCount != a.wasteCount ? b.wasteCount - a.wasteCount : b.avoidableP - a.avoidableP)).take(5).toList();
  List<EfficiencyCategoryRow> get recurringOverspend => [for (final c in categories) if (c.overTargetMonths >= 2) c];
  List<EfficiencyItem> get excessiveWithAvoidable =>
      [for (final i in _valid) if (i.category == ExpenseAssessmentCategory.excessive && i.countedAvoidableP > 0) i];

  /// Rule-based, each an observation with a suggestion; never a judgment
  /// about an expense that management hasn't assessed.
  List<({String observation, String suggestion})> get insights => [
        if (_valid.any((i) => !i.isAssessed))
          (
            observation: '${_valid.where((i) => !i.isAssessed).length} expenses (${efficiencyMoney(rupeesOf(_valid.where((i) => !i.isAssessed).fold(0, (s, i) => s + i.amountP)))}) are not yet assessed.',
            suggestion: 'Assess them so the potential savings figure is complete.',
          ),
        for (final c in recurringOverspend)
          (
            observation: '${c.name} was over its target in ${c.overTargetMonths} of ${c.targetedMonths} targeted months.',
            suggestion: 'Review purchasing and usage for ${c.name}, or revisit its target.',
          ),
        for (final c in mostWaste.take(3))
          (
            observation: '${c.name} has ${c.wasteCount} expense${c.wasteCount == 1 ? '' : 's'} assessed as Waste / Avoidable.',
            suggestion: 'Check the corrective actions recorded for ${c.name}.',
          ),
        if (needsReview.isNotEmpty)
          (
            observation: '${needsReview.length} assessment${needsReview.length == 1 ? '' : 's'} no longer match the expense amount.',
            suggestion: 'Review them; only the current expense amount is counted meanwhile.',
          ),
      ];

  /// Builds the report. [entries]: the ledger (watchLedger); [assessments]
  /// by transaction id; [targets]: all targets (inactive ones are ignored);
  /// [categoryNames]: expense categories by id (for names and empty rows).
  static ExpenseEfficiencyReport build({
    required List<FinanceLedgerEntryModel> entries,
    required Map<String, ExpenseAssessment> assessments,
    required List<ExpenseTarget> targets,
    required EfficiencyPeriod period,
    EfficiencyFilter filter = const EfficiencyFilter(),
    Map<String, String> categoryNames = const {},
  }) {
    final summary = period.summary(entries);
    final expenseIds = {for (final e in entries) if (e.entryType == 'expense') e.id};
    final all = [
      for (final e in entries)
        if (e.entryType == 'expense' && period.contains(e.transactionDate)) EfficiencyItem(e, assessments[e.id]),
    ]..sort((a, b) {
        final c = (b.entry.transactionDate ?? DateTime(0)).compareTo(a.entry.transactionDate ?? DateTime(0));
        return c != 0 ? c : a.id.compareTo(b.id);
      });

    bool matches(EfficiencyItem i) {
      if (filter.categoryId != null && i.categoryKey != filter.categoryId) return false;
      if (filter.assessment != null && (i.cancelled || i.category != filter.assessment)) return false;
      return switch (filter.status) {
        EfficiencyStatusFilter.all => true,
        EfficiencyStatusFilter.assessed => !i.cancelled && i.isAssessed,
        EfficiencyStatusFilter.notAssessed => !i.cancelled && !i.isAssessed,
        EfficiencyStatusFilter.needsReview => i.needsReview,
        EfficiencyStatusFilter.cancelled => i.cancelled,
      };
    }

    // Categories: every expense category, plus any seen on an expense or a target.
    final rows = <String, EfficiencyCategoryRow>{};
    EfficiencyCategoryRow row(String key, String name) => rows.putIfAbsent(key, () => EfficiencyCategoryRow(key, name));
    categoryNames.forEach((id, name) => row(id, name));
    final active = [for (final t in targets) if (t.isActive && t.error == null) t];
    for (final t in active) {
      row(t.categoryId, categoryNames[t.categoryId] ?? t.categoryName);
    }
    final valid = [for (final i in all) if (!i.cancelled) i];
    for (final i in valid) {
      final r = row(i.categoryKey, categoryNames[i.categoryKey] ?? i.categoryName);
      r.actualP += i.amountP;
      r.avoidableP += i.countedAvoidableP;
      final m = monthKey(i.entry.transactionDate!);
      r.monthlyActualP[m] = (r.monthlyActualP[m] ?? 0) + i.amountP;
      if (i.category == ExpenseAssessmentCategory.waste) r.wasteCount++;
      if (i.category == ExpenseAssessmentCategory.excessive) r.excessiveCount++;
    }

    final monthRows = {for (final m in period.months) m: EfficiencyMonthRow(m)};
    for (final e in entries) {
      if (e.status == 'cancelled' || !period.contains(e.transactionDate)) continue;
      final r = monthRows[monthKey(e.transactionDate!)];
      if (r == null) continue;
      if (e.entryType == 'income') r.incomeP += paiseOf(e.amount);
      if (e.entryType == 'expense') r.expensesP += paiseOf(e.amount);
    }
    for (final i in valid) {
      monthRows[monthKey(i.entry.transactionDate!)]?.avoidableP += i.countedAvoidableP;
    }

    // Targets: per category and month, a target for a month the period
    // covers wholly; otherwise (or with none) the actual spending.
    for (final r in rows.values) {
      for (final m in period.months) {
        final actualM = r.monthlyActualP[m] ?? 0;
        final t = period.coversWholeMonth(m) ? active.where((t) => t.categoryId == r.key && t.covers(m)).firstOrNull : null;
        if (t != null) {
          final tp = paiseOf(t.monthlyAmount);
          r.targetedMonths++;
          r.targetP += tp;
          r.actualInTargetedP += actualM;
          r.scenarioP += tp;
          if (actualM > tp) r.overTargetMonths++;
          monthRows[m]?.targetScenarioP += tp;
        } else {
          r.untargetedMonths++;
          r.scenarioP += actualM;
          monthRows[m]?.targetScenarioP += actualM;
        }
      }
    }

    final categories = rows.values.toList()
      ..sort((a, b) => b.actualP != a.actualP ? b.actualP - a.actualP : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ExpenseEfficiencyReport._(
      period: period,
      filter: filter,
      income: summary.totalIncome,
      expenses: summary.totalExpenses,
      allItems: all,
      items: [for (final i in all) if (matches(i)) i],
      categories: categories,
      months: monthRows.values.toList(),
      orphans: [for (final a in assessments.values) if (!expenseIds.contains(a.transactionId)) a],
      undatedExpenses: entries.where((e) => e.entryType == 'expense' && e.status != 'cancelled' && e.transactionDate == null).length,
    );
  }

  /// Actual figures of [other] beside [current] (the same rules).
  static EfficiencyComparison compare({
    required String title,
    required List<FinanceLedgerEntryModel> entries,
    required Map<String, ExpenseAssessment> assessments,
    required EfficiencyPeriod current,
    required EfficiencyPeriod other,
  }) {
    EfficiencySnapshot snap(EfficiencyPeriod p) {
      final r = build(entries: entries, assessments: assessments, targets: const [], period: p);
      return EfficiencySnapshot(income: r.income, expenses: r.expenses, savings: r.potentialSavings,
          entries: entries.where((e) => e.status != 'cancelled' && p.contains(e.transactionDate)).length);
    }

    final dated = [for (final e in entries) if (e.transactionDate != null) e.transactionDate!]..sort();
    final o = snap(other);
    final earliest = dated.isEmpty ? null : DateTime(dated.first.year, dated.first.month, dated.first.day);
    return EfficiencyComparison(
      title: title,
      current: snap(current),
      other: o,
      otherLabel: other.label,
      incomplete: o.entries == 0 || earliest == null || earliest.isAfter(other.start),
    );
  }
}
