import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../admin/settings/models/academic_year_model.dart';
import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../admin/settings/providers/academic_year_provider.dart';
import '../../admin/settings/providers/school_identity_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../fees/services/fee_report_pdf.dart' show FeeReportPdfHeader;
import '../../fees/ui/fee_reports_tab.dart' show FeePdfExporter, sharePdfExporter;
import '../models/finance_category_model.dart';
import '../models/finance_ledger_entry_model.dart';
import '../services/finance_service.dart';
import 'expense_category_pill.dart';
import 'expense_efficiency_analysis.dart';
import 'expense_efficiency_dialogs.dart';
import 'expense_efficiency_models.dart';
import 'expense_efficiency_pdf.dart';
import 'expense_efficiency_service.dart';

/// Finance → Reports → Expense Efficiency (ExpenseEfficiencyPage): a read-only analysis of the ledger (the
/// same `watchLedger()` stream the Ledger tab uses) with management's own
/// assessments and monthly targets. Only those two are written, and only
/// by an administrator; nothing in Finance is changed.
class ExpenseEfficiencyTab extends ConsumerStatefulWidget {
  const ExpenseEfficiencyTab({super.key, required this.finance, required this.service, required this.clock, this.exportPdf = sharePdfExporter});

  final FinanceService finance;
  final ExpenseEfficiencyService service;
  final DateTime Function() clock;
  final FeePdfExporter exportPdf;

  static const adjustedLabel = 'Adjusted Operating Surplus – hypothetical, excluding identified avoidable spending';

  @override
  ConsumerState<ExpenseEfficiencyTab> createState() => _ExpenseEfficiencyTabState();
}

class _ExpenseEfficiencyTabState extends ConsumerState<ExpenseEfficiencyTab> {
  final _subs = <StreamSubscription<Object?>>[];
  List<FinanceLedgerEntryModel>? _ledger;
  Map<String, ExpenseAssessment>? _assessments;
  List<ExpenseTarget>? _targets;
  List<FinanceCategoryModel> _categories = const [];
  List<AcademicYearModel> _years = const [];
  String? _error;

  EfficiencyPeriodKind _kind = EfficiencyPeriodKind.month;
  late DateTime _month = DateTime(widget.clock().year, widget.clock().month);
  String? _yearId;
  DateTimeRange? _range;
  EfficiencyFilter _filter = const EfficiencyFilter();
  int _page = 0;
  static const _pageSize = 20;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    void fail(Object e) {
      if (mounted) setState(() => _error = 'Expense Efficiency could not load: $e');
    }

