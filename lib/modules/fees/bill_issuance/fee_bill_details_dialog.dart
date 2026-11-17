import 'dart:math' show max;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fee_month.dart';
import '../services/fee_receipt_regeneration.dart' show ReceiptParent, ReceiptPdfSaver;
import '../ui/dialogs/fee_receipt_regenerate_dialog.dart' show SchoolLogoLoader;
import 'fee_bill_models.dart';
import 'fee_bill_pdf.dart';
import 'fee_bill_service.dart';

/// One issued bill: its stored details (never edited), Download PDF and
/// Reprint (same Bill Reference and contents), the linked original payment as
/// it is now (read only), its history, and, for an administrator, Cancel
/// or Cancel and Reissue (a replacement gets a new Bill Reference).
///
/// Keys: `fee-bill-details-` + `status`, `download`, `reprint`,
/// `payment`, `history`, `history-list`, `cancel`, `close`,
/// `allocations` (a bill supported by several payments); the cancel
/// dialog: `fee-bill-cancel-reason`, `fee-bill-cancel-reissue`,
/// `fee-bill-reissue-gross`, `fee-bill-reissue-description`,
/// `fee-bill-reissue-adjustment-type`, `fee-bill-reissue-adjustment`,
/// `fee-bill-reissue-reason`, `fee-bill-reissue-alloc-<receiptId>`,
/// `fee-bill-cancel-confirm`.
class FeeBillDetailsDialog extends StatefulWidget {
  const FeeBillDetailsDialog({
    super.key,
    required this.bill,
    required this.service,
    required this.role,
    required this.loadLogo,
    required this.savePdf,
    this.clock = DateTime.now,
  });

  final FeeIssuedBill bill;
  final FeeBillService service;
  final String role;
  final SchoolLogoLoader loadLogo;
  final ReceiptPdfSaver savePdf;
  final DateTime Function() clock;

  @override
  State<FeeBillDetailsDialog> createState() => _FeeBillDetailsDialogState();
}

class _FeeBillDetailsDialogState extends State<FeeBillDetailsDialog> {
  late FeeIssuedBill _bill = widget.bill;
  /// Each supporting payment as recorded in Fees now, with its allocation
  /// record (read only), primary first.
  List<(FeeBillPaymentAllocation, FeeBillPayment?, FeeBillAllocation?)>? _live;
  bool _paymentShown = false, _busy = false;
  List<Map<String, dynamic>>? _history;
  String? _message;

  static final _date = DateFormat('d MMM yyyy');
  static final _dateTime = DateFormat('d MMM yyyy, HH:mm');

  bool get _isAdmin => widget.role.toLowerCase() == 'admin';

