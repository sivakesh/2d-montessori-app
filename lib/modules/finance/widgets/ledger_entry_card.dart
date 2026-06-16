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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: color),
        ),
        title: Text(entry.title.isEmpty ? '-' : entry.title),
        subtitle: Text(
          '${entry.categoryName} • ${entry.accountName}\n${entry.paymentMode} • ${entry.referenceNo.isEmpty ? '-' : entry.referenceNo}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('₹${entry.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            FinanceStatusChip(
              label: entry.status,
              color: entry.status == 'cancelled' ? Colors.grey : color,
            ),
          ],
        ),
      ),
    );
  }
}
