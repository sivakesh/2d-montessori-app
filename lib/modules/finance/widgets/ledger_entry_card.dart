import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
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

  static const _expenseColor = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.entryType == 'income';
    final color = isIncome ? AppColors.primary : _expenseColor;
    final sign = isIncome ? '+' : '-';

    String joinNonEmpty(List<String> values, String separator) {
      final filtered = values.where((v) => v.trim().isNotEmpty).toList();
      return filtered.join(separator);
    }

    // Account name doubles as "where the payment mode went" (Cash/Bank/UPI
    // accounts already mirror the payment mode), so category + account
    // covers category/payment-mode/account without repeating the same
    // information three times.
    final metaLine = joinNonEmpty([entry.categoryName, entry.accountName], ' • ');
    final dateValue = entry.transactionDate ?? entry.createdAt;
    final dateLine = dateValue != null ? DateFormat('dd MMM yyyy').format(dateValue) : '';
    final refLine = entry.referenceNo.trim().isNotEmpty ? 'Ref: ${entry.referenceNo.trim()}' : '';
    final remarksLine = entry.description.trim().isNotEmpty && entry.description.trim() != entry.title.trim()
        ? entry.description.trim()
        : '';
    // Every listed entry is implicitly "confirmed" — only surface the status
    // chip for exceptions (e.g. cancelled) instead of repeating it on every row.
    final showStatus = entry.status.isNotEmpty && entry.status != 'confirmed';

    return Container(
      padding: const EdgeInsets.all(16),
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
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title.trim().isEmpty ? 'Transaction' : entry.title.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (metaLine.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    metaLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
                if (dateLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dateLine,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                if (refLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    refLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                if (remarksLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    remarksLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                if (showStatus || onCancel != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showStatus)
                        FinanceStatusChip(
                          label: entry.status,
                          color: entry.status == 'cancelled' ? Colors.grey : color,
                        ),
                      if (onCancel != null)
                        TextButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Cancel'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$sign₹${entry.amount.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color),
          ),
        ],
      ),
    );
  }
}
