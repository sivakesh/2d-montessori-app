import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/monthly_bar_chart.dart';
import '../../admin/settings/models/academic_year_matching.dart';
import '../../admin/settings/models/academic_year_model.dart';
import '../../admin/settings/models/academic_year_months.dart';
import '../../admin/settings/models/school_settings_model.dart' show kDefaultSchoolId;
import '../../admin/settings/providers/academic_year_provider.dart';
import '../../admin/ui/admin_fab.dart';
import '../../admin/ui/admin_layout.dart';
import '../models/fee_due_date.dart';
import '../models/fee_list_filter.dart';
import '../models/fee_month.dart';
import '../models/fee_monthly_collections.dart';
import '../models/fee_overview.dart';
import '../models/fee_receipt_model.dart';
import '../models/fee_structure_model.dart';
import '../models/fee_student.dart';
import '../models/student_fee_assignment_model.dart';
import '../services/fee_service.dart';
import '../widgets/fee_filter_bar.dart';
import '../widgets/fee_summary_card.dart';
import 'dialogs/fee_assignment_dialog.dart';
import 'dialogs/fee_discount_apply_dialog.dart';
import 'dialogs/fee_due_backfill_dialog.dart';
import 'fee_reports_tab.dart';
import 'dialogs/fee_collection_details_dialog.dart';
import 'dialogs/fee_collection_dialog.dart';
import 'dialogs/fee_receipt_view_dialog.dart';
import 'dialogs/fee_structure_dialog.dart';
import 'dialogs/student_fee_history_dialog.dart';

/// Indian Rupee display formatting for the Fees Dashboard metric cards
/// (e.g. 173900 -> "₹1,73,900"). Display-only — never applied to a stored
/// or calculated value, only to the string shown on a card.
final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

String _formatCurrency(num? value) => _currencyFormat.format(value ?? 0);

class AdminFeesScreen extends ConsumerStatefulWidget {
  const AdminFeesScreen({super.key, FeeService? service, this.openReceiptId, this.clock = DateTime.now, this.exportPdf = sharePdfExporter})
      : _service = service;

  /// Saves a Reports PDF (tests capture it instead).
  final FeePdfExporter exportPdf;

  final FeeService? _service;

  /// Today, for Today's Collection (tests pass a fixed date).
  final DateTime Function() clock;

  /// Optional: a fee receipt (Fee Collection) to open on arrival, in the
  /// Receipts tab's own Edit Collection dialog — how Finance -> Ledger's
  /// "Open in Fees" reaches the collection behind a fee income entry.
  final String? openReceiptId;

  @override
  ConsumerState<AdminFeesScreen> createState() => _AdminFeesScreenState();
}

class _AdminFeesScreenState extends ConsumerState<AdminFeesScreen> {
  late final _service = widget._service ?? FeeService();
  // The tabs, in display order. Collections is the default.
  static const _collectionsTab = 0, _receiptsTab = 1, _duesTab = 2, _assignmentsTab = 3, _structuresTab = 4, _studentsTab = 5, _reportsTab = 6;
  static const _tabNames = ['Collections', 'Receipts', 'Dues', 'Assignments', 'Structures', 'Students', 'Reports'];

  /// Bumped on every load, so the Reports tab reads its records again.
  int _reloadToken = 0;
  int _tab = _collectionsTab;
  bool _loading = true;
  String? _deletingId;
  List<FeeStructureModel> _structures = [];
  List<StudentFeeAssignmentModel> _assignments = [];
  List<FeeReceiptModel> _receipts = [];
  List<FeeStudent> _students = [];
  Map<String, String> _classNames = {};
  List<AcademicYearModel> _years = [];

  // The shared filter, one state for every filtered tab (Assignments,
  // Collections, Receipts, Dues, Students), so it carries across tabs.
  // [_yearKey]: a year id or FeeFilterBar.allYears; set once on the first
  // load to the current academic year ([_defaultYearKey]).
  String _yearKey = FeeFilterBar.allYears;
  String _defaultYearKey = FeeFilterBar.allYears;
  bool _yearResolved = false;
  String? _classId;
  String? _studentId;

  /// Fee Month filter (`YYYY-MM`); null: All Months.
  String? _feeMonth;

  /// Monthly Fee Collection drill-down: the payment month (`YYYY-MM`) whose
  /// receipts the Receipts tab lists, by payment date; null: the normal
  /// Receipts list. [_tabBeforeDrill] is restored by Back to Fees Dashboard.
  String? _paymentMonth;
  int _tabBeforeDrill = _collectionsTab;
  final _chartKey = GlobalKey();
  final _tabsKey = GlobalKey();

  /// Independent UI page state for each list, kept here so it survives
  /// switching tabs and one list's paging never moves another's.
  final _pagers = {
    for (final list in _lists) list: _ListPager(),
  };

  /// Each list's own search text, kept here (like [_pagers]) so a query
  /// survives switching tabs and never affects another list.
  final _searches = {
    for (final list in _lists) list: TextEditingController(),
  };

  static const _lists = ['structures', 'assignments', 'collections', 'receipts', 'dues', 'students'];

  /// Rebuilds just after local midnight, so overdue labels and the
  /// Overdue Students card move to the new day while the screen is open.
  Timer? _midnight;

