import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../admin/settings/models/school_settings_model.dart';
import '../models/fee_month.dart';
import '../models/fee_student.dart';
import '../services/fee_receipt_regeneration.dart' show ReceiptParent, ReceiptPdfSaver;
import '../ui/dialogs/fee_receipt_regenerate_dialog.dart' show SchoolLogoLoader, SchoolProfileLoader;
import 'fee_bill_models.dart';
import 'fee_bill_pdf.dart';
import 'fee_bill_service.dart';

/// The school's header for a new bill, from School Settings (read only).
FeeBillSchool feeBillSchoolOf(SchoolSettingsModel? s) {
  String t(String? v) => v?.trim() ?? '';
  return FeeBillSchool(
    name: t(s?.name),
    addressLines: s?.postalAddressLines ?? const [],
    contactLines: [
      if (t(s?.phone).isNotEmpty) 'Phone: ${t(s?.phone)}',
      if (t(s?.email).isNotEmpty) 'Email: ${t(s?.email)}',
      if (t(s?.website).isNotEmpty) 'Website: ${t(s?.website)}',
    ],
    logoUrl: t(s?.logoUrl),
  );
}

/// An unsaved bill line being edited (its text fields).
class _LineDraft {
  _LineDraft({required this.month, required this.className, String description = '', String gross = ''})
      : description = TextEditingController(text: description),
        gross = TextEditingController(text: gross);

  String month;

  /// The class printed on this bill.
  String className;
  final TextEditingController description, gross;
  final adjustment = TextEditingController(text: '0');
  final reason = TextEditingController();
  FeeBillAdjustmentType type = FeeBillAdjustmentType.none;

  int? get grossPaise => parseRupees(gross.text);
  int? get adjustmentPaise => adjustment.text.trim().isEmpty ? 0 : parseRupees(adjustment.text);

  /// The line, or null while an amount isn't a valid amount.
  FeeBillLine? get line {
    final g = grossPaise, a = adjustmentPaise;
    if (g == null || a == null) return null;
    return FeeBillLine(
        billingMonth: month, description: description.text, grossPaise: g, adjustmentType: type, adjustmentPaise: a, adjustmentReason: reason.text, className: className);
  }

  String? get error {
    if (grossPaise == null) return 'Enter the gross bill amount, e.g. 4200 or 4200.50.';
    if (adjustmentPaise == null) return 'Enter the adjustment amount (0 for none).';
    return line!.error;
  }

  void dispose() {
    description.dispose();
    gross.dispose();
    adjustment.dispose();
    reason.dispose();
  }
}

/// Fees → Fee Bill Issuance → Issue Bills: choose a student and one of
/// their existing payments, add one or more bill lines (each issued as a
/// separate bill), review, then issue. Only bill records are written
/// ([FeeBillService.issueBills]); the payment, its receipt, the fee
/// assignment and Finance are never changed.
///
/// Keys: `fee-bill-` + `student-search`, `student-<id>`, `student-change`,
/// `payment-<receiptId>`, `payment-details`, `line-<i>-month`,
/// `line-<i>-year`, `line-<i>-description`, `line-<i>-gross`,
/// `line-<i>-adjustment-type`, `line-<i>-adjustment`, `line-<i>-reason`,
/// `line-<i>-net`, `line-<i>-remove`, `add-line`, `summary-payment`,
/// `summary-billed`, `summary-new`, `summary-remaining`, `error`,
/// `preview`, `preview-pdf-<i>`, `issue`, `confirm-issue`, `cancel`,
/// `issued-<billNo>`, `download-<billNo>`, `close`.
class FeeBillIssueDialog extends StatefulWidget {
  const FeeBillIssueDialog({
    super.key,
    required this.service,
    required this.role,
    required this.loadSchool,
    required this.loadLogo,
    required this.savePdf,
    this.clock = DateTime.now,
  });

  final FeeBillService service;
  final String role;
  final SchoolProfileLoader loadSchool;
  final SchoolLogoLoader loadLogo;
  final ReceiptPdfSaver savePdf;
  final DateTime Function() clock;