  Future<void> _pdf({required bool reprint}) async {
    setState(() => _busy = true);
    try {
      final now = widget.clock();
      final bytes = await FeeBillPdf.build(_bill, reprintedAt: reprint ? now : null, logo: await widget.loadLogo(_bill.school.logoUrl));
      await widget.savePdf(bytes, FeeBillPdf.fileName(_bill));
      if (reprint) await widget.service.recordReprint(requesterRole: widget.role, billId: _bill.id);
      if (mounted) setState(() => _message = reprint ? 'Reprint of ${_bill.billNo} downloaded.' : 'PDF of ${_bill.billNo} downloaded.');
      if (_history != null) await _loadHistory();
    } catch (e) {
      if (mounted) setState(() => _message = '$e'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showPayment() async {
    setState(() => _paymentShown = true);
    final live = [
      for (final a in _bill.allocations) (a, await widget.service.getPayment(a.receiptId), await widget.service.getAllocation(a.receiptId)),
    ];
    if (mounted) setState(() => _live = live);
  }

  Future<void> _loadHistory() async {
    final h = await widget.service.history(_bill.id);
    if (mounted) setState(() => _history = h);
  }

  Future<void> _cancel() async {
    final result = await showDialog<FeeIssuedBill?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CancelBillDialog(bill: _bill, service: widget.service, role: widget.role),
    );
    if (result == null || !mounted) return;
    final refreshed = await widget.service.getBill(_bill.id);
    if (!mounted) return;
    setState(() {
      if (refreshed != null) _bill = refreshed;
      _message = result.id == _bill.id
          ? 'Bill ${_bill.billNo} was cancelled. Its amount is available to bill again.'
          : 'Bill ${_bill.billNo} was cancelled and replaced by ${result.billNo}.';
      _history = null;
      _paymentShown = false;
    });
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 190, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
          Expanded(child: Text(value.isEmpty ? '-' : value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
        ]),
      );

  static String _when(Object? v) => v is Timestamp ? _dateTime.format(v.toDate()) : v is DateTime ? _dateTime.format(v) : '';

  static String _historyLine(Map<String, dynamic> h) {
    final at = _when(h['at']);
    final by = h['by']?.toString() ?? '';
    return switch (h['action']) {
      'issued' => 'Issued ${h['billNo'] ?? ''}: gross ${billMoney((h['grossPaise'] as num?)?.toInt() ?? 0)}'
          '${((h['adjustmentPaise'] as num?)?.toInt() ?? 0) > 0 ? ', ${FeeBillAdjustmentType.of(h['adjustmentType']).label.toLowerCase()} ${billMoney((h['adjustmentPaise'] as num).toInt())} (${h['adjustmentReason']})' : ''}'
          ', net ${billMoney((h['netPaise'] as num?)?.toInt() ?? 0)}${_allocationsText(h['allocations'])} · $at · $by',
      'cancelled' => 'Cancelled: ${h['reason'] ?? ''}${h['replacedBy'] == null ? '' : ' (replaced by ${h['replacedBy']})'} · '
          '${billMoney((h['releasedPaise'] as num?)?.toInt() ?? 0)} released${_allocationsText(h['released'])} · $at · $by',
      'reprinted' => 'Reprinted · $at · $by',
      final a => '$a · $at · $by',
    };
  }

  /// " (REC-1 ₹5,000.00, REC-2 ₹7,500.00)" for a history entry's payments
  /// when there were several; '' otherwise.
  static String _allocationsText(Object? list) {
    final items = [for (final a in (list as List? ?? const [])) if (a is Map) '${a['receiptNo']} ${billMoney((a['allocatedPaise'] as num?)?.toInt() ?? 0)}'];
    return items.length > 1 ? ' (${items.join(', ')})' : '';
  }

  @override
  Widget build(BuildContext context) {
    final b = _bill;
    return AlertDialog(
      title: Text('Bill Reference ${b.billNo}', key: const Key('fee-bill-details-reference')),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Container(
              key: const Key('fee-bill-details-status'),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: b.isCancelled ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(
                b.isCancelled
                    ? 'CANCELLED${b.cancelledAt == null ? '' : ' on ${_date.format(b.cancelledAt!)}'} by ${b.cancelledBy}: ${b.cancellationReason}'
                    : 'Issued. A bill document only: the original receipt and payment are unchanged.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: b.isCancelled ? Colors.red.shade900 : Colors.green.shade900),
              ),
            ),
            const SizedBox(height: 8),
            if (b.parentName.isNotEmpty) _row(ReceiptParent.labelOf(b.parentRelation), b.parentName),
            _row('Student', b.payment.studentName),
            _row('Admission No', b.payment.admissionNo),
            _row('Class', b.payment.className),
            _row('Billing month', FeeMonth.label(b.line.billingMonth)),
            _row('Item description', b.line.description),
            _row('Gross amount', billMoney(b.line.grossPaise)),
            if (b.line.adjustmentPaise > 0) ...[
              _row('Bill-only adjustment', '${b.line.adjustmentType.label}: ${billMoney(b.line.adjustmentPaise)}'),
              _row('Adjustment reason', b.line.adjustmentReason),
            ],
            _row('Net bill amount', '${billMoney(b.line.netPaise)}${b.amountIncludesGst ? ' ${FeeBillPdf.gstIncludedLabel}' : ''}', bold: true),
            if (b.school.gstin.isNotEmpty) _row('GSTIN shown', b.school.gstin),
            _row('Issue date', b.documentDate == null ? '' : _date.format(b.documentDate!)),
            _row('Issued on', b.issuedAt == null ? '' : _date.format(b.issuedAt!)),
            _row('Issued by', b.issuedBy),
            _row('Receipt Reference', FeeBillPdf.receiptReference(b)),
            if (b.isMultiPayment)
              Container(
                key: const Key('fee-bill-details-allocations'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(border: Border.all(color: Colors.blueGrey.shade100), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Payment allocation (${b.allocations.length} payments; Bill Reference from ${b.payment.receiptNo}, the earliest)',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  for (final a in b.allocations) _row('${a.receiptNo} · ${a.paymentDate == null ? '-' : _date.format(a.paymentDate!)}', billMoney(a.allocatedPaise)),
                  _row('Total allocated', billMoney(b.allocatedPaise), bold: true),
                ]),
              )
            else ...[
              _row('Original payment date', b.payment.paymentDate == null ? '' : _date.format(b.payment.paymentDate!)),
              _row('Original payment reference', b.payment.referenceNo),
            ],
            if (b.replacesBillId.isNotEmpty) _row('Replaces', b.replacesBillId.split('_').last),
            if (b.replacedByBillId.isNotEmpty) _row('Replaced by', b.replacedByBillId.split('_').last),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton.icon(key: const Key('fee-bill-details-download'), onPressed: _busy ? null : () => _pdf(reprint: false), icon: const Icon(Icons.download, size: 18), label: const Text('Download PDF')),
              OutlinedButton.icon(key: const Key('fee-bill-details-reprint'), onPressed: _busy || !_isAdmin ? null : () => _pdf(reprint: true), icon: const Icon(Icons.print, size: 18), label: const Text('Reprint')),
              OutlinedButton.icon(
                  key: const Key('fee-bill-details-payment'),
                  onPressed: _showPayment,
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: Text(b.isMultiPayment ? 'Original payments' : 'Original payment')),
              OutlinedButton.icon(key: const Key('fee-bill-details-history'), onPressed: _loadHistory, icon: const Icon(Icons.history, size: 18), label: const Text('History')),
            ]),
            if (_paymentShown)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: _live == null
                    ? const Text('Loading the original payment...')
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Original payment${_live!.length > 1 ? 's' : ''} (as recorded in Fees now; read only)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        for (final (i, (a, live, alloc)) in _live!.indexed) ...[
                          if (i > 0) const Divider(height: 12),
                          if (live == null)
                            _row('Receipt number', '${a.receiptNo} (no longer found in Fees)')
                          else ...[
                            _row('Receipt number', live.receiptNo),
                            _row('Status', live.voided ? 'Voided in Fees' : 'Active'),
                            _row('Amount received', billMoney(live.amountPaise)),
                            _row('Payment date', live.paymentDate == null ? '' : _date.format(live.paymentDate!)),
                            _row('Payment mode', live.paymentMode),
                            _row('Payment reference', live.referenceNo),
                            if (_live!.length > 1) _row('Used by this bill', billMoney(a.allocatedPaise)),
                            if (alloc != null) ...[
                              _row('Billed by active bills', billMoney(alloc.allocatedPaise)),
                              _row('Not yet billed', billMoney(max(0, live.amountPaise - alloc.allocatedPaise))),
                            ],
                          ],
                        ],
                      ]),
              ),
            if (_history case final h?)
              Container(
                key: const Key('fee-bill-details-history-list'),
                margin: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('History', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  if (h.isEmpty) const Text('No history recorded.'),
                  for (final e in h) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_historyLine(e), style: const TextStyle(fontSize: 12))),
                ]),
              ),
            if (_message != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_message!, style: const TextStyle(fontSize: 12))),
          ]),
        ),
      ),
      actions: [
        if (_isAdmin && !b.isCancelled)
          TextButton(
            key: const Key('fee-bill-details-cancel'),
            onPressed: _busy ? null : _cancel,
            child: Text('Cancel bill', style: TextStyle(color: Colors.red.shade800)),
          ),
        FilledButton(key: const Key('fee-bill-details-close'), onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

/// Cancel a bill (reason required), optionally issuing a corrected
/// replacement with a new number. Pops the replacement, or the cancelled
/// bill itself when there is none; null when nothing was done.
class _CancelBillDialog extends StatefulWidget {
  const _CancelBillDialog({required this.bill, required this.service, required this.role});

  final FeeIssuedBill bill;
  final FeeBillService service;
  final String role;

  @override
  State<_CancelBillDialog> createState() => _CancelBillDialogState();
}

class _CancelBillDialogState extends State<_CancelBillDialog> {
  final _reason = TextEditingController();
  bool _reissue = false, _busy = false;
  String? _error;
  late final _description = TextEditingController(text: widget.bill.line.description);
  late final _gross = TextEditingController(text: rupeesText(widget.bill.line.grossPaise));
  late final _adjustment = TextEditingController(text: rupeesText(widget.bill.line.adjustmentPaise));
  late final _adjReason = TextEditingController(text: widget.bill.line.adjustmentReason);
  late FeeBillAdjustmentType _type = widget.bill.line.adjustmentType;

  /// A bill supported by several payments: how much of each the
  /// replacement uses (prefilled with the cancelled bill's allocations,
  /// which the cancellation releases).
  late final Map<String, TextEditingController> _alloc = {
    if (widget.bill.isMultiPayment)
      for (final a in widget.bill.allocations) a.receiptId: TextEditingController(text: rupeesText(a.allocatedPaise)),
  };

  @override
  void dispose() {
    for (final c in [_reason, _description, _gross, _adjustment, _adjReason, ..._alloc.values]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The replacement's allocations (several payments), or null while one
  /// isn't a valid amount.
  Map<String, int>? get _allocations {
    final out = <String, int>{};
    for (final e in _alloc.entries) {
      final t = e.value.text.trim();
      final v = t.isEmpty ? 0 : parseRupees(t);
      if (v == null) return null;
      if (v > 0) out[e.key] = v;
    }
    return out;
  }

  FeeBillLine? get _line {
    final g = parseRupees(_gross.text), a = _type == FeeBillAdjustmentType.none ? 0 : parseRupees(_adjustment.text);
    if (g == null || a == null) return null;
    return FeeBillLine(
      billingMonth: widget.bill.line.billingMonth,
      description: _description.text,
      grossPaise: g,
      adjustmentType: _type,
      adjustmentPaise: a,
      adjustmentReason: _adjReason.text,
      className: widget.bill.payment.className,
    );
  }

  Future<void> _confirm() async {
    final line = _reissue ? _line : null;
    if (_reason.text.trim().isEmpty) return setState(() => _error = 'Enter the reason for cancelling this bill.');
    if (_reissue && line == null) return setState(() => _error = 'Enter valid amounts for the replacement bill.');
    if (line?.error case final e?) return setState(() => _error = 'Replacement: $e');
    Map<String, int>? allocations;
    if (line != null && _alloc.isNotEmpty) {
      allocations = _allocations;
      if (allocations == null) return setState(() => _error = 'Replacement: enter a valid amount for each payment (0 for none).');
      final total = allocations.values.fold<int>(0, (s, v) => s + v);
      if (total != line.netPaise) {
        return setState(() => _error = 'Replacement: its payment allocations total ${billMoney(total)}, but its net bill amount is ${billMoney(line.netPaise)}. They must be equal.');
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final replacement = await widget.service.cancelBill(
          requesterRole: widget.role, billId: widget.bill.id, reason: _reason.text, replacement: line, replacementAllocations: allocations);
      if (mounted) Navigator.pop(context, replacement ?? widget.bill);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e'.replaceFirst('Bad state: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bill;
    return AlertDialog(
      title: Text('Cancel bill ${b.billNo}?'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              'The bill is kept, marked cancelled, with your reason, and its net amount (${billMoney(b.line.netPaise)}) can be billed again'
              '${b.isMultiPayment ? ': each of its ${b.allocations.length} payments gets back exactly what this bill used of it' : ''}. '
              'Issued bills are never edited: to correct one, cancel it and issue a replacement, which gets a new Bill Reference. '
              'The payment, its receipt and Finance are not changed.',
              style: const TextStyle(fontSize: 12),
            ),
            TextField(key: const Key('fee-bill-cancel-reason'), controller: _reason, enabled: !_busy, maxLength: FeeBillService.maxReason, decoration: const InputDecoration(labelText: 'Reason for cancelling *', counterText: '')),
            CheckboxListTile(
              key: const Key('fee-bill-cancel-reissue'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _reissue,
              onChanged: _busy ? null : (v) => setState(() => _reissue = v ?? false),
              title: Text('Issue a replacement bill for ${FeeMonth.label(b.line.billingMonth)}'),
            ),
            if (_reissue) ...[
              TextField(key: const Key('fee-bill-reissue-description'), controller: _description, enabled: !_busy, decoration: const InputDecoration(labelText: 'Description or fee particulars *')),
              TextField(key: const Key('fee-bill-reissue-gross'), controller: _gross, enabled: !_busy, decoration: const InputDecoration(labelText: 'Gross bill amount (₹) *')),
              DropdownButtonFormField<FeeBillAdjustmentType>(
                key: const Key('fee-bill-reissue-adjustment-type'),
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Bill-only adjustment'),
                items: [for (final t in FeeBillAdjustmentType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: _busy ? null : (v) => setState(() => _type = v ?? FeeBillAdjustmentType.none),
              ),
              if (_type != FeeBillAdjustmentType.none) ...[
                TextField(key: const Key('fee-bill-reissue-adjustment'), controller: _adjustment, enabled: !_busy, decoration: const InputDecoration(labelText: 'Adjustment (₹)')),
                TextField(key: const Key('fee-bill-reissue-reason'), controller: _adjReason, enabled: !_busy, decoration: const InputDecoration(labelText: 'Adjustment reason *')),
              ],
              if (_alloc.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Payments supporting the replacement (they must total its net amount)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                for (final a in b.allocations)
                  TextField(
                    key: Key('fee-bill-reissue-alloc-${a.receiptId}'),
                    controller: _alloc[a.receiptId],
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Uses of ${a.receiptNo} (₹)', isDense: true),
                  ),
              ],
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, key: const Key('fee-bill-cancel-error'), style: TextStyle(fontSize: 12, color: Colors.red.shade800))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Keep bill')),
        FilledButton(
          key: const Key('fee-bill-cancel-confirm'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: _busy ? null : _confirm,
          child: Text(_reissue ? 'Cancel and Reissue' : 'Cancel Bill'),
        ),
      ],
    );
  }
}