  void _scheduleMidnight() {
    final now = widget.clock();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _scheduleMidnight();
    });
  }

  @override
  void dispose() {
    _midnight?.cancel();
    for (final controller in _searches.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Searchable fields shared by the assignment-based lists (Assignments,
  /// Collections, Dues).
  static Iterable<String> _assignmentSearchFields(StudentFeeAssignmentModel a) =>
      [a.studentName, a.admissionNo, a.className, a.feeStructureName, a.academicYear, a.status, FeeMonth.label(a.feeMonth)];

  /// [a]'s fee month for its card: "January 2027"; for a Monthly structure's
  /// assignment made before months were recorded, "month not recorded";
  /// otherwise nothing.
  String _monthOf(StudentFeeAssignmentModel a) {
    if (a.feeMonth.isNotEmpty) return FeeMonth.label(a.feeMonth);
    final structure = _structures.where((s) => s.id == a.feeStructureId).firstOrNull;
    return structure != null && FeeMonth.isMonthlyStructure(structure) ? 'month not recorded' : '';
  }

  /// Opens [a]'s read-only Collection Details (its payment history). Writes
  /// nothing, so nothing is reloaded afterwards.
  Future<void> _openCollectionDetails(StudentFeeAssignmentModel a) {
    final structure = _structures.where((s) => s.id == a.feeStructureId).firstOrNull;
    return showDialog<void>(
      context: context,
      builder: (_) => FeeCollectionDetailsDialog(
        assignment: a,
        service: _service,
        isMonthlyStructure: structure != null && FeeMonth.isMonthlyStructure(structure),
        today: widget.clock(),
      ),
    );
  }

  /// "Due 5 Jan 2027", "Overdue • due 5 Jan 2027 • outstanding 500", or
  /// "Due date not set" (never inferred).

  /// "Fee 5000 • Student discount 500 (10%) • Manual discount 0", only for
  /// an assignment with a discount (others are shown as before).
  String? _discountLine(StudentFeeAssignmentModel a) {
    if ((a.discountAmount * 100).round() <= 0) return null;
    final snap = a.studentDiscount;
    return [
      'Fee: ${a.totalFee.toStringAsFixed(0)}',
      if (snap != null) 'Student discount: ${snap.label}',
      if (snap == null || (a.manualDiscountAmount * 100).round() > 0) 'Manual discount: ${a.manualDiscountAmount.toStringAsFixed(0)}',
    ].join(' • ');
  }

  String _dueLine(StudentFeeAssignmentModel a) {
    final due = a.dueDate;
    if (due == null) return 'Due date not set';
    return FeeDueDate.isOverdue(a, widget.clock())
        ? 'Overdue • due ${FeeDueDate.label(due)} • outstanding ${a.balanceAmount.toStringAsFixed(0)}'
        : 'Due ${FeeDueDate.label(due)}';
  }

  bool _hasBalance(StudentFeeAssignmentModel a) => (a.balanceAmount * 100).round() > 0;

  /// Paid / Partially Paid / Unpaid, from the recorded amounts, and Overdue
  /// where it applies.
  Widget _statusBadges(StudentFeeAssignmentModel a) {
    final (label, color) = !_hasBalance(a)
        ? ('Paid', Colors.green)
        : (a.paidAmount * 100).round() > 0
            ? ('Partially Paid', Colors.orange)
            : ('Unpaid', Colors.blueGrey);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        Container(
          key: Key('fees-status-${a.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color.shade800)),
        ),
        ?_overdueBadge(a),
      ],
    );
  }

  /// A red "Overdue" label for an overdue assignment's card.
  Widget? _overdueBadge(StudentFeeAssignmentModel a) => FeeDueDate.isOverdue(a, widget.clock())
      ? Container(
          key: Key('fees-overdue-${a.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20)),
          child: Text('Overdue', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade800)),
        )
      : null;

  String _withMonth(String text, StudentFeeAssignmentModel a) => switch (_monthOf(a)) { '' => text, final m => '$text • $m' };

  @override
  void initState() {
    super.initState();
    _scheduleMidnight();
    _load();
  }

  Future<void> _load() async {
    final structures = await _service.getFeeStructures();
    final assignments = await _service.getAssignments();
    final receipts = await _service.getReceipts();
    final students = await _service.getStudents();
    final classNames = await _service.getClassNames();
    final years = _yearResolved ? _years : await _loadYears();
    if (!mounted) return;
    setState(() {
      _reloadToken++;
      _structures = structures;
      _assignments = assignments;
      _receipts = receipts;
      _students = students;
      _classNames = classNames;
      if (!_yearResolved) {
        _years = years;
        _defaultYearKey = years.where((y) => y.isCurrent).firstOrNull?.id ?? FeeFilterBar.allYears;
        _yearKey = _defaultYearKey;
        _yearResolved = true;
      }
      _loading = false;
    });
    final requested = widget.openReceiptId;
    if (requested != null && !_openedRequested) {
      _openedRequested = true;
      _openRequestedReceipt(requested);
    }
  }

  bool _openedRequested = false;

  /// The school's academic years, through the app's shared academic-year
  /// service (the one Settings uses; `isCurrent` marks the current year).
  /// None, or a read failure, leaves the filter on All Academic Years.
  Future<List<AcademicYearModel>> _loadYears() async {
    try {
      return await ref.read(academicYearServiceProvider).getAllAcademicYears(schoolId: kDefaultSchoolId);
    } catch (_) {
      return const [];
    }
  }

  AcademicYearModel? get _selectedYear => _years.where((y) => y.id == _yearKey).firstOrNull;

  FeeListFilter get _filter =>
      FeeListFilter(year: _selectedYear, classId: _classId, studentId: _studentId, feeMonth: _feeMonth, monthlyStructureIds: _monthlyStructureIds);

  bool get _filtersAtDefault => _yearKey == _defaultYearKey && _classId == null && _studentId == null && _feeMonth == null;

  /// Fee Month options: the months recorded on the assignments of the
  /// selected academic year, in order.
  List<String> get _monthOptions {
    final year = FeeListFilter(year: _selectedYear);
    return {for (final a in _assignments) if (a.feeMonth.isNotEmpty && year.assignmentInYear(a)) a.feeMonth}.toList()..sort();
  }

  String get _currentFeeMonth {
    final now = widget.clock();
    return FeeMonth.of(now.year, now.month);
  }

  // Section keys for assignments without a month, and receipts without an
  // assignment (FeeMonth values are YYYY-MM, so these never clash).
  static const _notMonthlySection = '~1-not-monthly', _unlinkedSection = '~2-unlinked', _noMonthSection = '~3-no-month';

  // Lookups rebuilt only when _load replaces the lists.
  List<FeeStructureModel>? _monthlyFor;
  Set<String> _monthlyIds = const {};
  List<StudentFeeAssignmentModel>? _byIdFor;
  Map<String, StudentFeeAssignmentModel> _byId = const {};

  Map<String, StudentFeeAssignmentModel> get _assignmentsById {
    if (!identical(_byIdFor, _assignments)) {
      _byIdFor = _assignments;
      _byId = {for (final a in _assignments) a.id: a};
    }
    return _byId;
  }

  /// The ids of the Monthly structures (FeeMonth.isMonthlyStructure).
  Set<String> get _monthlyStructureIds {
    if (!identical(_monthlyFor, _structures)) {
      _monthlyFor = _structures;
      _monthlyIds = {for (final s in _structures) if (FeeMonth.isMonthlyStructure(s)) s.id};
    }
    return _monthlyIds;
  }

  bool _isMonthlyAssignment(StudentFeeAssignmentModel a) => _monthlyStructureIds.contains(a.feeStructureId);

  /// [a]'s month section: its stored fee month; an older Monthly one with
  /// none is "Month not recorded"; other structures are not monthly.
  String _sectionOfAssignment(StudentFeeAssignmentModel a) =>
      a.feeMonth.isNotEmpty ? a.feeMonth : (_isMonthlyAssignment(a) ? _noMonthSection : _notMonthlySection);

  /// The section order: the selected month, then Term and One-time Fees
  /// (never hidden by a month); or, for All Months, the current month
  /// first (always), every other month in date order, Term and One-time
  /// Fees, receipts with no assignment, and Month not recorded last.
  List<String> _sectionOrder(Iterable<String> present) {
    final month = _feeMonth;
    if (month != null) return [month, _notMonthlySection];
    final current = _currentFeeMonth;
    final months = {for (final k in present) if (!k.startsWith('~') && k != current) k}.toList()..sort();
    return [current, ...months, _notMonthlySection, _unlinkedSection, _noMonthSection];
  }

  String _sectionTitle(String key) => switch (key) {
        _notMonthlySection => 'Term and One-time Fees',
        _unlinkedSection => 'Not linked to a fee assignment',
        _noMonthSection => 'Month not recorded',
        _ when key == _feeMonth => '${FeeMonth.label(key)} – Selected Month',
        _ when key == _currentFeeMonth => '${FeeMonth.label(key)} – Current Month',
        _ => FeeMonth.label(key),
      };

  /// Applies a filter change and returns every list to its first page.
  void _changeFilter(VoidCallback change) {
    setState(() {
      change();
      for (final pager in _pagers.values) {
        pager.page = 0;
      }
    });
  }

  /// Class filter options: every class, plus any class an assignment was
  /// made under that is no longer in `classes` (by its stored name).
  Map<String, String> get _classOptions {
    final options = {..._classNames};
    for (final a in _assignments) {
      if (a.classId.isNotEmpty) options.putIfAbsent(a.classId, () => a.className);
    }
    final ids = options.keys.toList()..sort((x, y) => options[x]!.toLowerCase().compareTo(options[y]!.toLowerCase()));
    return {for (final id in ids) id: options[id]!};
  }

  /// Student filter options, narrowed to the class when one is chosen:
  /// every student record, plus any student an assignment names who is no
  /// longer in `students` (by stored id and name).
  List<FeeStudent> get _studentOptions {
    final classId = _classId;
    final all = _allStudentOptions;
    return classId == null ? all : all.where((s) => studentInClass(s.id, s.classId, classId, _assignments)).toList();
  }

  List<FeeStudent> get _allStudentOptions {
    final known = {for (final s in _students) s.id};
    final extra = <String, FeeStudent>{};
    for (final a in _assignments) {
      if (a.studentId.isNotEmpty && !known.contains(a.studentId)) {
        extra.putIfAbsent(a.studentId, () => FeeStudent(id: a.studentId, name: a.studentName, admissionNo: a.admissionNo, classId: a.classId));
      }
    }
    return [..._students, ...extra.values];
  }

  void _onClassChanged(String? classId) => _changeFilter(() {
        _classId = classId;
        final studentId = _studentId;
        if (classId != null && studentId != null) {
          final s = _allStudentOptions.where((s) => s.id == studentId).firstOrNull;
          if (!studentInClass(studentId, s?.classId ?? '', classId, _assignments)) _studentId = null;
        }
      });

  /// "2026-2027 • Mont 1 • Anu (ADM-1)": what the filters select.
  String get _scopeLabel {
    final student = _studentId == null ? null : _allStudentOptions.where((s) => s.id == _studentId).firstOrNull;
    return [
      _selectedYear?.name ?? 'All academic years',
      _classId == null ? 'All classes' : (_classOptions[_classId] ?? 'Unknown class'),
      student == null ? 'All students' : (student.admissionNo.isEmpty ? student.name : '${student.name} (${student.admissionNo})'),
      _feeMonth == null ? 'All months' : FeeMonth.label(_feeMonth!),
    ].join(' • ');
  }

  /// The overview cards for the filters (FeeOverview: same definitions as
  /// before; with no filter, the same figures).
  Widget _buildOverview() {
    final today = widget.clock();
    final o = FeeOverview.of(assignments: _assignments, receipts: _receipts, filter: _filter, today: today);
    final todayScope = [
      DateFormat('MMM d, yyyy').format(today),
      if (_selectedYear != null) 'any academic year',
    ].join(' • ');
    return Column(
      key: const Key('fees-overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricSection(
          title: 'Collection Overview',
          caption: 'Fee assignments: $_scopeLabel',
          captionKey: const Key('fees-overview-scope'),
          cards: [
            FeeSummaryCard(key: const Key('fees-overview-expected'), label: 'Total Expected', value: _formatCurrency(o.totalExpected), icon: Icons.receipt_long),
            FeeSummaryCard(key: const Key('fees-overview-collected'), label: 'Total Collected', value: _formatCurrency(o.totalCollected), icon: Icons.payments),
            FeeSummaryCard(
              key: const Key('fees-overview-outstanding'),
              label: 'Outstanding',
              value: _formatCurrency(o.outstanding),
              icon: Icons.warning,
              color: Colors.orange,
            ),
            FeeSummaryCard(
              key: const Key('fees-overview-percent'),
              label: 'Collection %',
              value: '${o.collectionPercent.toStringAsFixed(1)}%',
              icon: Icons.show_chart,
              subtitle: 'Collected ÷ expected, same assignments',
            ),
          ],
        ),
        const SizedBox(height: 24),
        _MetricSection(
          title: 'Activity & Attention',
          caption: 'As of ${DateFormat('MMM d, yyyy').format(today)}',
          cards: [
            FeeSummaryCard(
              key: const Key('fees-overview-overdue'),
              label: 'Overdue Students',
              value: '${o.overdue}',
              icon: Icons.schedule,
              color: Colors.red,
              subtitle: 'Distinct students with an overdue balance',
            ),
            FeeSummaryCard(
              key: const Key('fees-overview-today'),
              label: 'Today\'s Collection',
              value: _formatCurrency(o.todayCollection),
              icon: Icons.today,
              subtitle: todayScope,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildCollectionChart(),
      ],
    );
  }

  /// The current academic year (Settings), for the monthly chart.
  AcademicYearModel? get _currentYear => _years.where((y) => y.isCurrent).firstOrNull;

  /// Payments received each month of the current academic year, through
  /// today; null without a current year.
  FeeMonthlyCollections? get _monthlyCollections =>
      _currentYear == null ? null : FeeMonthlyCollections.of(_receipts, AcademicYearMonths(_currentYear!, widget.clock()));

  void _openPaymentMonth(String month) {
    setState(() {
      if (_paymentMonth == null) _tabBeforeDrill = _tab;
      _paymentMonth = month;
      _tab = _receiptsTab;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _tabsKey.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250));
    });
  }

  void _closePaymentMonth() {
    setState(() {
      _paymentMonth = null;
      _tab = _tabBeforeDrill;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _chartKey.currentContext;
      if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 250));
    });
  }

  /// Fees Dashboard → Monthly Fee Collection: one bar per month, by payment
  /// date; a bar opens that month's receipts.
  Widget _buildCollectionChart() {
    final year = _currentYear;
    final small = TextStyle(fontSize: 12, color: Colors.grey.shade700);
    Widget frame(List<Widget> children) => Container(
          key: _chartKey,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withValues(alpha: 0.06))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly Fee Collection', style: Theme.of(context).textTheme.titleMedium),
            ...children,
          ]),
        );
    if (year == null) {
      return frame([Text('No current academic year is set in Settings, so the monthly chart can\'t be shown.', key: const Key('fees-chart-no-year'), style: small)]);
    }
    final c = _monthlyCollections!;
    if (c.window.notStarted) {
      return frame([Text('The academic year ${year.name} starts on ${DateFormat('d MMM yyyy').format(c.window.start)}.', key: const Key('fees-chart-not-started'), style: small)]);
    }
    final months = c.months;
    return frame([
      Text(
        'Payments received in ${year.name}, by payment date, through ${DateFormat('d MMM yyyy').format(c.window.end)}. '
        'All payment methods; voided receipts excluded. Not affected by the filters above.',
        key: const Key('fees-chart-caption'),
        style: small,
      ),
      const SizedBox(height: 12),
      MonthlyBarChart(
        key: const Key('fees-chart'),
        months: months,
        monthLabels: [for (final m in months) _chartMonthLabel(m, months)],
        series: [
          MonthlyChartSeries(label: 'Collected', color: MonthlyBarChart.moneyInColor, values: [for (final m in months) c.totalIn(m)], keyPrefix: 'fees-chart-bar'),
        ],
        onBarTap: (_, m) => _openPaymentMonth(m),
      ),
      Text(
        c.isEmpty
            ? 'No payments recorded yet this academic year.'
            : 'Total ${_formatCurrency(c.total)} · select a month to see its payments.',
        key: const Key('fees-chart-total'),
        style: small,
      ),
      if (c.undated > 0) Text('${c.undated} receipt(s) have no payment date and are not in any month.', style: small),
    ]);
  }

  static String _chartMonthLabel(String m, List<String> months) {
    final d = AcademicYearMonths.monthStart(m);
    return m == months.first || d.month == 1 ? '${AcademicYearMonths.shortLabel(m)}\n${d.year}' : AcademicYearMonths.shortLabel(m);
  }

  /// The shared filters as the Reports headings and PDFs show them.
  List<String> get _reportFilterLabels => [
        'Academic Year: ${_selectedYear?.name ?? 'All Academic Years'}',
        'Class: ${_classId == null ? 'All Classes' : (_classNames[_classId] ?? _classId)}',
        if (_studentId != null) 'Student: ${_allStudentOptions.where((s) => s.id == _studentId).firstOrNull?.name ?? _studentId}',
        'Fee Month: ${_feeMonth == null ? 'All Months' : FeeMonth.label(_feeMonth!)}',
      ];

  /// What the filters mean on the current tab.
  String get _filterScopeNote => switch (_tab) {
        _reportsTab => 'Reports list every student matching the filters (by current class), with all their fees for the Academic Year and Fee Month, '
            'whether paid or not. Fee Month is the month a fee is for; payment dates are shown separately.',
        _structuresTab => 'Filters apply to the overview and to Collections, Receipts, Dues, Assignments and Students. Fee structures are not filtered.',
        _studentsTab => 'Class is each student’s current class. Academic Year chooses which year’s fees are summarised here and shown in each fee history; '
            'Fee Month does not filter this list.',
        _ => 'Class is the class recorded on each fee assignment, which may differ from the student’s current class. '
            'Fee Month is the month each fee is for (not when it was paid). Receipts follow their linked assignment.',
      };

  Widget _buildFilterBar() {
    final options = _studentOptions;
    final selected = _studentId == null ? null : options.where((s) => s.id == _studentId).firstOrNull;
    return FeeFilterBar(
      scopeNote: _filterScopeNote,
      years: _years,
      yearKey: _yearKey,
      classes: _classOptions,
      classId: _classId,
      students: options,
      selectedStudent: selected,
      isDefault: _filtersAtDefault,
      months: _monthOptions,
      feeMonth: _feeMonth,
      onMonthChanged: (m) => _changeFilter(() => _feeMonth = m),
      onYearChanged: (key) => _changeFilter(() {
            _yearKey = key;
            // A month the new year has no assignments for is cleared.
            if (_feeMonth != null && !_monthOptions.contains(_feeMonth)) _feeMonth = null;
          }),
      onClassChanged: _onClassChanged,
      onStudentChanged: (id) => _changeFilter(() => _studentId = id),
      onReset: _resetFilters,
    );
  }

  /// Back to the current academic year, All Classes, All Students, All
  /// Months.
  void _resetFilters() => _changeFilter(() {
        _yearKey = _defaultYearKey;
        _classId = null;
        _studentId = null;
        _feeMonth = null;
      });

  /// Shows the Receipts tab and opens [receiptId]'s Edit Collection dialog
  /// (the same as its Edit action there), or says why it can't.
  Future<void> _openRequestedReceipt(String receiptId) async {
    setState(() => _tab = _receiptsTab);
    final receipt = await _service.getReceiptById(receiptId);
    if (!mounted) return;
    if (receipt == null || !_receipts.any((r) => r.id == receiptId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The fee collection for this transaction could not be found, or it has been voided.')),
      );
      return;
    }
    await _openEditCollection(receipt);
  }

  Future<void> _openStructure({FeeStructureModel? structure}) async {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => FeeStructureDialog(structure: structure, service: _service));
    await _load();
  }

  Future<void> _openAssignment({StudentFeeAssignmentModel? assignment}) async {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => FeeAssignmentDialog(assignment: assignment, service: _service));
    await _load();
  }

  Future<void> _openCollection(StudentFeeAssignmentModel assignment, {FeeReceiptModel? receipt}) async {
    await showDialog(context: context, barrierDismissible: false, builder: (_) => FeeCollectionDialog(assignment: assignment, receipt: receipt, service: _service));
    await _load();
  }

  /// Opens the Edit Collection dialog for [receipt] — looks up its parent
  /// assignment first (FeeCollectionDialog requires one for balance
  /// context), scoped to only that one assignment by id.
  Future<void> _openEditCollection(FeeReceiptModel receipt) async {
    final assignment = await _service.getAssignmentById(receipt.assignmentId);
    if (assignment == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find the assignment for this collection.')),
        );
      }
      return;
    }
    await _openCollection(assignment, receipt: receipt);
  }

  Future<void> _openPdf(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _deleteStructure(FeeStructureModel structure) async {
    if (!await _confirmDelete()) return;
    setState(() => _deletingId = structure.id);
    try {
      await _service.deleteFeeStructure(structure.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Structure deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete structure: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  Future<void> _deleteAssignment(StudentFeeAssignmentModel assignment) async {
    if (!await _confirmDelete()) return;
    setState(() => _deletingId = assignment.id);
    try {
      await _service.deleteAssignment(assignment.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete assignment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  /// Void-specific confirmation, distinct from the generic [_confirmDelete]
  /// used elsewhere in this screen: explains the actual effect (balance
  /// recalculated, record preserved) rather than the generic destructive
  /// "cannot be undone" wording, since voiding a payment is not the same
  /// operation as deleting a structure/assignment.
  Future<bool> _confirmVoid(FeeReceiptModel receipt) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void Payment'),
        content: Text(
          'Void the payment of ₹${receipt.amount.toStringAsFixed(0)} for '
          '${receipt.studentName}? This will remove it from the collected '
          'total and add ₹${receipt.amount.toStringAsFixed(0)} back to the '
          "assignment's outstanding balance. The original payment record is "
          'preserved for audit — it will no longer count as a valid payment, '
          'but is not permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _voidReceipt(FeeReceiptModel receipt) async {
    if (!await _confirmVoid(receipt)) return;
    setState(() => _deletingId = receipt.id);
    try {
      await _service.voidReceipt(receipt.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment voided')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to void payment: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 6,
      title: 'Fees',
      floatingActionButton: AdminFab(
        icon: Icons.add,
        onPressed: () {
          if (_tab == _structuresTab) {
            _openStructure();
          } else if (_tab == _assignmentsTab) {
            _openAssignment();
          } else if (_tab == _collectionsTab) {
            // The first collection the filters show.
            final first = _assignments.where((a) => a.balanceAmount > 0 && _filter.matchesAssignment(a)).firstOrNull;
            if (first != null) _openCollection(first);
          }
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fees', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  _buildFilterBar(),
                  _buildOverview(),
                  const SizedBox(height: 24),
                  Wrap(
                    key: _tabsKey,
                    spacing: 8,
                    runSpacing: 8,
                    children: _tabNames.asMap().entries.map((e) {
                      return ChoiceChip(
                        label: Text(e.value),
                        selected: _tab == e.key,
                        onSelected: (_) => setState(() {
                          _tab = e.key;
                          _paymentMonth = null;
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  _buildTab(),
                  // Reserves clearance so the last row can scroll
                  // fully clear of the floating "Add" FAB.
                  const SizedBox(height: 24 + AppSizes.fabScrollClearance),
                ],
              ),
            ),
    );
  }

  Widget _buildTab() {
    return switch (_tab) {
      _structuresTab => _buildStructures(),
      _assignmentsTab => _buildAssignments(),
      _collectionsTab => _buildCollections(),
      _receiptsTab => _buildReceipts(),
      _studentsTab => _buildStudents(),
      _duesTab => _buildDues(),
      _reportsTab => FeeReportsTab(
          service: _service,
          filter: _filter,
          students: _students,
          classNames: _classNames,
          filterLabels: _reportFilterLabels,
          reloadToken: _reloadToken,
          exportPdf: widget.exportPdf,
          clock: widget.clock,
        ),
      _ => _buildCollections(),
    };
  }

  Widget _buildStructures() {
    // FEES-AY-IMPLEMENT-01: loaded once per build (not per row) via the
    // same shared academicYearsProvider every other Academic-Year-aware
    // screen already reads, so resolving each Structure's display label
    // never issues a per-row Firestore query.
    final academicYearNamesById = <String, String>{
      for (final year in ref.watch(academicYearsProvider).valueOrNull ?? const [])
        year.id: year.name,
    };
    return _pagedList<FeeStructureModel>(
        list: 'structures',
        items: _structures,
        idOf: (s) => s.id,
        hint: 'Search name, description, academic year or frequency',
        noun: 'fee structures',
        searchFieldsOf: (s) => [
          s.name,
          s.description,
          s.academicYear,
          resolveClassAcademicYearLabel(
            academicYearId: s.academicYearId,
            academicYear: s.academicYear,
            academicYearNamesById: academicYearNamesById,
          ),
          for (final c in s.components) c.frequency,
        ],
        itemBuilder: (s) {
          final frequencySummary = s.components.isEmpty
              ? 'No components'
              : s.components.map((c) => c.frequency).toSet().join(', ');
          final resolvedAcademicYear = resolveClassAcademicYearLabel(
            academicYearId: s.academicYearId,
            academicYear: s.academicYear,
            academicYearNamesById: academicYearNamesById,
          );
          final academicYearLabel = resolvedAcademicYear.isNotEmpty
              ? resolvedAcademicYear
              : (s.academicYearId.isNotEmpty ? 'Unresolved' : '-');
          return _FeeListCard(
            icon: Icons.receipt_long_outlined,
            title: s.name,
            subtitleLines: ['$academicYearLabel • ${s.components.length} components • $frequencySummary'],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _openStructure(structure: s),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: _deletingId == s.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: _deletingId == s.id ? null : () => _deleteStructure(s),
                ),
              ],
            ),
          );
        },
      );
  }

  /// Set Missing Due Dates (admins only, like the rest of Fees): a
  /// read-only preview first; nothing is written until confirmed there.
  Future<void> _openDueBackfill() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FeeDueBackfillDialog(
        service: _service,
        onEdit: (a) async {
          // The stored record, not the preview's copy.
          final current = await _service.getAssignmentById(a.id);
          if (current == null || !mounted) return;
          await showDialog(context: context, barrierDismissible: false, builder: (_) => FeeAssignmentDialog(assignment: current, service: _service));
        },
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _openDiscountApply() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FeeDiscountApplyDialog(service: _service),
    );
    if (saved == true) await _load();
  }

  Widget _buildAssignments() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(FeeDueBackfillDialog.explanation, key: Key('fees-due-backfill-explanation')),
                  OutlinedButton.icon(
                    key: const Key('fees-set-missing-due-dates'),
                    onPressed: _openDueBackfill,
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('Set Missing Due Dates'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(FeeDiscountApplyDialog.explanation, key: Key('fees-discount-apply-explanation')),
                  OutlinedButton.icon(
                    key: const Key('fees-apply-student-discounts'),
                    onPressed: _openDiscountApply,
                    icon: const Icon(Icons.percent),
                    label: const Text(FeeDiscountApplyDialog.title),
                  ),
                ],
              ),
            ),
          ),
          _buildAssignmentList(),
        ],
      );

  Widget _buildAssignmentList() => _pagedList<StudentFeeAssignmentModel>(
        list: 'assignments',
        sectionOf: _sectionOfAssignment,
        items: _assignments.where(_filter.matchesAssignment).toList(),
        sourceCount: _assignments.length,
        idOf: (a) => a.id,
        hint: 'Search student, admission no., class, structure, year or status',
        noun: 'assignments',
        searchFieldsOf: _assignmentSearchFields,
        itemBuilder: (a) {
          return _FeeListCard(
            icon: Icons.assignment_outlined,
            title: a.studentName,
            badge: _overdueBadge(a),
            subtitleLines: [
              _withMonth('${a.className} • ${a.feeStructureName}', a),
              'Balance: ${a.balanceAmount.toStringAsFixed(0)}',
              _dueLine(a),
            ],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _openAssignment(assignment: a),
                ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: _deletingId == a.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: _deletingId == a.id ? null : () => _deleteAssignment(a),
                ),
              ],
            ),
          );
        },
      );

  // Filtered once per build (previously re-filtered for every row), then
  // sliced to the current page.
  Widget _buildCollections() => _pagedList<StudentFeeAssignmentModel>(
        list: 'collections',
        sectionOf: _sectionOfAssignment,
        // Every assignment, paid ones included (they stay reachable for
        // View Details); Collect is offered only while a balance is due.
        items: _assignments.where(_filter.matchesAssignment).toList(),
        sourceCount: _assignments.length,
        idOf: (a) => a.id,
        hint: 'Search student, admission no., class, structure, year or status',
        noun: 'collections',
        searchFieldsOf: _assignmentSearchFields,
        itemBuilder: (a) {
          return _FeeListCard(
            icon: Icons.payments_outlined,
            title: a.studentName,
            badge: _statusBadges(a),
            subtitleLines: [
              '${a.admissionNo} • ${a.className}',
              _withMonth(a.feeStructureName, a),
              ?_discountLine(a),
              'Payable: ${a.payableAmount.toStringAsFixed(0)} • Paid: ${a.paidAmount.toStringAsFixed(0)} • Balance: ${a.balanceAmount.toStringAsFixed(0)}',
              _dueLine(a),
            ],
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A labelled button where there's room; on a phone, an
                // icon button with the same name (tooltip and semantics).
                if (MediaQuery.sizeOf(context).width >= AppSizes.mobileBreakpoint)
                  TextButton.icon(
                    key: Key('collection-view-details-${a.id}'),
                    onPressed: () => _openCollectionDetails(a),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('View Details'),
                  )
                else
                  IconButton(
                    key: Key('collection-view-details-${a.id}'),
                    tooltip: 'View Details',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    onPressed: () => _openCollectionDetails(a),
                  ),
                if (_hasBalance(a))
                  TextButton(
                    key: Key('collection-collect-${a.id}'),
                    onPressed: () => _openCollection(a),
                    child: const Text('Collect'),
                  ),
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: _deletingId == a.id
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: _deletingId == a.id ? null : () => _deleteAssignment(a),
                ),
              ],
            ),
          );
        },
      );

  /// Receipts matching the filter through their linked assignment.
  List<FeeReceiptModel> get _filteredReceipts {
    final byId = {for (final a in _assignments) a.id: a};
    final filter = _filter;
    return [for (final r in _receipts) if (filter.matchesReceipt(r, byId[r.assignmentId])) r];
  }

  Future<void> _openStudentHistory(FeeStudent student) => showDialog<void>(
        context: context,
        builder: (_) => StudentFeeHistoryDialog(
          student: student,
          className: _classNames[student.classId] ?? '',
          year: _selectedYear,
          service: _service,
          structures: _structures,
          today: widget.clock(),
        ),
      );

  /// Every student record, filtered by current class and student; the
  /// selected year's fees for each come from the assignments already
  /// loaded (no per-student reads). The full history loads on opening.
  Widget _buildStudents() {
    final filter = _filter;
    final year = _selectedYear;
    final yearLabel = year?.name ?? 'all years';
    final assignmentsByStudent = <String, List<StudentFeeAssignmentModel>>{};
    for (final a in _assignments) {
      if (filter.assignmentInYear(a)) (assignmentsByStudent[a.studentId] ??= []).add(a);
    }
    final narrow = MediaQuery.sizeOf(context).width < AppSizes.mobileBreakpoint;
    return _pagedList<FeeStudent>(
      list: 'students',
      items: _students.where(filter.matchesStudent).toList(),
      sourceCount: _students.length,
      idOf: (s) => s.id,
      hint: 'Search student name or admission no.',
      noun: 'students',
      searchFieldsOf: (s) => [s.name, s.admissionNo],
      itemBuilder: (s) {
        final mine = assignmentsByStudent[s.id] ?? const [];
        final outstanding = mine.fold<double>(0, (sum, a) => sum + a.balanceAmount);
        final className = _classNames[s.classId] ?? '';
        return _FeeListCard(
          icon: Icons.person_outline,
          title: s.name.isEmpty ? '(no name)' : s.name,
          subtitleLines: [
            [if (s.admissionNo.isNotEmpty) s.admissionNo, className.isEmpty ? 'No class' : className, if (!s.isActive) 'Inactive'].join(' • '),
            mine.isEmpty
                ? 'No fee assignments in $yearLabel'
                : '${mine.length} fee ${mine.length == 1 ? 'assignment' : 'assignments'} in $yearLabel • Outstanding: ${outstanding.toStringAsFixed(0)}',
          ],
          trailing: narrow
              ? IconButton(
                  key: Key('student-view-history-${s.id}'),
                  tooltip: 'View Fee History',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.history, size: 20),
                  onPressed: () => _openStudentHistory(s),
                )
              : TextButton.icon(
                  key: Key('student-view-history-${s.id}'),
                  onPressed: () => _openStudentHistory(s),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('View Fee History'),
                ),
        );
      },
    );
  }

  Widget _buildReceipts() {
    if (_paymentMonth case final month?) return _buildPaymentMonthReceipts(month);
    final byId = {for (final a in _assignments) a.id: a};
    final unlinked = _receipts.where((r) => !byId.containsKey(r.assignmentId)).length;
    final placed = _selectedYear == null && _classId == null && _feeMonth == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (unlinked > 0 && !placed)
          Padding(
            key: const Key('fees-receipts-unlinked'),
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '$unlinked ${unlinked == 1 ? 'receipt is' : 'receipts are'} not linked to a current fee assignment, so '
              '${unlinked == 1 ? 'it has' : 'they have'} no academic year or class and ${unlinked == 1 ? 'appears' : 'appear'} '
              'only under All Academic Years, All Classes and All Months.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
            ),
          ),
        _buildReceiptList(),
      ],
    );
  }

  /// Monthly Fee Collection drill-down: the receipts paid in [month] (the
  /// chart's own list, so the total always matches its bar), in the normal
  /// receipt cards with their usual actions.
  Widget _buildPaymentMonthReceipts(String month) {
    final c = _monthlyCollections;
    final list = c?.receiptsIn(month) ?? const <FeeReceiptModel>[];
    final partial = c != null && c.window.isPartial(month);
    final small = TextStyle(fontSize: 12, color: Colors.grey.shade700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: const Key('fees-payment-month-banner'),
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Payments received in ${AcademicYearMonths.label(month)}', key: const Key('fees-payment-month-title'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${list.length} ${list.length == 1 ? 'payment' : 'payments'} · ${_formatCurrency(c?.totalIn(month) ?? 0)}',
                key: const Key('fees-payment-month-total')),
            Text(
              'By payment date${partial ? ' (${DateFormat('d MMM').format(c.window.daysOf(month).$1)}–${DateFormat('d MMM yyyy').format(c.window.daysOf(month).$2)})' : ''}; '
              'all payment methods; voided receipts excluded. Fee Month (what each fee is for) is shown separately on each payment. '
              'The filters above don\'t apply to this list.',
              style: small,
            ),
            TextButton.icon(
              key: const Key('fees-payment-month-back'),
              onPressed: _closePaymentMonth,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to Fees Dashboard'),
            ),
          ]),
        ),
        _buildReceiptList(only: list),
      ],
    );
  }

  /// [only]: a fixed list (the payment-month drill-down), shown by payment
  /// date with each payment's date, method and reference; otherwise the
  /// filtered receipts in fee-month sections, as before.
  Widget _buildReceiptList({List<FeeReceiptModel>? only}) => _pagedList<FeeReceiptModel>(
        list: 'receipts',
        // A receipt's month is its linked assignment's (never its payment
        // date); one with no assignment to go by has none.
        sectionOf: only != null
            ? null
            : (r) => switch (_assignmentsById[r.assignmentId]) {
                  final a? => _sectionOfAssignment(a),
                  null => _unlinkedSection,
                },
        items: only ?? _filteredReceipts,
        sourceCount: only?.length ?? _receipts.length,
        idOf: (r) => r.id,
        hint: 'Search receipt no., student, admission no., structure, mode or reference',
        noun: 'receipts',
        searchFieldsOf: (r) => [r.receiptNo, r.studentName, r.admissionNo, r.className, r.feeStructureName, r.paymentMode, r.referenceNo, FeeMonth.label(r.feeMonth)],
        itemBuilder: (r) {
          return _FeeListCard(
            icon: Icons.description_outlined,
            title: r.receiptNo,
            subtitleLines: [
              '${r.studentName} • ${r.admissionNo} • ${r.className}',
              '${r.feeStructureName}${r.feeMonth.isEmpty ? '' : ' • ${FeeMonth.label(r.feeMonth)}'} • ${r.amount.toStringAsFixed(0)} • ${r.paymentMode}',
              if (only != null)
                'Paid ${r.paymentDate == null ? '-' : DateFormat('d MMM yyyy').format(r.paymentDate!)} • '
                    '${r.feeMonth.isEmpty ? 'Fee month not recorded' : 'Fee month ${FeeMonth.label(r.feeMonth)}'}'
                    '${r.referenceNo.isEmpty ? '' : ' • Ref ${r.referenceNo}'}',
            ],
            trailing: PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (value) {
                switch (value) {
                  case 'view':
                    showDialog(context: context, builder: (_) => FeeReceiptViewDialog(receipt: r));
                    break;
                  case 'edit':
                    _openEditCollection(r);
                    break;
                  case 'open_pdf':
                    _openPdf(r.pdfUrl);
                    break;
                  case 'generate_pdf':
                    showDialog(context: context, builder: (_) => FeeReceiptViewDialog(receipt: r));
                    break;
                  case 'void':
                    _voidReceipt(r);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(leading: Icon(Icons.visibility_outlined), title: Text('View'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), contentPadding: EdgeInsets.zero),
                ),
                PopupMenuItem(
                  value: 'open_pdf',
                  enabled: r.pdfUrl.isNotEmpty,
                  child: const ListTile(leading: Icon(Icons.open_in_new), title: Text('Open PDF'), contentPadding: EdgeInsets.zero),
                ),
                PopupMenuItem(
                  value: 'generate_pdf',
                  enabled: r.pdfUrl.isEmpty,
                  child: const ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Generate PDF'), contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'void',
                  child: ListTile(
                    leading: Icon(Icons.block, color: Colors.red),
                    title: Text('Void', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          );
        },
      );

  Widget _buildDues() {
    final dues = _assignments.where((a) => a.balanceAmount > 0).toList();
    return _pagedList<StudentFeeAssignmentModel>(
        list: 'dues',
        sectionOf: _sectionOfAssignment,
        items: dues.where(_filter.matchesAssignment).toList(),
        sourceCount: dues.length,
        idOf: (a) => a.id,
        hint: 'Search student, admission no., class, structure, year or status',
        noun: 'dues',
        searchFieldsOf: _assignmentSearchFields,
        itemBuilder: (a) {
          return _FeeListCard(
            icon: Icons.schedule_outlined,
            title: a.studentName,
            badge: _overdueBadge(a),
            subtitleLines: [
              '${a.admissionNo} • ${a.className}',
              _withMonth('Due: ${a.balanceAmount.toStringAsFixed(0)}', a),
              ?_discountLine(a),
              _dueLine(a),
            ],
            trailing: IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: _deletingId == a.id
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: _deletingId == a.id ? null : () => _deleteAssignment(a),
            ),
          );
        },
      );
  }

  /// [items] (already filtered and ordered) searched and paged in the UI
  /// only: the list's query (trimmed, case-insensitive substring of any of
  /// [searchFieldsOf]) is applied once, then just the current page's rows
  /// are built with [itemBuilder], plus the pagination controls (none when
  /// nothing is shown). A genuinely empty [items] renders exactly as before,
  /// with no search box. Summary figures never come from here — `_summary`
  /// covers all records.
  Widget _pagedList<T>({
    required String list,
    required List<T> items,
    required String Function(T item) idOf,
    required Widget Function(T item) itemBuilder,
    required Iterable<String> Function(T item) searchFieldsOf,
    required String hint,
    required String noun,
    int? sourceCount,
    String Function(T item)? sectionOf,
  }) {
    final pager = _pagers[list]!;
    // [sourceCount]: how many records there are before the shared filter
    // (null for a list without one). The search box stays while there are
    // any, so a query survives a filter that matches nothing.
    final hasSource = items.isNotEmpty || (sourceCount ?? 0) > 0;
    final filteredOut = items.isEmpty && (sourceCount ?? 0) > 0;
    final search = _searches[list]!;
    final query = search.text.trim().toLowerCase();
    var shown = query.isEmpty
        ? items
        : items.where((item) => searchFieldsOf(item).any((f) => f.toLowerCase().contains(query))).toList();
    // Month sections ([sectionOf]): records ordered by section, keeping
    // their own order within it, then paged as before.
    final sectionKeys = sectionOf == null ? const <String, String>{} : {for (final item in shown) idOf(item): sectionOf(item)};
    if (sectionOf != null) {
      final order = _sectionOrder(sectionKeys.values);
      final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
      final indexed = shown.indexed.toList()
        ..sort((x, y) {
          final byRank = (rank[sectionKeys[idOf(x.$2)]] ?? order.length).compareTo(rank[sectionKeys[idOf(y.$2)]] ?? order.length);
          return byRank != 0 ? byRank : x.$1.compareTo(y.$1);
        });
      shown = [for (final (_, item) in indexed) item];
    }
    pager.sync([for (final item in shown) idOf(item)], query: query);
    final pageItems = shown.sublist(pager.start, pager.end(shown.length));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSource)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              key: Key('fees-$list-search'),
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        key: Key('fees-$list-search-clear'),
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(search.clear),
                      ),
              ),
            ),
          ),
        if (sourceCount == 0)
          Padding(
            key: Key('fees-$list-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No $noun yet.', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
          ),
        if (filteredOut)
          Padding(
            key: Key('fees-$list-filter-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(
                  'No $noun match the selected filters.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                if (_feeMonth != null)
                  TextButton(
                    key: Key('fees-$list-month-clear'),
                    onPressed: () => _changeFilter(() => _feeMonth = null),
                    child: const Text('Show all months'),
                  ),
                if (!_filtersAtDefault)
                  TextButton(
                    key: Key('fees-$list-filter-empty-reset'),
                    onPressed: _resetFilters,
                    child: const Text('Reset filters'),
                  ),
              ],
            ),
          ),
        if (items.isNotEmpty && shown.isEmpty)
          Padding(
            key: Key('fees-$list-search-empty'),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No $noun match "${search.text.trim()}".',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ),
        if (sectionOf == null)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pageItems.length,
            itemBuilder: (context, i) => itemBuilder(pageItems[i]),
          )
        else
          ..._sectionedPage(list, pageItems, idOf, itemBuilder, sectionKeys,
              firstPage: pager.page == 0 && shown.isNotEmpty,
              previousKey: pager.start == 0 || shown.isEmpty ? null : sectionKeys[idOf(shown[pager.start - 1])]),
        if (shown.isNotEmpty)
          _FeePaginationControls(
            list: list,
            pager: pager,
            total: shown.length,
            onChanged: (update) => setState(update),
          ),
      ],
    );
  }
}

