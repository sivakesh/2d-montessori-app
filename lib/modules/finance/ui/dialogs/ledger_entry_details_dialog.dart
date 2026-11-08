import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/finance_income_model.dart';
import '../../models/finance_ledger_entry_model.dart';
import '../../models/ledger_period.dart';

const _expenseColor = Color(0xFFD32F2F);

/// Currency as the rest of Finance shows it (whole rupees).
String _rupees(double amount) => '₹${amount.toStringAsFixed(0)}';

/// A payment mode as stored ('bank_transfer', 'upi') in words.
String _paymentMode(String mode) {
  final m = mode.trim();
  if (m.isEmpty) return '';
  if (m.toLowerCase() == 'upi') return 'UPI';
  final words = m.replaceAll('_', ' ').toLowerCase();
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

/// Every available detail of one Finance -> Ledger transaction, read only,
/// with the existing actions for it:
/// - income entered in Finance: Edit and Void (the Income tab's own
///   dialogs: [onEditIncome], [onVoidIncome]);
/// - income recorded by a Fee Collection: Open in Fees ([onOpenInFees],
///   that collection's own Edit in Fees) and Void Fee Collection (the Fees
///   void, through [onVoidIncome]); never Finance's Edit, which can't
///   change it;
/// - an expense invoice payment: Reverse payment (the Expenses tab's
///   [onReversePayment]).
/// Direct expenses and salary payments have no edit workflow, and cancelled
/// entries no action. Fields with no value are left out. Closes with the
/// close button, Escape or a tap outside.
class LedgerEntryDetailsDialog extends StatefulWidget {
  const LedgerEntryDetailsDialog({
    super.key,
    required this.entry,
    required this.findLinkedIncome,
    this.onEditIncome,
    this.onVoidIncome,
    this.onReversePayment,
    this.onOpenAttachment,
    this.onOpenInFees,
  });

  final FinanceLedgerEntryModel entry;

  /// The `finance_income` record [entry] mirrors, if any.
  final Future<FinanceIncomeModel?> Function(String ledgerEntryId) findLinkedIncome;
  final ValueChanged<FinanceIncomeModel>? onEditIncome;
  final ValueChanged<FinanceIncomeModel>? onVoidIncome;
  final ValueChanged<FinanceIncomeModel>? onReversePayment;
  final ValueChanged<String>? onOpenAttachment;

  /// Opens the Fee Collection (fee receipt) with this id in Fees.
  final ValueChanged<String>? onOpenInFees;

  @override
  State<LedgerEntryDetailsDialog> createState() => _LedgerEntryDetailsDialogState();
}

class _LedgerEntryDetailsDialogState extends State<LedgerEntryDetailsDialog> {
  late final Future<FinanceIncomeModel?> _linked = _find();

  Future<FinanceIncomeModel?> _find() async {
    try {
      return await widget.findLinkedIncome(widget.entry.id);
    } catch (_) {
      // The details still show; only the linked fields and actions are left out.
      return null;
    }
  }

  FinanceLedgerEntryModel get e => widget.entry;
  bool get _isIncome => e.entryType == 'income';
  bool get _cancelled => e.status == 'cancelled';

  String get _source => switch (e.sourceModule) {
        'fees' => 'Fee collection',
        'finance' => _isIncome ? 'Income entered in Finance' : 'Expense entered in Finance',
        'invoice' => e.categoryId == 'salary' ? 'Salary invoice payment' : 'Expense invoice payment',
        'salary' => 'Salary payment',
        'manual' => 'Manual entry',
        final s => s,
      };

  /// What `subCategoryName` holds for this kind of entry.
  String get _subCategoryLabel => switch ((e.sourceModule, _isIncome)) {
        ('finance', false) => 'Vendor',
        ('finance', true) => 'Program',
        _ => 'Sub-category',
      };

  /// Income entered in Finance (not by Fees or an invoice payment): the
  /// only income FinanceService.updateIncome edits.
  static bool _isManualIncome(FinanceIncomeModel income) => const {'', 'finance'}.contains(income.sourceModule) && income.programType != 'invoice';

  void _then(ValueChanged<FinanceIncomeModel>? action, FinanceIncomeModel income) {
    Navigator.of(context).pop();
    action?.call(income);
  }

  @override
  Widget build(BuildContext context) {
    final color = _isIncome ? AppColors.primary : _expenseColor;
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 600;
    final date = DateFormat('dd MMM yyyy');
    final dateTime = DateFormat('dd MMM yyyy, h:mm a');
    final title = e.title.trim().isEmpty ? 'Transaction' : e.title.trim();
    final notes = e.description.trim() == e.title.trim() ? '' : e.description.trim();
    final mode = _paymentMode(e.paymentMode);

    return Dialog(
      key: const Key('ledger-detail'),
      insetPadding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(_isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Container(
                            key: const Key('ledger-detail-type'),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                            child: Text(_isIncome ? 'Income' : 'Expense', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                          ),
                          if (_cancelled)
                            Container(
                              key: const Key('ledger-detail-cancelled'),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                              child: const Text('Cancelled', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                            ),
                        ]),
                        const SizedBox(height: 6),
                        Text(title, key: const Key('ledger-detail-title'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          '${_isIncome ? '+' : '-'}${_rupees(e.amount)}',
                          key: const Key('ledger-detail-amount'),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _cancelled ? AppColors.textSecondary : color,
                            decoration: _cancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('ledger-detail-close'),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                key: const Key('ledger-detail-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: FutureBuilder<FinanceIncomeModel?>(
                  future: _linked,
                  builder: (context, snap) {
                    final linked = snap.data;
                    final party = linked?.studentName.trim() ?? '';
                    final partyLabel = e.sourceModule == 'fees' ? 'Student' : (_isIncome ? 'Payer' : 'Paid to');
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_cancelled && linked != null && !linked.isDeleted && linked.sourceModule == 'fees')
                          _DetailNote(
                            key: const Key('ledger-detail-fees-note'),
                            text: linked.sourceId.isEmpty
                                ? 'Recorded by a Fee Collection, which can’t be identified from here. Change it in Fees, which updates this entry.'
                                : 'Recorded by a Fee Collection. To change it, open it in Fees, which updates this entry.',
                          ),
                        if (_cancelled)
                          const _DetailNote(
                            key: Key('ledger-detail-cancelled-note'),
                            text: 'Cancelled: not counted in any total, profit/loss or balance. The record is kept for audit.',
                          ),
                        _DetailRow(field: 'date', label: 'Transaction date', value: e.transactionDate == null ? '' : date.format(e.transactionDate!)),
                        _DetailRow(field: 'category', label: 'Category', value: e.categoryName),
                        _DetailRow(field: 'subcategory', label: _subCategoryLabel, value: e.subCategoryName),
                        _DetailRow(field: 'party', label: partyLabel, value: party),
                        _DetailRow(field: 'class', label: 'Class', value: linked?.className ?? ''),
                        _DetailRow(field: 'account', label: 'Account', value: e.accountName),
                        _DetailRow(field: 'payment-mode', label: 'Payment method', value: mode.toLowerCase() == e.accountName.trim().toLowerCase() ? '' : mode),
                        _DetailRow(field: 'reference', label: 'Reference number', value: e.referenceNo),
                        _DetailRow(field: 'invoice', label: 'Invoice number', value: e.invoiceNo),
                        _DetailRow(field: 'notes', label: 'Notes', value: notes),
                        _DetailRow(field: 'source', label: 'Recorded from', value: _source),
                        if (e.attachmentUrls.isNotEmpty)
                          _DetailRow(
                            field: 'attachments',
                            label: 'Attachments',
                            value: '${e.attachmentUrls.length}',
                            child: Wrap(spacing: 4, children: [
                              for (final (i, url) in e.attachmentUrls.indexed)
                                TextButton.icon(
                                  key: Key('ledger-detail-attachment-$i'),
                                  onPressed: widget.onOpenAttachment == null ? null : () => widget.onOpenAttachment!(url),
                                  icon: const Icon(Icons.attach_file, size: 16),
                                  label: Text('Attachment ${i + 1}'),
                                ),
                            ]),
                          ),
                        _DetailRow(field: 'created', label: 'Created', value: e.createdAt == null ? '' : dateTime.format(e.createdAt!)),
                        _DetailRow(field: 'updated', label: 'Last updated', value: e.updatedAt == null ? '' : dateTime.format(e.updatedAt!)),
                        _DetailRow(field: 'created-by', label: 'Created by', value: e.createdBy),
                        _DetailRow(field: 'id', label: 'Ledger entry ID', value: e.id),
                      ],
                    );
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: FutureBuilder<FinanceIncomeModel?>(
                future: _linked,
                builder: (context, snap) {
                  final linked = snap.data;
                  final active = linked != null && !linked.isDeleted && !_cancelled;
                  final isManualIncome = active && _isIncome && _isManualIncome(linked);
                  final isFeeIncome = active && _isIncome && linked.sourceModule == 'fees';
                  final isExpensePayment = active && !_isIncome && e.sourceModule == 'invoice' && e.categoryId == 'expense';
                  return Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if ((isManualIncome || isFeeIncome) && widget.onVoidIncome != null)
                        TextButton.icon(
                          key: const Key('ledger-detail-void'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => _then(widget.onVoidIncome, linked),
                          icon: const Icon(Icons.block, size: 18),
                          label: Text(linked.sourceModule == 'fees' ? 'Void Fee Collection' : 'Void'),
                        ),
                      if (isExpensePayment && widget.onReversePayment != null)
                        TextButton.icon(
                          key: const Key('ledger-detail-reverse'),
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          onPressed: () => _then(widget.onReversePayment, linked),
                          icon: const Icon(Icons.undo, size: 18),
                          label: const Text('Reverse payment'),
                        ),
                      if (isFeeIncome && linked.sourceId.isNotEmpty && widget.onOpenInFees != null)
                        OutlinedButton.icon(
                          key: const Key('ledger-detail-open-in-fees'),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onOpenInFees!(linked.sourceId);
                          },
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Open in Fees'),
                        ),
                      if (isManualIncome && widget.onEditIncome != null)
                        OutlinedButton.icon(
                          key: const Key('ledger-detail-edit'),
                          onPressed: () => _then(widget.onEditIncome, linked),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit'),
                        ),
                      FilledButton(
                        key: const Key('ledger-detail-done'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailNote extends StatelessWidget {
  const _DetailNote({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      );
}

/// One label/value line; nothing when [value] is empty. Label beside the
/// value, or above it on a narrow dialog.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.field, required this.label, required this.value, this.child});
  final String field;
  final String label;
  final String value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    const labelStyle = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    final valueWidget = child ?? SelectableText(value.trim(), key: Key('ledger-detail-$field-value'), style: const TextStyle(fontSize: 14, color: AppColors.textPrimary));
    return Padding(
      key: Key('ledger-detail-$field'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth < 380
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: labelStyle), const SizedBox(height: 2), valueWidget])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 150, child: Text(label, style: labelStyle)),
                Expanded(child: valueWidget),
              ]),
      ),
    );
  }
}

/// Choose a month and year for the Ledger, or All time. Pops the chosen
/// [LedgerPeriod], or null (cancelled).
class LedgerMonthPickerDialog extends StatefulWidget {
  const LedgerMonthPickerDialog({super.key, required this.initial, required this.now});

  final LedgerPeriod initial;
  final DateTime now;

  @override
  State<LedgerMonthPickerDialog> createState() => _LedgerMonthPickerDialogState();
}

class _LedgerMonthPickerDialogState extends State<LedgerMonthPickerDialog> {
  late int _year = widget.initial.year ?? widget.now.year;

  @override
  Widget build(BuildContext context) {
    final months = DateFormat.MMM();
    return AlertDialog(
      key: const Key('ledger-month-picker'),
      title: const Text('Choose a month'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(key: const Key('ledger-year-previous'), tooltip: 'Previous year', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _year--)),
                SizedBox(width: 80, child: Text('$_year', key: const Key('ledger-picker-year'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(key: const Key('ledger-year-next'), tooltip: 'Next year', icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _year++)),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var m = 1; m <= 12; m++)
                  () {
                    final selected = widget.initial == LedgerPeriod.month(_year, m);
                    final label = Text(months.format(DateTime(_year, m)));
                    void choose() => Navigator.of(context).pop(LedgerPeriod.month(_year, m));
                    return selected
                        ? FilledButton(key: Key('ledger-month-$m'), style: FilledButton.styleFrom(padding: EdgeInsets.zero), onPressed: choose, child: label)
                        : OutlinedButton(key: Key('ledger-month-$m'), style: OutlinedButton.styleFrom(padding: EdgeInsets.zero), onPressed: choose, child: label);
                  }(),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(key: const Key('ledger-picker-all-time'), onPressed: () => Navigator.of(context).pop(const LedgerPeriod.allTime()), child: const Text('All time')),
        TextButton(key: const Key('ledger-picker-cancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}