  @override
  State<FeeBillIssueDialog> createState() => _FeeBillIssueDialogState();
}

class _FeeBillIssueDialogState extends State<FeeBillIssueDialog> {
  // One id for this dialog's issue: a repeated press, or a retry after a
  // lost response, returns the bills already issued instead of new ones.
  // (Not from Random().nextInt(1 << 32): on the web `1 << 32` is 0 and
  // nextInt throws a RangeError as the dialog opens.)
  late final String _requestId = widget.service.newRequestId();
  final _search = TextEditingController();
  List<FeeStudent> _students = const [];
  FeeStudent? _student;
  List<FeeBillPayment> _payments = const [];
  final Map<String, FeeBillAllocation?> _allocations = {};
  FeeBillPayment? _payment;
  final List<_LineDraft> _lines = [];
  FeeBillSchool _school = const FeeBillSchool(name: '');
  bool _loading = true, _busy = false, _reviewing = false;

  /// Class names for the per-bill class selector (read only).
  Map<String, String> _classNames = const {};

  /// The parent or guardian the bills will name (father, else mother, else
  /// guardian); null : none.
  ReceiptParent? _parent;

  /// The school's saved GSTIN, and the two GST options (as on the
  /// regenerated receipt; both off by default).
  String _savedGstin = '';
  bool _showGstin = false, _amountIncludesGst = false;

  /// Each billing month's Issue Date, worked out for the preview.
  Map<String, DateTime> _issueDates = const {};
  String? _error;
  List<FeeIssuedBill>? _issued;