extension on _AdminFeesScreenState {
  /// One page of a sectioned list: a heading before each section's first
  /// row on the page ("(continued)" when it began on an earlier page). On
  /// the first page, the leading month's heading (the current month, or the
  /// selected one) is shown even when it has
  /// no records (All Months only).
  List<Widget> _sectionedPage<T>(
    String list,
    List<T> pageItems,
    String Function(T item) idOf,
    Widget Function(T item) itemBuilder,
    Map<String, String> sectionKeys, {
    required bool firstPage,
    required String? previousKey,
  }) {
    Widget heading(String key, {bool continued = false}) => Padding(
          key: Key('fees-$list-section-$key'),
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            '${_sectionTitle(key)}${continued ? ' (continued)' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
          ),
        );
    final out = <Widget>[];
    // The current month (All Months) or the selected month always leads.
    final current = _feeMonth ?? _currentFeeMonth;
    final firstKey = pageItems.isEmpty ? null : sectionKeys[idOf(pageItems.first)];
    if (firstPage && firstKey != current) {
      out
        ..add(heading(current))
        ..add(Padding(
          key: Key('fees-$list-section-empty-$current'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Nothing for ${FeeMonth.label(current)}.', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ));
    }
    String? last;
    for (final item in pageItems) {
      final key = sectionKeys[idOf(item)]!;
      if (key != last) {
        out.add(heading(key, continued: last == null && key == previousKey));
        last = key;
      }
      out.add(itemBuilder(item));
    }
    return out;
  }
}

/// A titled group of Fees Dashboard metric cards, laid out in a compact
/// responsive grid: 3 columns on wide desktop, 2 on tablet, 1 on mobile —
/// matching the breakpoints this screen already used for its metric row.
/// Grouping only changes presentation; every card still shows the exact
/// same pre-computed value it always did.
class _MetricSection extends StatelessWidget {
  const _MetricSection({
    required this.title,
    required this.caption,
    required this.cards,
    this.captionKey,
  });

  final String title;
  final String caption;
  final Key? captionKey;
  final List<FeeSummaryCard> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          key: captionKey,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1200
                ? 3
                : width >= 800
                    ? 2
                    : 1;
            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 112,
              ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cards.length,
              itemBuilder: (context, i) => cards[i],
            );
          },
        ),
      ],
    );
  }
}

