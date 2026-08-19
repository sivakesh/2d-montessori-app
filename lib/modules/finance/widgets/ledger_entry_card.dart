import 'package:flutter/material.dart';

import '../models/finance_ledger_entry_model.dart';
import 'finance_status_chip.dart';

class LedgerEntryCard extends StatelessWidget {
  const LedgerEntryCard({
    super.key,
    required this.entry,
    this.onCancel,
  });

  final FinanceLedgerEntryModel entry;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.entryType == 'income';
    final color = isIncome ? const Color(0xFF2E7D32) : Colors.redAccent;
    String joinNonEmpty(List<String> values, String separator) {
      final filtered = values.where((v) => v.trim().isNotEmpty).toList();
      return filtered.join(separator);
    }

    final categoryPayment = joinNonEmpty([
      entry.categoryName,
      entry.paymentMode,
    ], ' • ');
    final refLine = entry.referenceNo.trim().isNotEmpty
        ? 'Reference No: ${entry.referenceNo.trim()}'
        : '';
    final remarksLine = entry.description.trim().isNotEmpty &&
            entry.description.trim() != entry.title.trim()
        ? 'Remarks: ${entry.description.trim()}'
        : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final amountText = Text(
              '₹${entry.amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            );
            final status = FinanceStatusChip(
              label: entry.status,
              color: entry.status == 'cancelled' ? Colors.grey : color,
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (onCancel != null)
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                  ),
              ],
            );

            final rightSection = compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      amountText,
                      const SizedBox(height: 6),
                      status,
                      if (onCancel != null) ...[
                        const SizedBox(height: 8),
                        actions,
                      ],
                    ],
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 150, maxWidth: 190),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(alignment: Alignment.centerRight, child: amountText),
                        const SizedBox(height: 6),
                        status,
                        if (onCancel != null) ...[
                          const SizedBox(height: 8),
                          actions,
                        ],
                      ],
                    ),
                  );

            final leftSection = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        entry.title.trim().isEmpty ? '-' : entry.title.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    if (compact) ...[
                      const SizedBox(width: 8),
                      amountText,
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                if (categoryPayment.isNotEmpty)
                  Text(
                    categoryPayment,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                if (refLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    refLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
                if (remarksLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    remarksLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.12),
                        child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: leftSection),
                    ],
                  ),
                  const SizedBox(height: 12),
                  rightSection,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(child: leftSection),
                const SizedBox(width: 12),
                Align(alignment: Alignment.topRight, child: rightSection),
              ],
            );
          },
        ),
      ),
    );
  }
}