    _subs
      ..add(widget.finance.watchLedger().listen((v) => setState(() => _ledger = v), onError: fail))
      ..add(widget.finance.watchCategories().listen((v) => setState(() => _categories = v), onError: fail))
      ..add(widget.service.watchAssessments().listen((v) => setState(() => _assessments = v), onError: fail))
      ..add(widget.service.watchTargets().listen((v) => setState(() => _targets = v), onError: fail));
    ref.read(academicYearServiceProvider).getAllAcademicYears(schoolId: kDefaultSchoolId).then((y) {
      if (!mounted) return;
      setState(() {
        _years = [...y]..sort((a, b) => b.startDate.compareTo(a.startDate));
        _yearId = _years.where((y) => y.isCurrent).firstOrNull?.id ?? _years.firstOrNull?.id;
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  String get _role => ref.read(currentUserProvider)?.role ?? '';
  bool get _canEdit => (ref.watch(currentUserProvider)?.role ?? '').toLowerCase() == 'admin';

  AcademicYearModel? get _year => _years.where((y) => y.id == _yearId).firstOrNull;

  EfficiencyPeriod get _period => switch (_kind) {
        EfficiencyPeriodKind.financialYear when _year != null => EfficiencyPeriod.financialYear(_year!),
        EfficiencyPeriodKind.custom when _range != null => EfficiencyPeriod.custom(_range!.start, _range!.end),
        _ => EfficiencyPeriod.month(_month.year, _month.month),
      };

  /// Expense categories: Finance's own, plus any seen on an expense.
  Map<String, String> get _categoryNames => {
        for (final c in _categories) if (c.type == 'expense') c.id: c.name,
        for (final e in _ledger ?? const <FinanceLedgerEntryModel>[])
          if (e.entryType == 'expense' && e.categoryId.isNotEmpty && !_categories.any((c) => c.id == e.categoryId)) e.categoryId: e.categoryName.isEmpty ? e.categoryId : e.categoryName,
      };

  ExpenseEfficiencyReport _report() => ExpenseEfficiencyReport.build(
        entries: _ledger!,
        assessments: _assessments!,
        targets: _targets!,
        period: _period,
        filter: _filter,
        categoryNames: _categoryNames,
      );

  List<String> _filterLabels() => [
        'Period: ${_period.label}',
        'Category: ${_filter.categoryId == null ? 'All' : _categoryNames[_filter.categoryId] ?? _filter.categoryId}',
        'Assessment: ${_filter.assessment?.label ?? 'All'}',
        'Status: ${_filter.status.label}',
      ];

  /// The school name from School Settings, as on the Fees report PDFs.
  String _schoolName() {
    final name = ref.read(schoolIdentityProvider).valueOrNull?.name.trim() ?? '';
    return name.isEmpty ? '2D Montessori' : name;
  }

  Future<void> _export(ExpenseEfficiencyReport r) async {
    setState(() => _exporting = true);
    try {
      final bytes = await ExpenseEfficiencyPdf.build(
        r,
        FeeReportPdfHeader(
          schoolName: _schoolName(), title: ExpenseEfficiencyPdf.title, filters: _filterLabels().skip(1).toList(), generatedAt: widget.clock(),
          logo: await FeeReportPdfHeader.bundledLogo(),
        ),
      );
      await widget.exportPdf(Uint8List.fromList(bytes), 'expense-efficiency-${DateFormat('yyyyMMdd').format(_period.start)}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('The PDF could not be created: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _assess(EfficiencyItem i) => showDialog<bool>(
        context: context,
        builder: (_) => ExpenseAssessmentDialog(service: widget.service, role: _role, entry: i.entry, current: i.assessment),
      );

  Future<void> _editTarget([ExpenseTarget? t]) => showDialog<bool>(
        context: context,
        builder: (_) => ExpenseTargetDialog(service: widget.service, role: _role, categories: _categoryNames, current: t, initialMonth: monthKey(_period.start)),
      );

  Future<void> _toggleTarget(ExpenseTarget t) async {
    try {
      await widget.service.setTargetActive(requesterRole: _role, target: t, active: !t.isActive);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Bad state: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final e?) return Text(e, key: const Key('efficiency-error'), style: const TextStyle(color: Colors.red));
    if (_ledger == null || _assessments == null || _targets == null) return const Center(child: CircularProgressIndicator());
    final r = _report();
    final theme = Theme.of(context);
    return Column(
      key: const Key('expense-efficiency'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Expense Efficiency', style: theme.textTheme.titleLarge),
        Text('Management analysis of recorded expenses. Actual figures are the Finance Ledger\'s; assessments and targets are planning data and never change Finance.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        _controls(),
        const SizedBox(height: 8),
        Text('Showing ${r.period.label}', key: const Key('efficiency-period'), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (!_filter.isEmpty)
          Text('Category, assessment and status filters narrow the expense list and assessment figures; the surplus figures always cover all of the period\'s income and expenses.',
              key: const Key('efficiency-filter-note'), style: theme.textTheme.bodySmall),
        if (r.undatedExpenses > 0)
          Text('${r.undatedExpenses} expense(s) have no transaction date and can\'t be placed in a period (as in the Ledger).', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        _card('Financial overview', 'efficiency-overview', _tiles([
          ('income', 'Total Income', efficiencyMoney(r.income)),
          ('expenses', 'Total Actual Expenses', efficiencyMoney(r.expenses)),
          ('surplus', 'Actual Operating Surplus', efficiencyMoney(r.actualSurplus)),
          ('savings', 'Identified Potential Savings', efficiencyMoney(r.potentialSavings)),
        ])),
        _card('Expense assessment', 'efficiency-assessment', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _categoryTiles(r),
          const SizedBox(height: 8),
          _tiles([
            ('coverage', 'Assessment coverage', '${r.coveragePercent.toStringAsFixed(1)}%'),
            ('assessed', 'Assessed', '${r.assessedCount} · ${efficiencyMoney(r.assessedAmount)}'),
            ('unassessed', 'Not assessed', '${r.unassessedCount} · ${efficiencyMoney(r.unassessedAmount)}'),
          ]),
          if (r.cancelledCount > 0) Text('${r.cancelledCount} cancelled expense(s) in this period are not counted.', style: theme.textTheme.bodySmall),
        ])),
        _card('Actual vs Adjusted vs Target', 'efficiency-scenarios', _scenarios(r)),
        _card('Category-wise expenses and targets', 'efficiency-categories', _categoryTable(r)),
        _card('Monthly trend', 'efficiency-months', _monthTable(r)),
        _card('Historical comparison', 'efficiency-comparison', _comparisons()),
        _card('Observations and suggestions', 'efficiency-insights', _insights(r)),
        _card('Monthly targets', 'efficiency-targets', _targetList()),
        _card('Expenses', 'efficiency-expenses', _expenseList(r)),
        if (r.needsReview.isNotEmpty || r.orphans.isNotEmpty) _card('Needs review', 'efficiency-review', _reviewList(r)),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('efficiency-export'),
            onPressed: _exporting ? null : () => _export(r),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export Report as PDF'),
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    final cats = _categoryNames;
    return Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SegmentedButton<EfficiencyPeriodKind>(
        key: const Key('efficiency-period-kind'),
        segments: const [
          ButtonSegment(value: EfficiencyPeriodKind.month, label: Text('Month')),
          ButtonSegment(value: EfficiencyPeriodKind.financialYear, label: Text('Financial year')),
          ButtonSegment(value: EfficiencyPeriodKind.custom, label: Text('Custom')),
        ],
        selected: {_kind},
        onSelectionChanged: (s) async {
          final k = s.first;
          if (k == EfficiencyPeriodKind.custom && _range == null) {
            final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDateRange: DateTimeRange(start: _period.start, end: _period.end));
            if (picked == null) return;
            _range = picked;
          }
          setState(() {
            _kind = k;
            _page = 0;
          });
        },
      ),
      if (_kind == EfficiencyPeriodKind.month) ...[
        IconButton(key: const Key('efficiency-month-prev'), tooltip: 'Previous month', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
        Text(DateFormat('MMMM yyyy').format(_month), key: const Key('efficiency-month-label')),
        IconButton(key: const Key('efficiency-month-next'), tooltip: 'Next month', icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
      ],
      if (_kind == EfficiencyPeriodKind.financialYear)
        _years.isEmpty
            ? const Text('No academic (financial) years are set up.')
            : DropdownButton<String>(
                key: const Key('efficiency-year'),
                value: _yearId,
                items: [for (final y in _years) DropdownMenuItem(value: y.id, child: Text(y.name))],
                onChanged: (v) => setState(() => _yearId = v),
              ),
      if (_kind == EfficiencyPeriodKind.custom)
        TextButton(
          key: const Key('efficiency-range'),
          onPressed: () async {
            final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100), initialDateRange: _range);
            if (picked != null) setState(() => _range = picked);
          },
          child: Text(_period.label),
        ),
      DropdownButton<String?>(
        key: const Key('efficiency-filter-category'),
        value: _filter.categoryId,
        hint: const Text('All categories'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
          for (final MapEntry(:key, :value) in cats.entries) DropdownMenuItem<String?>(value: key, child: Text(value)),
        ],
        onChanged: (v) => setState(() {
          _filter = EfficiencyFilter(categoryId: v, assessment: _filter.assessment, status: _filter.status);
          _page = 0;
        }),
      ),
      DropdownButton<ExpenseAssessmentCategory?>(
        key: const Key('efficiency-filter-assessment'),
        value: _filter.assessment,
        hint: const Text('All assessments'),
        items: [
          const DropdownMenuItem<ExpenseAssessmentCategory?>(value: null, child: Text('All assessments')),
          for (final c in ExpenseAssessmentCategory.values) DropdownMenuItem(value: c, child: Text(c.label)),
        ],
        onChanged: (v) => setState(() {
          _filter = EfficiencyFilter(categoryId: _filter.categoryId, assessment: v, status: _filter.status);
          _page = 0;
        }),
      ),
      DropdownButton<EfficiencyStatusFilter>(
        key: const Key('efficiency-filter-status'),
        value: _filter.status,
        items: [for (final s in EfficiencyStatusFilter.values) DropdownMenuItem(value: s, child: Text(s == EfficiencyStatusFilter.all ? 'All statuses' : s.label))],
        onChanged: (v) => setState(() {
          _filter = EfficiencyFilter(categoryId: _filter.categoryId, assessment: _filter.assessment, status: v!);
          _page = 0;
        }),
      ),
    ]);
  }

  Widget _card(String title, String key, Widget body) => Card(
        key: Key(key),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            body,
          ]),
        ),
      );

  Widget _tiles(List<(String, String, String)> items) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (key, label, value) in items)
          Container(
            constraints: const BoxConstraints(minWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, key: Key('efficiency-tile-$key'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
      ]);

  /// One tile per assessment category, headed by its coloured pill, with
  /// the count beside it and the amount below.
  Widget _categoryTiles(ExpenseEfficiencyReport r) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in ExpenseAssessmentCategory.values)
          Container(
            key: Key('efficiency-category-tile-${c.key}'),
            constraints: const BoxConstraints(minWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                ExpenseCategoryPill(c),
                const SizedBox(width: 6),
                Text('${r.count(c)}', key: Key('efficiency-tile-count-${c.key}'), style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 4),
              Text(efficiencyMoney(r.total(c)), key: Key('efficiency-tile-${c.key}'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
      ]);

  Widget _scenarios(ExpenseEfficiencyReport r) {
    final values = [
      ('actual', 'Actual Operating Surplus', r.actualSurplus),
      ('adjusted', ExpenseEfficiencyTab.adjustedLabel, r.adjustedSurplus),
      ('target', 'Target Operating Surplus (planning)', r.targetSurplus),
    ];
    final maxAbs = values.map((v) => v.$3.abs()).fold<double>(0, (a, b) => a > b ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (key, label, v) in values)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Row(children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: maxAbs == 0 ? 0 : v.abs() / maxAbs,
                  minHeight: 10,
                  color: paiseOf(v) < 0 ? Colors.red.shade400 : (key == 'actual' ? Theme.of(context).colorScheme.primary : Colors.teal),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: Text(efficiencyMoney(v), key: Key('efficiency-scenario-$key'), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ]),
        ),
      Text('Adjusted − Actual: ${efficiencyMoney(r.adjustedSurplus - r.actualSurplus)} (identified potential savings)  ·  '
          'Target − Actual: ${efficiencyMoney(r.targetSurplus - r.actualSurplus)}  ·  Target − Adjusted: ${efficiencyMoney(r.targetSurplus - r.adjustedSurplus)}',
          key: const Key('efficiency-scenario-differences')),
      const SizedBox(height: 4),
      Text('Target expenses ${efficiencyMoney(r.targetExpenses)}: each category\'s monthly target for the months it covers in full; '
          'actual spending where no target is set (missing targets are never treated as zero).',
          style: Theme.of(context).textTheme.bodySmall),
      if (r.untargetedCategories.isNotEmpty)
        Text('Without a target for every month: ${r.untargetedCategories.map((c) => c.name).join(', ')}.',
            key: const Key('efficiency-untargeted'), style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _scroll(Widget table) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);

  Widget _categoryTable(ExpenseEfficiencyReport r) => r.categories.isEmpty
      ? const Text('No expense categories.')
      : _scroll(DataTable(
          key: const Key('efficiency-category-table'),
          columns: const [
            DataColumn(label: Text('Category')),
            DataColumn(label: Text('Actual'), numeric: true),
            DataColumn(label: Text('Target')),
            DataColumn(label: Text('Difference'), numeric: true),
            DataColumn(label: Text('Variance'), numeric: true),
            DataColumn(label: Text('Avoidable'), numeric: true),
          ],
          rows: [
            for (final c in r.categories)
              DataRow(key: ValueKey('efficiency-category-${c.key}'), cells: [
                DataCell(Text(c.name)),
                DataCell(Text(efficiencyMoney(c.actual))),
                DataCell(Text(c.targetLabel, key: Key('efficiency-target-${c.key}'))),
                DataCell(Text(c.difference == null ? '—' : '${efficiencyMoney(c.difference!)} ${paiseOf(c.difference!) > 0 ? 'over' : paiseOf(c.difference!) < 0 ? 'under' : ''}'.trim(),
                    style: TextStyle(color: (c.difference ?? 0) > 0 ? Colors.red.shade700 : null))),
                DataCell(Text(c.variancePercent == null ? '—' : '${c.variancePercent!.toStringAsFixed(1)}%')),
                DataCell(Text(efficiencyMoney(rupeesOf(c.avoidableP)))),
              ]),
          ],
        ));

  Widget _monthTable(ExpenseEfficiencyReport r) => _scroll(DataTable(
        key: const Key('efficiency-month-table'),
        columns: const [
          DataColumn(label: Text('Month')),
          DataColumn(label: Text('Income'), numeric: true),
          DataColumn(label: Text('Expenses'), numeric: true),
          DataColumn(label: Text('Surplus'), numeric: true),
          DataColumn(label: Text('Identified avoidable'), numeric: true),
          DataColumn(label: Text('Target scenario expenses'), numeric: true),
        ],
        rows: [
          for (final m in r.months)
            DataRow(cells: [
              DataCell(Text(m.label)),
              DataCell(Text(efficiencyMoney(rupeesOf(m.incomeP)))),
              DataCell(Text(efficiencyMoney(rupeesOf(m.expensesP)))),
              DataCell(Text(efficiencyMoney(rupeesOf(m.incomeP - m.expensesP)))),
              DataCell(Text(efficiencyMoney(rupeesOf(m.avoidableP)))),
              DataCell(Text(efficiencyMoney(rupeesOf(m.targetScenarioP)))),
            ]),
        ],
      ));

  Widget _comparisons() {
    final p = _period;
    final pairs = <(String, EfficiencyPeriod)>[
      if (p.previous case final prev?) (p.kind == EfficiencyPeriodKind.month ? 'Previous month' : 'Previous period of the same length', prev),
      if (p.sameMonthLastYear case final ly?) ('Same month last year', ly),
      if (p.kind == EfficiencyPeriodKind.financialYear)
        if (EfficiencyPeriod.previousYear(p.year!, _years) case final y?) ('Previous financial year', EfficiencyPeriod.financialYear(y)),
    ];
    if (pairs.isEmpty) return const Text('No earlier period to compare with.');
    final rows = [
      for (final (title, other) in pairs)
        ExpenseEfficiencyReport.compare(title: title, entries: _ledger!, assessments: _assessments!, current: p, other: other),
    ];
    String delta(double a, double b) => '${paiseOf(a - b) >= 0 ? '+' : ''}${efficiencyMoney(a - b)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _scroll(DataTable(
        key: const Key('efficiency-comparison-table'),
        columns: const [
          DataColumn(label: Text('Compared with')),
          DataColumn(label: Text('Income'), numeric: true),
          DataColumn(label: Text('Expenses'), numeric: true),
          DataColumn(label: Text('Surplus'), numeric: true),
          DataColumn(label: Text('Change in expenses'), numeric: true),
          DataColumn(label: Text('Data')),
        ],
        rows: [
          for (final c in rows)
            DataRow(cells: [
              DataCell(Text('${c.title}: ${c.otherLabel}')),
              DataCell(Text(efficiencyMoney(c.other.income))),
              DataCell(Text(efficiencyMoney(c.other.expenses))),
              DataCell(Text(efficiencyMoney(c.other.surplus))),
              DataCell(Text(delta(c.current.expenses, c.other.expenses))),
              DataCell(Text(c.incomplete ? 'Incomplete: no or partial records' : 'Complete')),
            ]),
        ],
      )),
      Text('Earlier figures come only from recorded ledger entries; nothing is estimated or filled in.', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _insights(ExpenseEfficiencyReport r) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Highest-spend categories: ${r.highestSpend.isEmpty ? 'none' : r.highestSpend.map((c) => '${c.name} ${efficiencyMoney(c.actual)}').join(', ')}'),
      Text('Most often assessed Waste / Avoidable: ${r.mostWaste.isEmpty ? 'none' : r.mostWaste.map((c) => '${c.name} (${c.wasteCount})').join(', ')}'),
      Text('Excessive with a recorded avoidable portion: ${r.excessiveWithAvoidable.length} '
          '(${efficiencyMoney(rupeesOf(r.excessiveWithAvoidable.fold(0, (s, i) => s + i.countedAvoidableP)))})'),
      Text('Recurring overspending (over target in 2+ months): ${r.recurringOverspend.isEmpty ? 'none' : r.recurringOverspend.map((c) => c.name).join(', ')}'),
      const SizedBox(height: 8),
      for (final (i, x) in r.insights.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(key: Key('efficiency-insight-$i'), crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Observation: ${x.observation}'),
            Text('Suggestion: ${x.suggestion}', style: small),
          ]),
        ),
      Text('Based only on recorded amounts and management\'s own assessments; nothing is classified automatically.', style: small),
    ]);
  }

  Widget _targetList() {
    final targets = _targets!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (targets.isEmpty) const Text('No targets yet. Categories without a target show "Target not set".'),
      for (final t in targets)
        ListTile(
          key: Key('efficiency-target-row-${t.id}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text('${t.categoryName.isEmpty ? t.categoryId : t.categoryName}: ${efficiencyMoney(t.monthlyAmount)} per month'),
          subtitle: Text('${t.monthsLabel} · ${t.isActive ? 'Active' : 'Inactive'}${t.note.isEmpty ? '' : ' · ${t.note}'}'),
          trailing: !_canEdit
              ? null
              : Wrap(children: [
                  IconButton(key: Key('efficiency-target-edit-${t.id}'), tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _editTarget(t)),
                  TextButton(key: Key('efficiency-target-toggle-${t.id}'), onPressed: () => _toggleTarget(t), child: Text(t.isActive ? 'Deactivate' : 'Activate')),
                ]),
        ),
      if (_canEdit)
        OutlinedButton.icon(key: const Key('efficiency-target-add'), onPressed: () => _editTarget(), icon: const Icon(Icons.add), label: const Text('Add Monthly Target')),
    ]);
  }