/// Compact list-card shared by the Fees tabs: icon + title/meta (wrapped,
/// ellipsized) + trailing actions — matching the row pattern already used
/// by Students/Classes/Documents/Notifications.
class _FeeListCard extends StatelessWidget {
  const _FeeListCard({
    required this.icon,
    required this.title,
    required this.subtitleLines,
    required this.trailing,
    this.badge,
  });

  final IconData icon;
  final String title;

  /// Shown after the title (e.g. an "Overdue" label).
  final Widget? badge;
  final List<String> subtitleLines;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
                // On its own line, so a narrow card never runs out of room.
                if (badge != null) ...[const SizedBox(height: 4), badge!],
                for (final line in subtitleLines) ...[
                  const SizedBox(height: 4),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// UI page state for one Fees list: 10/25/50 per page. Returns to the first
/// page when the shown records are added, removed or reordered (their ids
/// change), when the list's search query changes, or when the current page
/// no longer exists. The page size is never reset.
class _ListPager {
  static const pageSizes = [10, 25, 50];

  int pageSize = pageSizes.first;
  int page = 0;
  int pageCount = 1;
  List<String> _lastIds = const [];
  String _lastQuery = '';

  void sync(List<String> ids, {String query = ''}) {
    if (!listEquals(ids, _lastIds) || query != _lastQuery) {
      _lastIds = ids;
      _lastQuery = query;
      page = 0;
    }
    pageCount = ids.isEmpty ? 1 : (ids.length + pageSize - 1) ~/ pageSize;
    if (page >= pageCount) page = 0;
  }

  int get start => page * pageSize;
  int end(int total) => (start + pageSize).clamp(0, total);
}

/// Range, page size and Previous/Next for one Fees list; wraps on narrow
/// screens. Keys: `fees-<list>-pagination`, `fees-<list>-page-size`.
class _FeePaginationControls extends StatelessWidget {
  const _FeePaginationControls({required this.list, required this.pager, required this.total, required this.onChanged});

  final String list;
  final _ListPager pager;
  final int total;
  final void Function(VoidCallback update) onChanged;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    return Wrap(
      key: Key('fees-$list-pagination'),
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Showing ${pager.start + 1}–${pager.end(total)} of $total', style: label),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Per page', style: label),
            DropdownButton<int>(
              key: Key('fees-$list-page-size'),
              value: pager.pageSize,
              underline: const SizedBox.shrink(),
              items: [for (final size in _ListPager.pageSizes) DropdownMenuItem(value: size, child: Text('$size'))],
              onChanged: (size) => onChanged(() => pager.pageSize = size ?? pager.pageSize),
            ),
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left),
              onPressed: pager.page > 0 ? () => onChanged(() => pager.page--) : null,
            ),
            Text('Page ${pager.page + 1} of ${pager.pageCount}', style: label),
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right),
              onPressed: pager.page < pager.pageCount - 1 ? () => onChanged(() => pager.page++) : null,
            ),
          ],
        ),
      ],
    );
  }
}
