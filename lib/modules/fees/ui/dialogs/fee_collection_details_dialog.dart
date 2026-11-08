import 'package:flutter/material.dart';

import '../../../../core/widgets/responsive_dialog_shell.dart';
import '../../models/fee_collection_record.dart';
import '../../models/fee_month.dart';
import '../../models/student_fee_assignment_model.dart';
import '../../services/fee_service.dart';
import '../../widgets/fee_payment_tile.dart';
import 'fee_receipt_view_dialog.dart';

/// Fees -> Collections -> View Details: one fee assignment and every
/// payment recorded against it. Read-only: it reads the assignment the
/// Collections row already has and the assignment's own fee receipts
/// (FeeService.getCollectionHistory), and writes nothing. Collect, Edit
/// and Void stay in their existing places.
class FeeCollectionDetailsDialog extends StatefulWidget {
  const FeeCollectionDetailsDialog({
    super.key,
    required this.assignment,
    required this.service,
    this.isMonthlyStructure = false,
    this.today,
  });

  /// Today, for the Overdue label (defaults to now).
  final DateTime? today;

  final StudentFeeAssignmentModel assignment;
  final FeeService service;

  /// Whether the assignment's structure is Monthly, so an assignment with
  /// no recorded month is shown as "Month not recorded".
  final bool isMonthlyStructure;

  @override
  State<FeeCollectionDetailsDialog> createState() => _FeeCollectionDetailsDialogState();
}

class _FeeCollectionDetailsDialogState extends State<FeeCollectionDetailsDialog> {
  late final Future<List<FeeCollectionRecord>> _history = widget.service.getCollectionHistory(widget.assignment.id);

  StudentFeeAssignmentModel get _a => widget.assignment;

  Widget _row(String label, String value, {Key? key, bool bold = false, Color? color}) =>
      FeeDetailRow(label, value, key: key, bold: bold, color: color);

  Widget _section(String title, List<Widget> children, {Key? key}) => Container(
        key: key,
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );

  Widget _assignmentSection() {
    final month = _a.feeMonth.isNotEmpty ? FeeMonth.label(_a.feeMonth) : (widget.isMonthlyStructure ? 'Month not recorded' : null);
    return _section('Student and assignment', key: const Key('collection-details-assignment'), [
      _row('Student', _a.studentName, bold: true),
      _row('Admission No', _a.admissionNo.isEmpty ? '-' : _a.admissionNo),
      _row('Class', _a.className.isEmpty ? '-' : _a.className),
      _row('Fee structure', _a.feeStructureName),
      _row('Academic year', _a.academicYear.isEmpty ? '-' : _a.academicYear),
      FeeDueDateRow(assignment: _a, today: widget.today ?? DateTime.now(), keyPrefix: 'collection-details'),
      if (month != null)
        _row(
          'Fee month',
          month,
          key: Key(_a.feeMonth.isEmpty ? 'collection-details-month-legacy' : 'collection-details-month'),
          color: _a.feeMonth.isEmpty ? Colors.orange.shade900 : null,
        ),
      if (month != null && _a.feeMonth.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'This assignment was made before fee months were recorded. Set its month with Edit in Assignments.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
    ]);
  }

  Widget _summarySection(List<FeeCollectionRecord>? history) {
    final receiptsTotal = history?.where((r) => r.counts).fold<double>(0, (sum, r) => sum + r.receipt.amount);
    final mismatch = receiptsTotal != null && (receiptsTotal * 100).round() != (_a.paidAmount * 100).round();
    return _section('Financial summary', key: const Key('collection-details-summary'), [
      _row('Original fee', formatFeeMoney(_a.totalFee), key: const Key('collection-details-total-fee')),
      _row('Discount', formatFeeMoney(_a.discountAmount), key: const Key('collection-details-discount')),
      if (_a.studentDiscount case final snap?) ...[
        _row('Student discount', snap.label, key: const Key('collection-details-student-discount')),
        _row('Manual discount', formatFeeMoney(_a.manualDiscountAmount), key: const Key('collection-details-manual-discount')),
      ],
      _row('Final payable', formatFeeMoney(_a.payableAmount), key: const Key('collection-details-payable'), bold: true),
      _row('Total collected', formatFeeMoney(_a.paidAmount), key: const Key('collection-details-paid'), color: Colors.green.shade800),
      _row(
        'Outstanding',
        formatFeeMoney(_a.balanceAmount),
        key: const Key('collection-details-balance'),
        bold: true,
        color: _a.balanceAmount > 0 ? Colors.red.shade800 : null,
      ),
      if (mismatch)
        Padding(
          key: const Key('collection-details-total-mismatch'),
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'The completed payments listed below total ${formatFeeMoney(receiptsTotal)}, but this assignment records '
            '${formatFeeMoney(_a.paidAmount)} collected. The figures above are the assignment\'s recorded amounts; '
            'some payments may have been recorded before receipts were linked to assignments.',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
          ),
        ),
    ]);
  }

  Future<void> _openReceipt(FeeCollectionRecord record) => showDialog<void>(
        context: context,
        builder: (_) => FeeReceiptViewDialog(receipt: record.receipt, service: widget.service, voided: record.isVoided),
      );

  Widget _historySection(AsyncSnapshot<List<FeeCollectionRecord>> snapshot) {
    final List<Widget> children;
    if (snapshot.hasError) {
      children = [
        const Text(
          'The payment history could not be loaded. Close this and try again.',
          key: Key('collection-details-error'),
          style: TextStyle(color: Colors.red),
        ),
      ];
    } else if (!snapshot.hasData) {
      children = [const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))];
    } else {
      final history = snapshot.data!;
      final completed = history.where((r) => r.counts).toList();
      final cancelled = history.length - completed.length;
      final total = completed.fold<double>(0, (sum, r) => sum + r.receipt.amount);
      children = history.isEmpty
          ? [const Text('No payments recorded yet.', key: Key('collection-details-empty'), style: TextStyle(color: Colors.black54))]
          : [
              Text(
                '${history.length} ${history.length == 1 ? 'payment' : 'payments'}: ${completed.length} completed, '
                'totalling ${formatFeeMoney(total)}${cancelled == 0 ? '' : '; $cancelled cancelled, not counted'}.',
                key: const Key('collection-details-receipts-total'),
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 10),
              for (final record in history)
                FeePaymentTile(
                  record: record,
                  expectedStudentId: _a.studentId,
                  expectedFeeMonth: _a.feeMonth,
                  onViewReceipt: () => _openReceipt(record),
                ),
            ];
    }
    return _section('Collection history', key: const Key('collection-details-history'), children);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      key: const Key('collection-details'),
      desktopWidth: 640,
      desktopHeight: 760,
      title: 'Collection Details',
      content: FutureBuilder<List<FeeCollectionRecord>>(
        future: _history,
        builder: (context, snapshot) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _assignmentSection(),
            _summarySection(snapshot.data),
            _historySection(snapshot),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('collection-details-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
