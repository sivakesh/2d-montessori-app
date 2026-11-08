import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../admin/settings/providers/school_identity_provider.dart';
import '../../admin/students/models/admission_date.dart';
import '../models/fee_list_filter.dart';
import '../models/fee_report.dart';
import '../models/fee_student.dart';
import '../services/fee_report_pdf.dart';
import '../services/fee_service.dart';
import 'dialogs/fee_receipt_view_dialog.dart';

/// Saves or shares a generated PDF (the browser download on the web).
typedef FeePdfExporter = Future<void> Function(Uint8List bytes, String fileName);

Future<void> sharePdfExporter(Uint8List bytes, String fileName) async {
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

/// Fees → Reports: the Student Monthly Fee Statement and the All Students
/// – Fee Collection and Outstanding Report. Both follow the Fees screen's
/// shared filters (Academic Year, Class, Student, Fee Month); the second
/// adds search, payment status and an admission-date range. Screen and
/// PDF come from the same FeeReport.build result. Read-only.
class FeeReportsTab extends ConsumerStatefulWidget {
  const FeeReportsTab({
    super.key,
    required this.service,
    required this.filter,
    required this.students,
    required this.classNames,
    required this.filterLabels,
    required this.reloadToken,
    this.exportPdf = sharePdfExporter,
    this.clock = DateTime.now,
  });

  final FeeService service;
  final FeeListFilter filter;

  /// Every student record (active or not), as the screen loaded them.
  final List<FeeStudent> students;
  final Map<String, String> classNames;

  /// The shared filters as shown ("Academic Year: 2026-2027", …), for the
  /// report headings and PDFs.
  final List<String> filterLabels;

  /// Changes whenever the screen reloads, so the report reads again.
  final int reloadToken;
  final FeePdfExporter exportPdf;
  final DateTime Function() clock;

  @override
  ConsumerState<FeeReportsTab> createState() => _FeeReportsTabState();
}

class _FeeReportsTabState extends ConsumerState<FeeReportsTab> {
  static const _pageSize = 10;

  FeeReportData? _data;
  String? _error;
  bool _loading = true;
  bool _exporting = false;

  final _search = TextEditingController();
  FeePaymentStatus? _status;
  DateTime? _from, _to;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(FeeReportsTab old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) _read();
    if (old.filter.year != widget.filter.year || old.filter.classId != widget.filter.classId || old.filter.feeMonth != widget.filter.feeMonth ||
        old.filter.studentId != widget.filter.studentId) {
      _page = 0;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.getReportData();
      if (mounted) setState(() => _data = data);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You don’t have permission to read the fee records these reports need. Nothing was changed.'
            : 'The fee records could not be read (${e.code}). Nothing was changed.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'The fee records could not be read: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  FeeSchoolReport _report(FeeReportFilter filter) =>
      FeeReport.build(students: widget.students, data: _data!, classNames: widget.classNames, filter: filter);

  FeeReportFilter get _schoolFilter => FeeReportFilter(base: widget.filter, search: _search.text, status: _status, admittedFrom: _from, admittedTo: _to);

  String get _schoolName {
    final name = ref.watch(schoolIdentityProvider).valueOrNull?.name.trim() ?? '';
    return name.isEmpty ? '2D Montessori' : name;
  }

  List<String> get _schoolFilterLabels => [
        ...widget.filterLabels,
        'Payment status: ${_status?.label ?? 'All'}',
        if (_search.text.trim().isNotEmpty) 'Search: "${_search.text.trim()}"',
        if (_from != null || _to != null)
          'Admitted: ${_from == null ? 'any date' : AdmissionDate.label(_from)} to ${_to == null ? 'any date' : AdmissionDate.label(_to)}',
      ];

  Future<void> _export(Future<Uint8List> Function(FeeReportPdfHeader h) build, String title, List<String> filters, String fileName) async {
    setState(() => _exporting = true);
    try {
      final header = FeeReportPdfHeader(
        schoolName: _schoolName,
        title: title,
        filters: filters,
        generatedAt: widget.clock(),
        logo: await FeeReportPdfHeader.bundledLogo(),
      );
      await widget.exportPdf(await build(header), fileName);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('The PDF could not be created: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openReceipt(FeeReportPayment p) => showDialog<void>(
        context: context,
        builder: (_) => FeeReceiptViewDialog(receipt: p.receipt, service: widget.service, voided: p.voided),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (_error case final e?) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.lock_outline, color: Colors.red),
          title: Text(e, key: const Key('fee-report-error')),
          trailing: TextButton(onPressed: _read, child: const Text('Try Again')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statementCard(),
        const SizedBox(height: 16),
        _schoolCard(),
      ],
    );
  }

  // ------------------------------------------------ statement

  Widget _statementCard() {
    final f = widget.filter;
    Widget body;
    if (f.studentId != null) {
      final s = _report(FeeReportFilter(base: f)).students.where((x) => x.student.id == f.studentId).firstOrNull;
      body = s == null
          ? const Text('The selected student isn’t in the selected class.', key: Key('fee-statement-none'))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    key: const Key('fee-statement-export'),
                    onPressed: _exporting ? null : () => _exportStatement(s),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Export Statement as PDF'),
                  ),
                ),
                _StatementView(statement: s, filterLabels: widget.filterLabels, generatedAt: widget.clock(), onReceipt: _openReceipt),
              ],
            );
    } else if (f.classId != null) {
      final r = _report(FeeReportFilter(base: f));
      body = r.students.isEmpty
          ? const Text('No students in this class.', key: Key('fee-statement-none'))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                key: const Key('fee-statement-class'),
                columns: const [
                  DataColumn(label: Text('Student')),
                  DataColumn(label: Text('Admission No')),
                  DataColumn(label: Text('Payable'), numeric: true),
                  DataColumn(label: Text('Collected'), numeric: true),
                  DataColumn(label: Text('Outstanding'), numeric: true),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final s in r.students)
                    DataRow(cells: [
                      DataCell(Text(s.student.name)),
                      DataCell(Text(s.student.admissionNo)),
                      DataCell(Text(FeeReport.money(s.payable))),
                      DataCell(Text(FeeReport.money(s.collected))),
                      DataCell(Text(FeeReport.money(s.outstanding))),
                      DataCell(Text(s.status.label)),
                      DataCell(TextButton(
                        key: Key('fee-statement-view-${s.student.id}'),
                        onPressed: () => _showStatement(s),
                        child: const Text('View Statement'),
                      )),
                    ]),
                ],
              ),
            );
    } else {
      body = const Text('Choose a student in the filters above for their statement, or a class to see each student’s totals.', key: Key('fee-statement-hint'));
    }
    return _card(FeeReport.statementTitle, 'fee-statement-card', body);
  }

  Future<void> _exportStatement(FeeStudentStatement s) => _export(
        (h) => FeeReportPdf.statement(s, h),
        FeeReport.statementTitle,
        [
          'Student: ${s.student.name}', 'Admission No: ${s.student.admissionNo.isEmpty ? '—' : s.student.admissionNo}',
          'Admission date: ${AdmissionDate.label(s.student.admissionDate)}', 'Class: ${s.className}', ...widget.filterLabels,
        ],
        'fee-statement-${s.student.admissionNo.isEmpty ? s.student.id : s.student.admissionNo}.pdf',
      );

  Future<void> _showStatement(FeeStudentStatement s) => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(FeeReport.statementTitle, style: Theme.of(context).textTheme.titleMedium)),
                      OutlinedButton.icon(
                        key: const Key('fee-statement-export'),
                        onPressed: () => _exportStatement(s),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export as PDF'),
                      ),
                      IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _StatementView(statement: s, filterLabels: widget.filterLabels, generatedAt: widget.clock(), onReceipt: _openReceipt),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  // ------------------------------------------------ school-wide

  Widget _schoolCard() {
    final r = _report(_schoolFilter);
    final pages = (r.students.length / _pageSize).ceil();
    final page = pages == 0 ? 0 : _page.clamp(0, pages - 1);
    final shown = r.students.skip(page * _pageSize).take(_pageSize).toList();
    return _card(
      FeeReport.schoolTitle,
      'fee-report-card',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const Key('fee-report-export'),
                onPressed: _exporting || r.students.isEmpty
                    ? null
                    : () => _export((h) => FeeReportPdf.school(r, h), FeeReport.schoolTitle, _schoolFilterLabels, 'all-students-fee-report.pdf'),
                icon: _exporting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export Full Report as PDF'),
              ),
              Text(
                r.students.isEmpty
                    ? 'No students match these filters, so there is nothing to export.'
                    : 'The PDF contains all ${r.totalStudents} matching students, not just this page.',
                key: const Key('fee-report-export-note'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  key: const Key('fee-report-search'),
                  controller: _search,
                  decoration: const InputDecoration(labelText: 'Search student or admission no.', prefixIcon: Icon(Icons.search), isDense: true),
                  onChanged: (_) => setState(() => _page = 0),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<FeePaymentStatus?>(
                  key: const Key('fee-report-status'),
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Payment status', isDense: true),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: FeePaymentStatus.paid, child: Text('Paid')),
                    DropdownMenuItem(value: FeePaymentStatus.partial, child: Text('Partially Paid')),
                    DropdownMenuItem(value: FeePaymentStatus.unpaid, child: Text('Not Paid')),
                  ],
                  onChanged: (v) => setState(() {
                    _status = v;
                    _page = 0;
                  }),
                ),
              ),
              _dateButton('fee-report-admitted-from', 'Admitted from', _from, (d) => _from = d),
              _dateButton('fee-report-admitted-to', 'Admitted to', _to, (d) => _to = d),
            ],
          ),
          if (_from != null || _to != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('With an admission-date range, students without an admission date are not shown.', style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          _summary(r),
          const SizedBox(height: 12),
          Text('Month-wise summary', style: Theme.of(context).textTheme.titleSmall),
          _summaryTable('fee-report-monthly', 'Fee Month', r.monthlySummary, 'No monthly fees in the selected period.'),
          const SizedBox(height: 12),
          Text('${FeeReport.nonMonthlyTitle} summary', style: Theme.of(context).textTheme.titleSmall),
          _summaryTable('fee-report-nonmonthly', 'Fee Structure', r.nonMonthlySummary, 'No term or one-time fees in the selected period.'),
          if (r.noMonthSummary case final row?) ...[
            const SizedBox(height: 12),
            Text('${FeeReport.noMonthTitle} summary', style: Theme.of(context).textTheme.titleSmall),
            _summaryTable('fee-report-nomonth', 'Fees', [row], ''),
          ],
          const SizedBox(height: 16),
          Text('Students', style: Theme.of(context).textTheme.titleSmall),
          if (r.students.isEmpty) const Text('No students match the selected filters.', key: Key('fee-report-empty')),
          for (final s in shown)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: DecoratedBox(
                key: Key('fee-report-student-${s.student.id}'),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outline, width: 3))),
                child: Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: _StatementView(statement: s, compact: true, onReceipt: _openReceipt),
                ),
              ),
            ),
          if (pages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  IconButton(tooltip: 'Previous page', onPressed: page == 0 ? null : () => setState(() => _page = page - 1), icon: const Icon(Icons.chevron_left)),
                  Text('Showing ${page * _pageSize + 1}–${page * _pageSize + shown.length} of ${r.totalStudents} students', key: const Key('fee-report-page')),
                  IconButton(
                    key: const Key('fee-report-next'),
                    tooltip: 'Next page',
                    onPressed: page >= pages - 1 ? null : () => setState(() => _page = page + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateButton(String key, String label, DateTime? value, void Function(DateTime?) set) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            key: Key(key),
            icon: const Icon(Icons.event, size: 18),
            label: Text(value == null ? label : '$label ${AdmissionDate.label(value)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: AdmissionDate.first,
                lastDate: AdmissionDate.last,
                initialDate: value ?? AdmissionDate.dateOnly(widget.clock()),
              );
              if (picked != null) {
                setState(() {
                  set(AdmissionDate.dateOnly(picked));
                  _page = 0;
                });
              }
            },
          ),
          if (value != null)
            IconButton(
              key: Key('$key-clear'),
              tooltip: 'Clear',
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() {
                set(null);
                _page = 0;
              }),
            ),
        ],
      );

  Widget _summary(FeeSchoolReport r) {
    final items = [
      ('students', 'Total students', '${r.totalStudents}'),
      ('assigned-students', 'With fee assignments', '${r.withAssignments}'),
      ('paid', 'Fully paid', '${r.count(FeePaymentStatus.paid)}'),
      ('partial', 'Partially paid', '${r.count(FeePaymentStatus.partial)}'),
      ('unpaid', 'No payment', '${r.count(FeePaymentStatus.unpaid)}'),
      ('assigned', 'Total assigned', FeeReport.money(r.assigned)),
      ('discounts', 'Total discounts', FeeReport.money(r.discounts)),
      ('student-discounts', 'Student discounts', FeeReport.money(r.studentDiscounts)),
      ('manual-discounts', 'Manual discounts', FeeReport.money(r.manualDiscounts)),
      ('payable', 'Total payable', FeeReport.money(r.payable)),
      ('collected', 'Total collected', FeeReport.money(r.collected)),
      ('outstanding', 'Total outstanding', FeeReport.money(r.outstanding)),
      ('percent', 'Collection %', FeeReport.percentLabel(r.collectionPercent)),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (key, label, value) in items)
          Container(
            constraints: const BoxConstraints(minWidth: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(value, key: Key('fee-report-summary-$key'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _summaryTable(String key, String first, List<FeeReportSummaryRow> rows, String empty) => rows.isEmpty
      ? Text(empty, key: Key('$key-empty'))
      : SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: Key(key),
            columns: [
              DataColumn(label: Text(first)),
              const DataColumn(label: Text('Students Assigned'), numeric: true),
              const DataColumn(label: Text('Gross Assigned'), numeric: true),
              const DataColumn(label: Text('Discounts'), numeric: true),
              const DataColumn(label: Text('Total Payable'), numeric: true),
              const DataColumn(label: Text('Total Collected'), numeric: true),
              const DataColumn(label: Text('Outstanding'), numeric: true),
              const DataColumn(label: Text('Collection %'), numeric: true),
            ],
            rows: [
              for (final r in rows)
                DataRow(cells: [
                  DataCell(Text(r.label)),
                  DataCell(Text('${r.students.length}')),
                  DataCell(Text(FeeReport.money(r.assigned))),
                  DataCell(Text(FeeReport.money(r.discounts))),
                  DataCell(Text(FeeReport.money(r.payable))),
                  DataCell(Text(FeeReport.money(r.collected))),
                  DataCell(Text(FeeReport.money(r.outstanding))),
                  DataCell(Text(FeeReport.percentLabel(r.percent))),
                ]),
            ],
          ),
        );

  Widget _card(String title, String key, Widget body) => Card(
        key: Key(key),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              body,
            ],
          ),
        ),
      );
}

