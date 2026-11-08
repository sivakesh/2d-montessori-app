import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fee_collection_record.dart';
import '../models/fee_due_date.dart';
import '../models/fee_month.dart';
import '../models/student_fee_assignment_model.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
String formatFeeMoney(num value) => _money.format(value);

/// Payment mode as the Collect Fee dialog stores it, for display.
String paymentModeLabel(String mode) => switch (mode) {
      'cash' => 'Cash',
      'upi' => 'UPI',
      'bank_transfer' => 'Bank Transfer',
      'cheque' => 'Cheque',
      'other' => 'Other',
      '' => '-',
      _ => mode,
    };

/// An assignment's due date for a detail view: "5 Jan 2027", "Due date
/// not set", and an Overdue label when FeeDueDate.isOverdue on [today].
class FeeDueDateRow extends StatelessWidget {
  const FeeDueDateRow({super.key, required this.assignment, required this.today, this.keyPrefix = 'fee'});

  final StudentFeeAssignmentModel assignment;
  final DateTime today;

  /// Keys: `<prefix>-due-date-<id>` and `<prefix>-overdue-<id>`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final due = assignment.dueDate;
    final overdue = FeeDueDate.isOverdue(assignment, today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FeeDetailRow(
          'Due date',
          due == null ? 'Due date not set' : FeeDueDate.label(due),
          key: Key('$keyPrefix-due-date-${assignment.id}'),
          color: overdue ? Colors.red.shade800 : (due == null ? Colors.black54 : null),
        ),
        if (overdue)
          Container(
            key: Key('$keyPrefix-overdue-${assignment.id}'),
            margin: const EdgeInsets.only(left: 140, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(20)),
            child: Text(
              'Overdue • outstanding ${formatFeeMoney(assignment.balanceAmount)}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade800),
            ),
          ),
      ],
    );
  }
}

/// A label/value line used by the read-only Fees detail views.
class FeeDetailRow extends StatelessWidget {
  const FeeDetailRow(this.label, this.value, {super.key, this.bold = false, this.color});

  final String label, value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 140, child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54))),
            Expanded(
              child: Text(value, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
            ),
          ],
        ),
      );
}

/// One payment (fee receipt) in a read-only Fees view: amount, status
/// (Completed, or Cancelled (voided), struck through), date, receipt no.,
/// method, reference, notes, a warning when the receipt's own student or
/// month disagrees with its assignment, and View Receipt.
///
/// Keys (by receipt id): `collection-payment-<id>`,
/// `collection-payment-amount-<id>`, `collection-payment-status-<id>`,
/// `collection-payment-mismatch-<id>`, `collection-receipt-<id>`.
class FeePaymentTile extends StatelessWidget {
  const FeePaymentTile({
    super.key,
    required this.record,
    required this.onViewReceipt,
    this.expectedStudentId = '',
    this.expectedFeeMonth = '',
  });

  final FeeCollectionRecord record;
  final VoidCallback onViewReceipt;

  /// The assignment's student and month, checked against the receipt's
  /// own copies ('' skips the check).
  final String expectedStudentId, expectedFeeMonth;

  /// Why the receipt's own copy of the student or month disagrees with its
  /// assignment, or null. Shown, never corrected.
  String? get _mismatch {
    final r = record.receipt;
    if (r.studentId.isNotEmpty && expectedStudentId.isNotEmpty && r.studentId != expectedStudentId) {
      return 'This receipt names a different student (${r.studentName}). Review it before relying on it.';
    }
    if (r.feeMonth.isNotEmpty && expectedFeeMonth.isNotEmpty && r.feeMonth != expectedFeeMonth) {
      return 'This receipt is for ${FeeMonth.label(r.feeMonth)}, not ${FeeMonth.label(expectedFeeMonth)}. Review it before relying on it.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = record.receipt;
    final voided = record.isVoided;
    final date = r.paymentDate;
    final mismatch = _mismatch;
    final muted = voided ? Colors.black45 : null;
    return Container(
      key: Key('collection-payment-${r.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: voided ? Colors.grey.shade100 : Colors.white,
        border: Border.all(color: voided ? Colors.red.shade100 : Colors.black.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatFeeMoney(r.amount),
                key: Key('collection-payment-amount-${r.id}'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: muted,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
              Container(
                key: Key('collection-payment-status-${r.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: voided ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  voided ? 'Cancelled (voided)' : 'Completed',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: voided ? Colors.red.shade800 : Colors.green.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FeeDetailRow('Date', date == null ? 'Date not recorded' : DateFormat('d MMM yyyy').format(date)),
          FeeDetailRow('Receipt No', r.receiptNo.isEmpty ? '-' : r.receiptNo),
          FeeDetailRow('Payment method', paymentModeLabel(r.paymentMode)),
          if (r.referenceNo.isNotEmpty) FeeDetailRow('Reference', r.referenceNo),
          if (record.remarks.isNotEmpty) FeeDetailRow('Notes', record.remarks),
          if (voided)
            FeeDetailRow(
              'Voided',
              '${record.voidedAt == null ? '' : '${DateFormat('d MMM yyyy').format(record.voidedAt!)} • '}not counted in Total collected',
              color: Colors.red.shade800,
            ),
          if (mismatch != null)
            Padding(
              key: Key('collection-payment-mismatch-${r.id}'),
              padding: const EdgeInsets.only(top: 4),
              child: Text(mismatch, style: TextStyle(fontSize: 12, color: Colors.orange.shade900)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('collection-receipt-${r.id}'),
              onPressed: onViewReceipt,
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('View Receipt'),
            ),
          ),
        ],
      ),
    );
  }
}