  Widget _expenseList(ExpenseEfficiencyReport r) {
    final items = r.items;
    final pages = (items.length / _pageSize).ceil();
    final page = _page.clamp(0, pages == 0 ? 0 : pages - 1);
    final shown = items.skip(page * _pageSize).take(_pageSize).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${items.length} expense(s) · ${efficiencyMoney(r.filteredExpenses)} · identified avoidable ${efficiencyMoney(r.filteredSavings)}',
          key: const Key('efficiency-expense-count')),
      if (items.isEmpty) const Text('No expenses match the selected period and filters.'),
      for (final i in shown)
        ListTile(
          key: Key('efficiency-expense-${i.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text(i.entry.title.isEmpty ? (i.entry.description.isEmpty ? 'Expense' : i.entry.description) : i.entry.title),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([
              i.entry.transactionDate == null ? 'No date' : DateFormat('d MMM yyyy').format(i.entry.transactionDate!),
              i.categoryName,
              efficiencyMoney(i.entry.amount),
            ].join(' · '), key: Key('efficiency-expense-text-${i.id}')),
            const SizedBox(height: 4),
            // The category as its pill; the avoidable amount and notes
            // beside it, never inside it.
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ExpenseCategoryPill(i.category, key: Key('efficiency-expense-pill-${i.id}')),
              if (i.cancelled) const Text('Cancelled: not counted'),
              if (i.category.hasAvoidable && !i.cancelled) Text('Avoidable ${efficiencyMoney(i.countedAvoidable)}', key: Key('efficiency-expense-avoidable-${i.id}')),
              if (i.needsReview) Text('Needs review', style: TextStyle(color: Colors.orange.shade900)),
              if ((i.assessment?.reason ?? '').isNotEmpty) Text(i.assessment!.reason),
            ]),
          ]),
          trailing: _canEdit && !i.cancelled
              ? TextButton(key: Key('efficiency-assess-${i.id}'), onPressed: () => _assess(i), child: Text(i.assessment == null ? 'Assess' : 'Edit'))
              : null,
        ),
      if (pages > 1)
        Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: page == 0 ? null : () => setState(() => _page = page - 1)),
          Text('Page ${page + 1} of $pages', key: const Key('efficiency-page')),
          IconButton(key: const Key('efficiency-page-next'), icon: const Icon(Icons.chevron_right), onPressed: page >= pages - 1 ? null : () => setState(() => _page = page + 1)),
        ]),
    ]);
  }

  Widget _reviewList(ExpenseEfficiencyReport r) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final i in r.needsReview)
          ListTile(
            key: Key('efficiency-needs-review-${i.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(i.entry.title.isEmpty ? i.id : i.entry.title),
            subtitle: Text(i.reviewReason ?? ''),
            trailing: _canEdit ? TextButton(onPressed: () => _assess(i), child: const Text('Review')) : null,
          ),
        for (final a in r.orphans)
          ListTile(
            key: Key('efficiency-orphan-${a.transactionId}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text('Assessment for a transaction no longer in the ledger (${a.transactionId})'),
            subtitle: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ExpenseCategoryPill(a.category),
              Text('${a.reason.isEmpty ? '' : '${a.reason}. '}Not counted anywhere; kept for review.'),
            ]),
            trailing: _canEdit
                ? TextButton(
                    key: Key('efficiency-orphan-remove-${a.transactionId}'),
                    onPressed: () => widget.service.deleteAssessment(requesterRole: _role, transactionId: a.transactionId),
                    child: const Text('Remove'),
                  )
                : null,
          ),
      ]);
}