/// One student's statement: details and totals, then the monthly table
/// (one row per payment, or "Not paid"), Term and One-time fees, Month not
/// recorded, unlinked receipts and any reconciliation warnings.
class _StatementView extends StatelessWidget {
  const _StatementView({required this.statement, required this.onReceipt, this.compact = false, this.filterLabels = const [], this.generatedAt});

  final FeeStudentStatement statement;
  final Future<void> Function(FeeReportPayment) onReceipt;
  final bool compact;
  final List<String> filterLabels;
  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    final st = s.student;
    final small = Theme.of(context).textTheme.bodySmall;
    final id = st.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${st.name.isEmpty ? st.id : st.name}${st.admissionNo.isEmpty ? '' : ' (${st.admissionNo})'}',
            style: Theme.of(context).textTheme.titleSmall),
        Text(
          [
            'Admission date: ${AdmissionDate.label(st.admissionDate)}',
            'Class: ${s.className}',
            'Status: ${s.status.label}',
            if (!st.isActive) 'Inactive',
            if (s.recordMissing) 'Student record not found',
          ].join(' · '),
          key: Key('fee-statement-details-$id'),
          style: small,
        ),
        if (!compact) ...[
          if (filterLabels.isNotEmpty) Text(filterLabels.join(' · '), style: small),
          if (generatedAt != null) Text('Generated ${FeeReport.date(generatedAt)}', style: small),
        ],
        const SizedBox(height: 6),
        if (!s.hasAssignments)
          Text(FeeReport.noAssignments, key: Key('fee-statement-no-assignments-$id'), style: const TextStyle(fontStyle: FontStyle.italic))
        else ...[
          Text(
            'Assigned ${FeeReport.money(s.assigned)} · Discounts ${FeeReport.money(s.discounts)}'
            '${(s.studentDiscounts * 100).round() > 0 ? ' (student ${FeeReport.money(s.studentDiscounts)}, manual ${FeeReport.money(s.manualDiscounts)})' : ''} · Net payable ${FeeReport.money(s.payable)} · '
            'Collected ${FeeReport.money(s.collected)} · Outstanding ${FeeReport.money(s.outstanding)} · '
            '${FeeReport.percentLabel(s.collectionPercent)} collected',
            key: Key('fee-statement-totals-$id'),
          ),
          if (s.monthly.isNotEmpty) _table(context, 'Monthly fees', 'fee-statement-monthly-$id', s.monthly, monthly: true),
          if (s.nonMonthly.isNotEmpty) _table(context, FeeReport.nonMonthlyTitle, 'fee-statement-nonmonthly-$id', s.nonMonthly, monthly: false),
          if (s.noMonth.isNotEmpty) _table(context, FeeReport.noMonthTitle, 'fee-statement-nomonth-$id', s.noMonth, monthly: false),
        ],
        if (s.unlinked.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(FeeReport.unlinkedTitle, style: Theme.of(context).textTheme.labelLarge),
          for (final p in s.unlinked)
            Text(
              '${FeeReport.date(p.receipt.paymentDate)} · ${p.receipt.receiptNo} · ${p.receipt.paymentMode} · ${FeeReport.money(p.receipt.amount)}'
              '${p.voided ? ' · Cancelled (voided)' : ''}',
              key: Key('fee-statement-unlinked-${p.receipt.id}'),
              style: small,
            ),
        ],
        for (final w in s.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Reconciliation warning: $w', key: Key('fee-statement-warning-$id'), style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _table(BuildContext context, String title, String key, List<FeeReportLine> lines, {required bool monthly}) {
    final rows = [for (final l in lines) ...l.rows];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              key: Key(key),
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: [
                DataColumn(label: Text(monthly ? 'Fee Month' : 'Fee Structure')),
                DataColumn(label: Text(monthly ? 'Fee' : 'Assigned')),
                if (!monthly) const DataColumn(label: Text('Due Date')),
                const DataColumn(label: Text('Payment Date')),
                const DataColumn(label: Text('Receipt No')),
                const DataColumn(label: Text('Method')),
                const DataColumn(label: Text('Status')),
                const DataColumn(label: Text('Amount Paid'), numeric: true),
                const DataColumn(label: Text('Total Paid'), numeric: true),
                const DataColumn(label: Text('Outstanding'), numeric: true),
                const DataColumn(label: Text('Discount'), numeric: true),
                const DataColumn(label: Text('Total Payable'), numeric: true),
              ],
              rows: [
                for (final r in rows)
                  DataRow(
                    key: ValueKey('${r.line.assignment.id}:${r.payment?.receipt.id ?? 'none'}'),
                    cells: [
                      DataCell(Text(monthly ? r.line.feeMonthLabel : r.line.assignment.feeStructureName)),
                      DataCell(Text(monthly ? r.line.assignment.feeStructureName : FeeReport.date(r.line.assignment.assignedAt))),
                      if (!monthly) DataCell(Text(FeeReport.date(r.line.assignment.dueDate))),
                      DataCell(Text(FeeReport.date(r.payment?.receipt.paymentDate))),
                      DataCell(r.payment == null
                          ? const Text('—')
                          : TextButton(
                              key: Key('fee-statement-receipt-${r.payment!.receipt.id}'),
                              onPressed: () => onReceipt(r.payment!),
                              child: Text(r.payment!.receipt.receiptNo.isEmpty ? 'View' : r.payment!.receipt.receiptNo),
                            )),
                      DataCell(Text(r.payment?.receipt.paymentMode ?? '—')),
                      DataCell(Text(r.status, style: TextStyle(color: r.voided ? Colors.red : null))),
                      DataCell(Text(r.voided ? '${FeeReport.money(r.payment!.receipt.amount)} (cancelled)' : FeeReport.money(r.amount))),
                      DataCell(Text(FeeReport.money(r.line.paid))),
                      DataCell(Text(FeeReport.money(r.line.outstanding))),
                      DataCell(Tooltip(
                        message: r.line.assignment.studentDiscount == null
                            ? 'Manual discount'
                            : 'Student discount ${r.line.assignment.studentDiscount!.label}; manual ${FeeReport.money(r.line.manualDiscount)}',
                        child: Text(FeeReport.money(r.line.discount)),
                      )),
                      DataCell(Text(FeeReport.money(r.line.payable))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