  static final _date = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    List<FeeStudent> students = const [];
    SchoolSettingsModel? school;
    try {
      students = await widget.service.getStudents();
    } catch (_) {}
    try {
      school = await widget.loadSchool();
    } catch (_) {}
    var classNames = const <String, String>{};
    try {
      classNames = await widget.service.getClassNames();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _students = students;
      _school = feeBillSchoolOf(school);
      _savedGstin = school?.gstin ?? '';
      _classNames = classNames;
      _loading = false;
    });
  }

  Future<void> _chooseStudent(FeeStudent s) async {
    setState(() {
      _student = s;
      _payment = null;
      _payments = const [];
      _reviewing = false;
      _error = null;
      _busy = true;
    });
    try {
      final payments = await widget.service.paymentsForStudent(s.id);
      for (final p in payments) {
        _allocations[p.receiptId] = await widget.service.getAllocation(p.receiptId);
      }
      final parent = await widget.service.parentFor(s.id);
      if (!mounted) return;
      setState(() {
        _payments = payments;
        _parent = parent;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'The payments could not be loaded: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _choosePayment(FeeBillPayment p) {
    setState(() {
      _payment = p;
      _reviewing = false;
      _error = null;
      for (final l in _lines) {
        l.dispose();
      }
      _lines.clear();
      final start = FeeMonth.isValid(p.feeMonth)
          ? p.feeMonth
          : FeeMonth.of((p.paymentDate ?? widget.clock()).year, (p.paymentDate ?? widget.clock()).month);
      _lines.add(_LineDraft(month: start, className: p.className.trim(), description: p.feeName));
    });
  }

  void _addLine() => setState(() {
        final last = _lines.isEmpty ? null : _lines.last;
        var month = last?.month ?? FeeMonth.of(widget.clock().year, widget.clock().month);
        if (last != null) {
          final y = int.parse(month.substring(0, 4)), m = int.parse(month.substring(5));
          month = m == 12 ? FeeMonth.of(y + 1, 1) : FeeMonth.of(y, m + 1);
        }
        _lines.add(_LineDraft(
            month: month, className: last?.className ?? _payment?.className.trim() ?? '', description: last?.description.text ?? '', gross: last?.gross.text ?? ''));
        _reviewing = false;
      });

  void _removeLine(int i) => setState(() {
        _lines.removeAt(i).dispose();
        _reviewing = false;
      });

  int get _billed => _allocations[_payment?.receiptId]?.allocatedPaise ?? 0;
  int get _newNet => _lines.fold<int>(0, (s, l) => s + (l.line?.netPaise ?? 0));

  /// Why the lines can't be issued yet, or null.
  String? get _validation {
    final p = _payment;
    if (p == null) return 'Choose the original payment.';
    if (p.voided) return FeeBillService.voidedMessage;
    if (_lines.isEmpty) return 'Add at least one bill line.';
    for (final (i, l) in _lines.indexed) {
      if (l.error case final e?) return 'Bill line ${i + 1}: $e';
    }
    final keys = <String>{};
    for (final l in _lines) {
      if (!keys.add(l.line!.key)) return 'Two bill lines are for the same month and description. Remove one.';
    }
    if (_showGstin) {
      final g = SchoolSettingsValidation.normalizeGstin(_savedGstin);
      if (g.isEmpty) return 'No GSTIN is configured for this school. Add it in Settings → School Settings, or untick Show GSTIN on bill.';
      if (SchoolSettingsValidation.validateGstin(g) case final e?) {
        return 'The GSTIN saved in School Settings is not valid ($e) Correct it there, or untick Show GSTIN on bill.';
      }
    }
    final available = p.amountPaise - _billed;
    if (_newNet > available) {
      return 'These bills total ${billMoney(_newNet)} net, but only ${billMoney(available < 0 ? 0 : available)} of this payment is not yet billed.';
    }
    return null;
  }

  FeeIssuedBill _draftBill(FeeBillLine line) => FeeIssuedBill(
        id: '',
        schoolId: widget.service.schoolId,
        billNo: '',
        status: FeeBillStatus.issued,
        payment: _payment!,
        line: line.normalized,
        school: _billSchool,
        issuedAt: null,
        issuedBy: '',
        issueDate: _issueDates[line.billingMonth],
        parentRelation: _parent?.relation ?? '',
        parentName: _parent?.name ?? '',
        amountIncludesGst: _amountIncludesGst,
      );

  /// The school header the bills carry: with the GSTIN only when shown.
  FeeBillSchool get _billSchool => _school.withGstin(_showGstin ? SchoolSettingsValidation.normalizeGstin(_savedGstin) : '');

  /// The classes offered: every class, plus the receipt's and the line's
  /// own (even if no longer a class), by name.
  List<String> _classOptions(_LineDraft l) => {
        for (final n in _classNames.values)
          if (n.trim().isNotEmpty) n.trim(),
        if ((_payment?.className.trim() ?? '').isNotEmpty) _payment!.className.trim(),
        if (l.className.isNotEmpty) l.className,
      }.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  /// Works out each billing month's Issue Date (from the school calendar),
  /// then shows the preview; says why when it can't.
  Future<void> _startReview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dates = <String, DateTime>{};
      for (final m in {for (final l in _lines) l.month}) {
        dates[m] = await widget.service.issueDateFor(m);
      }
      if (!mounted) return;
      setState(() {
        _issueDates = dates;
        _reviewing = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewPdf(int i) async {
    final line = _lines[i].line;
    if (line == null) return;
    try {
      final bytes = await FeeBillPdf.build(_draftBill(line), preview: true, logo: await widget.loadLogo(_school.logoUrl));
      await widget.savePdf(bytes, 'fee-bill-preview-${i + 1}.pdf');
    } catch (e) {
      if (mounted) setState(() => _error = 'The preview could not be created: $e');
    }
  }

  Future<void> _issue() async {
    if (_busy || _validation != null) return;
    final p = _payment!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Issue ${_lines.length} ${_lines.length == 1 ? 'bill' : 'bills'}?'),
        content: Text(
          '${_lines.length} ${_lines.length == 1 ? 'bill' : 'separate bills'} totalling ${billMoney(_newNet)} net will be issued against '
          'receipt ${p.receiptNo} (${billMoney(p.amountPaise)}). Each gets its own Bill Reference (${p.receiptNo}-000001 onwards) and cannot be edited afterwards; '
          'a mistake is corrected by cancelling the bill and issuing a replacement.\n\n'
          'No payment, receipt, fee balance or Finance record is created or changed.',
          key: const Key('fee-bill-confirm-text'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const Key('fee-bill-confirm-issue'), onPressed: () => Navigator.pop(context, true), child: const Text('Issue Bills')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final issued = await widget.service.issueBills(
        requesterRole: widget.role,
        studentId: _student!.id,
        receiptId: p.receiptId,
        lines: [for (final l in _lines) l.line!],
        requestId: _requestId,
        school: _billSchool,
        amountIncludesGst: _amountIncludesGst,
      );
      if (!mounted) return;
      setState(() {
        _issued = issued;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e'.replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _download(FeeIssuedBill b) async {
    try {
      await widget.savePdf(await FeeBillPdf.build(b, logo: await widget.loadLogo(b.school.logoUrl)), FeeBillPdf.fileName(b));
    } catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('The PDF could not be created: $e')));
    }
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.blueGrey.shade700)),
      );

  Widget _row(String label, String value, {Key? key, bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 170, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
          Expanded(child: Text(value, key: key, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color))),
        ]),
      );

  Widget _studentStep() {
    final s = _student;
    if (s != null) {
      return Row(children: [
        Expanded(child: Text('${s.name}${s.admissionNo.isEmpty ? '' : ' (${s.admissionNo})'}', style: const TextStyle(fontWeight: FontWeight.w600))),
        TextButton(
          key: const Key('fee-bill-student-change'),
          onPressed: _busy ? null : () => setState(() {
                _student = null;
                _payment = null;
                _payments = const [];
                _reviewing = false;
              }),
          child: const Text('Change'),
        ),
      ]);
    }
    if (_students.isEmpty) {
      return const Text('No students were found, so no bill can be issued.', key: Key('fee-bill-no-students'));
    }
    final q = _search.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <FeeStudent>[]
        : _students.where((x) => x.name.toLowerCase().contains(q) || x.admissionNo.toLowerCase().contains(q)).take(8).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const Key('fee-bill-student-search'),
        controller: _search,
        decoration: const InputDecoration(labelText: 'Search student name or admission no.', prefixIcon: Icon(Icons.search)),
        onChanged: (_) => setState(() {}),
      ),
      for (final x in matches)
        ListTile(
          key: Key('fee-bill-student-${x.id}'),
          dense: true,
          title: Text(x.name.isEmpty ? '(no name)' : x.name),
          subtitle: x.admissionNo.isEmpty ? null : Text(x.admissionNo),
          onTap: () => _chooseStudent(x),
        ),
      if (q.isNotEmpty && matches.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No matching student.')),
    ]);
  }

  Widget _paymentStep() {
    if (_busy && _payments.isEmpty) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
    if (_payments.isEmpty) return const Text('This student has no recorded payments.', key: Key('fee-bill-no-payments'));
    return Column(children: [
      for (final p in _payments)
        Builder(builder: (context) {
          final billed = _allocations[p.receiptId]?.allocatedPaise ?? 0;
          final available = p.amountPaise - billed;
          // Nothing left to bill (or voided): shown, but not selectable.
          final usableNo = FeeBillService.referenceBaseOf(p.receiptNo) != null;
          final selectable = !p.voided && available > 0 && usableNo;
          return Card(
            key: Key('fee-bill-payment-${p.receiptId}'),
            margin: const EdgeInsets.symmetric(vertical: 3),
            color: _payment?.receiptId == p.receiptId ? Colors.blue.shade50 : null,
            child: ListTile(
              dense: true,
              enabled: selectable && !_busy,
              leading: Icon(_payment?.receiptId == p.receiptId ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text('${p.receiptNo} · ${billMoney(p.amountPaise)}${p.voided ? ' · VOIDED' : (available <= 0 ? ' · FULLY BILLED' : '')}'),
              subtitle: Text(
                '${p.paymentDate == null ? 'No payment date' : _date.format(p.paymentDate!)} · ${p.paymentMode}'
                '${p.referenceNo.isEmpty ? '' : ' · Ref ${p.referenceNo}'}\n'
                'Already billed ${billMoney(billed)} · Not yet billed ${billMoney(available < 0 ? 0 : available)}'
                '${!p.voided && available <= 0 ? ' · Cancel a bill to bill this payment again' : ''}'
                '${usableNo ? '' : '\n${FeeBillService.unusableReceiptNoMessage(p.receiptNo)}'}',
              ),
              isThreeLine: true,
              onTap: selectable ? () => _choosePayment(p) : null,
            ),
          );
        }),
    ]);
  }

  Widget _paymentDetails(FeeBillPayment p) => Container(
        key: const Key('fee-bill-payment-details'),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: Column(children: [
          _row('Student', p.studentName),
          _row('Receipt number', p.receiptNo),
          _row('Payment date', p.paymentDate == null ? '-' : _date.format(p.paymentDate!)),
          _row('Amount received', billMoney(p.amountPaise), bold: true),
          _row('Payment mode', p.paymentMode.isEmpty ? '-' : p.paymentMode),
          _row('Payment reference', p.referenceNo.isEmpty ? '-' : p.referenceNo),
        ]),
      );

  Widget _lineEditor(int i, _LineDraft l) {
    final year = int.parse(l.month.substring(0, 4)), month = int.parse(l.month.substring(5));
    final base = (_payment?.paymentDate ?? widget.clock()).year;
    final years = {for (var y = base - 2; y <= base + 2; y++) y, year}.toList()..sort();
    final line = l.line;
    final err = l.error;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Bill ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (_lines.length > 1)
              IconButton(key: Key('fee-bill-line-$i-remove'), tooltip: 'Remove bill line', onPressed: _busy ? null : () => _removeLine(i), icon: const Icon(Icons.delete_outline)),
          ]),
          Wrap(spacing: 12, runSpacing: 4, children: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<int>(
                key: Key('fee-bill-line-$i-month'),
                initialValue: month,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Billing month *'),
                items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(FeeMonth.names[m - 1]))],
                onChanged: _busy ? null : (v) => setState(() => l.month = FeeMonth.of(year, v ?? month)),
              ),
            ),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<int>(
                key: Key('fee-bill-line-$i-year'),
                initialValue: year,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Year *'),
                items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
                onChanged: _busy ? null : (v) => setState(() => l.month = FeeMonth.of(v ?? year, month)),
              ),
            ),
          ]),
          DropdownButtonFormField<String>(
            key: Key('fee-bill-line-$i-class'),
            initialValue: l.className.isEmpty ? null : l.className,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Class shown on this bill', helperText: 'For this bill only: the student\'s class is not changed.'),
            items: [for (final c in _classOptions(l)) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                      l.className = v ?? l.className;
                      _reviewing = false;
                    }),
          ),
          TextField(
            key: Key('fee-bill-line-$i-description'),
            controller: l.description,
            enabled: !_busy,
            maxLength: FeeBillLine.maxDescription,
            decoration: const InputDecoration(labelText: 'Description or fee particulars *', counterText: ''),
            onChanged: (_) => setState(() => _reviewing = false),
          ),
          TextField(
            key: Key('fee-bill-line-$i-gross'),
            controller: l.gross,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Gross bill amount (₹) *'),
            onChanged: (_) => setState(() => _reviewing = false),
          ),
          Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.end, children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<FeeBillAdjustmentType>(
                key: Key('fee-bill-line-$i-adjustment-type'),
                initialValue: l.type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Bill-only adjustment'),
                items: [for (final t in FeeBillAdjustmentType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: _busy
                    ? null
                    : (v) => setState(() {
                          l.type = v ?? FeeBillAdjustmentType.none;
                          if (l.type == FeeBillAdjustmentType.none) l.adjustment.text = '0';
                          _reviewing = false;
                        }),
              ),
            ),
            if (l.type != FeeBillAdjustmentType.none)
              SizedBox(
                width: 160,
                child: TextField(
                  key: Key('fee-bill-line-$i-adjustment'),
                  controller: l.adjustment,
                  enabled: !_busy,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Adjustment (₹)'),
                  onChanged: (_) => setState(() => _reviewing = false),
                ),
              ),
          ]),
          if (l.type != FeeBillAdjustmentType.none)
            TextField(
              key: Key('fee-bill-line-$i-reason'),
              controller: l.reason,
              enabled: !_busy,
              maxLength: FeeBillLine.maxReason,
              decoration: const InputDecoration(
                labelText: 'Adjustment reason *',
                helperText: 'A bill-only adjustment: it changes this bill document only, never the fee, the payment or any balance.',
                helperMaxLines: 2,
                counterText: '',
              ),
              onChanged: (_) => setState(() => _reviewing = false),
            ),
          const SizedBox(height: 6),
          Text(
            line == null ? 'Net bill amount: -' : 'Net bill amount: ${billMoney(line.netPaise)}',
            key: Key('fee-bill-line-$i-net'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (err != null && (l.gross.text.isNotEmpty || l.description.text.isNotEmpty))
            Text(err, style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
        ]),
      ),
    );
  }

  Widget _summary(FeeBillPayment p) {
    final remaining = p.amountPaise - _billed - _newNet;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey.shade100), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        _row('Original payment', billMoney(p.amountPaise), key: const Key('fee-bill-summary-payment')),
        _row('Already billed (active bills)', billMoney(_billed), key: const Key('fee-bill-summary-billed')),
        _row('These bills (net)', billMoney(_newNet), key: const Key('fee-bill-summary-new'), bold: true),
        _row('Not yet billed after issuing', billMoney(remaining < 0 ? 0 : remaining),
            key: const Key('fee-bill-summary-remaining'), bold: true, color: remaining < 0 ? Colors.red.shade800 : (remaining == 0 ? Colors.green.shade800 : Colors.orange.shade900)),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Partly billed: ${billMoney(remaining)} of this payment will still have no bill.', style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
          ),
      ]),
    );
  }

  Widget _preview() => Column(
        key: const Key('fee-bill-preview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading('PREVIEW: ${_lines.length} ${_lines.length == 1 ? 'BILL' : 'SEPARATE BILLS'}'),
          for (final (i, l) in _lines.indexed)
            Card(
              child: ListTile(
                title: Text('${FeeMonth.label(l.month)} · ${l.description.text.trim()}'),
                subtitle: Text([
                  [
                    'Gross ${billMoney(l.line!.grossPaise)}',
                    if (l.line!.adjustmentPaise > 0) '${l.type.label} ${billMoney(l.line!.adjustmentPaise)} (${l.reason.text.trim()})',
                    'Net ${billMoney(l.line!.netPaise)}${_amountIncludesGst ? ' (GST Included)' : ''}',
                  ].join(' · '),
                  [
                    if (_issueDates[l.month] case final d?) 'Issue date ${_date.format(d)}',
                    if (l.className.isNotEmpty) 'Class ${l.className}',
                    if (_parent != null) '${ReceiptParent.labelOf(_parent!.relation)}: ${_parent!.name}',
                  ].join(' · '),
                ].join('\n'), key: Key('fee-bill-preview-details-$i')),
                trailing: TextButton(key: Key('fee-bill-preview-pdf-$i'), onPressed: _busy ? null : () => _previewPdf(i), child: const Text('Preview PDF')),
              ),
            ),
          Text(
            'Issue dates are the first working day of each billing month (school calendar holidays and weekends excluded).'
            '${_showGstin ? ' GSTIN ${_billSchool.gstin} is shown.' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      );

  Widget _result(List<FeeIssuedBill> issued) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${issued.length} ${issued.length == 1 ? 'bill was' : 'bills were'} issued. No payment or Finance record was changed.',
              style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final b in issued)
            Card(
              key: Key('fee-bill-issued-${b.billNo}'),
              child: ListTile(
                title: Text('Bill Reference ${b.billNo} · ${FeeMonth.label(b.line.billingMonth)}'),
                subtitle: Text('${b.line.description} · Net ${billMoney(b.line.netPaise)}'),
                trailing: TextButton.icon(
                  key: Key('fee-bill-download-${b.billNo}'),
                  onPressed: () => _download(b),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('PDF'),
                ),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final issued = _issued;
    final p = _payment;
    final validation = _loading || issued != null ? null : _validation;
    return AlertDialog(
      title: const Text('Issue Fee Bills'),
      content: SizedBox(
        width: 620,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: issued != null
                    ? _result(issued)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                            child: const Text(
                              'Bills are supplementary documents issued against a payment already collected in Fees. '
                              'Issuing them does not create a payment or receipt and does not change any fee balance or Finance record.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          _heading('1. STUDENT'),
                          _studentStep(),
                          if (_student != null) ...[_heading('2. ORIGINAL PAYMENT'), _paymentStep()],
                          if (p != null) ...[
                            const SizedBox(height: 8),
                            _paymentDetails(p),
                            _heading('3. BILL LINES (ONE BILL EACH)'),
                            for (final (i, l) in _lines.indexed) _lineEditor(i, l),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(key: const Key('fee-bill-add-line'), onPressed: _busy ? null : _addLine, icon: const Icon(Icons.add), label: const Text('Add bill line')),
                            ),
                            _heading('4. GST (OPTIONAL)'),
                            CheckboxListTile(
                              key: const Key('fee-bill-show-gstin'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _showGstin,
                              onChanged: _busy ? null : (v) => setState(() {
                                    _showGstin = v ?? false;
                                    _reviewing = false;
                                  }),
                              title: const Text('Show GSTIN on bill'),
                              subtitle: const Text('Prints the school\'s GSTIN in the header. It does not add or calculate GST.'),
                            ),
                            CheckboxListTile(
                              key: const Key('fee-bill-amount-includes-gst'),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _amountIncludesGst,
                              onChanged: _busy ? null : (v) => setState(() {
                                    _amountIncludesGst = v ?? false;
                                    _reviewing = false;
                                  }),
                              title: const Text('Amount includes GST'),
                              subtitle: const Text('Shows "(GST Included)" beside the net bill amount. The amount is not changed and no GST is calculated.'),
                            ),
                            if (_parent != null)
                              Text('${ReceiptParent.labelOf(_parent!.relation)} on the bills: ${_parent!.name}', key: const Key('fee-bill-parent'), style: const TextStyle(fontSize: 12)),
                            _heading('5. ALLOCATION'),
                            _summary(p),
                            if (_reviewing && validation == null) _preview(),
                          ],
                          if (_error != null || (p != null && validation != null && (_showGstin || _lines.any((l) => l.gross.text.isNotEmpty))))
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(_error ?? validation!, key: const Key('fee-bill-error'), style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
                            ),
                        ],
                      ),
              ),
      ),
      actions: issued != null
          ? [FilledButton(key: const Key('fee-bill-close'), onPressed: () => Navigator.pop(context, true), child: const Text('Done'))]
          : [
              TextButton(key: const Key('fee-bill-cancel'), onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
              if (!_reviewing)
                OutlinedButton(
                  key: const Key('fee-bill-review'),
                  onPressed: _busy || validation != null ? null : _startReview,
                  child: const Text('Preview'),
                )
              else
                FilledButton(
                  key: const Key('fee-bill-issue'),
                  onPressed: _busy || validation != null ? null : _issue,
                  child: Text(_busy ? 'Issuing...' : 'Issue Bills'),
                ),
            ],
    );
  }
}

/// Bytes of [b]'s PDF, for callers outside the dialogs.
Future<Uint8List> feeBillPdfBytes(FeeIssuedBill b, {SchoolLogoLoader? loadLogo, DateTime? reprintedAt}) async =>
    FeeBillPdf.build(b, reprintedAt: reprintedAt, logo: loadLogo == null ? null : await loadLogo(b.school.logoUrl));
