import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../models/finance_reconciliation_model.dart';
import '../../services/finance_service.dart';

const _bad = Color(0xFFD32F2F);
const _good = Color(0xFF2E7D5B);

String _rupees(double v) => '${(v * 100).round() < 0 ? '-' : ''}₹${v.abs().toStringAsFixed(0)}';

/// Read-only check of every account (FinanceService.reconcileAccounts):
/// its stored running balance beside the balance its ledger gives, the
/// difference, negative balances, and ledger entries whose account is
/// missing. It corrects nothing.
class AccountReconciliationDialog extends StatefulWidget {
  const AccountReconciliationDialog({super.key, required this.service});

  final FinanceService service;

  @override
  State<AccountReconciliationDialog> createState() => _AccountReconciliationDialogState();
}

class _AccountReconciliationDialogState extends State<AccountReconciliationDialog> {
  late Future<FinanceReconciliation> _result = widget.service.reconcileAccounts();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 600;
    return Dialog(
      key: const Key('finance-reconciliation'),
      insetPadding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 8),
              child: Row(children: [
                const Expanded(child: Text('Check account balances', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                IconButton(
                  key: const Key('finance-reconciliation-refresh'),
                  tooltip: 'Check again',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => setState(() {
                    _result = widget.service.reconcileAccounts();
                  }),
                ),
                IconButton(key: const Key('finance-reconciliation-close'), tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<FinanceReconciliation>(
                future: _result,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Padding(
                      key: Key('finance-reconciliation-error'),
                      padding: EdgeInsets.all(24),
                      child: Text('The balances could not be checked. Try again.', style: TextStyle(color: _bad)),
                    );
                  }
                  // A new check shows its own result, never the previous one.
                  if (snap.connectionState != ConnectionState.done || !snap.hasData) {
                    return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                  }
                  final r = snap.data!;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Summary(result: r),
                        const SizedBox(height: 12),
                        for (final group in const ['Cash', 'Bank', 'UPI', 'Other'])
                          if (r.accounts.where((a) => a.group == group).isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(group, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            ),
                            for (final a in r.accounts.where((a) => a.group == group)) _AccountRow(account: a, narrow: narrow),
                          ],
                        if (r.problems.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            '${r.problems.length} transaction${r.problems.length == 1 ? '' : 's'} with a missing account',
                            key: const Key('finance-reconciliation-problems'),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: _bad),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Their amounts are in no account’s balance (they are shown as Unclassified).',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          for (final p in r.problems)
                            Padding(
                              key: Key('finance-reconciliation-problem-${p.entryId}'),
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${p.title.isEmpty ? 'Transaction' : p.title} · ${p.entryType == 'income' ? '+' : '-'}${_rupees(p.amount)}'
                                '${p.transactionDate == null ? '' : ' · ${DateFormat('dd MMM yyyy').format(p.transactionDate!)}'}'
                                ' · ${p.hasNoAccount ? 'no account' : 'account “${p.accountName.isEmpty ? p.accountId : p.accountName}” no longer exists'}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                        ],
                        const SizedBox(height: 14),
                        const Text(
                          'Stored is the running balance kept on the account, changed by each transaction. Calculated is its opening balance plus its '
                          'transactions in the ledger (cancelled ones left out), the figure Finance shows. Read only: nothing is corrected here.',
                          key: Key('finance-reconciliation-note'),
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.result});
  final FinanceReconciliation result;

  @override
  Widget build(BuildContext context) {
    final mismatched = result.mismatched.length;
    final negative = result.negative.length;
    final lines = [
      if (mismatched > 0) '$mismatched account${mismatched == 1 ? '' : 's'} where the stored and calculated balances differ.',
      if (negative > 0) '$negative account${negative == 1 ? ' is' : 's are'} below zero.',
      if (result.problems.isNotEmpty) '${result.problems.length} transaction${result.problems.length == 1 ? '' : 's'} with a missing account.',
    ];
    final ok = lines.isEmpty;
    final color = ok ? _good : _bad;
    return Container(
      key: Key(ok ? 'finance-reconciliation-ok' : 'finance-reconciliation-issues'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(ok ? 'Every account’s stored balance matches its ledger.' : lines.join(' '), style: TextStyle(fontSize: 13, color: color))),
      ]),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.narrow});
  final AccountReconciliation account;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final a = account;
    Widget figure(String label, double value, {Key? key, Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Text(_rupees(value), key: key, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? AppColors.textPrimary)),
          ],
        );
    final figures = [
      figure('Stored', a.storedBalance, key: Key('finance-reconciliation-${a.accountId}-stored')),
      figure('Calculated', a.calculatedBalance, key: Key('finance-reconciliation-${a.accountId}-calculated'), color: a.isNegative ? _bad : null),
      figure('Difference', a.difference, key: Key('finance-reconciliation-${a.accountId}-difference'), color: a.matches ? _good : _bad),
    ];
    return Container(
      key: Key('finance-reconciliation-${a.accountId}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Colors.black.withValues(alpha: 0.08)), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(a.name.isEmpty ? 'Account' : a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (!a.isActive) const Text('inactive', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            if (a.isNegative) const Text('below zero', key: Key('finance-reconciliation-negative'), style: TextStyle(fontSize: 11, color: _bad, fontWeight: FontWeight.w600)),
            if (!a.matches) const Text('differs', style: TextStyle(fontSize: 11, color: _bad, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: narrow ? 16 : 32, runSpacing: 6, children: figures),
          const SizedBox(height: 4),
          Text(
            'Opening ${_rupees(a.openingBalance)}'
            '${a.openingBalanceDate != null ? ' from ${DateFormat('dd MMM yyyy').format(a.openingBalanceDate!)}' : ''}'
            ' · ${a.entryCount} transaction${a.entryCount == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          if (a.hasUndatedOpeningBalance)
            Text(
              'Opening date not set: historical month-end balances count its opening balance from the beginning.',
              key: Key('finance-reconciliation-${a.accountId}-opening-undated'),
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFB26A00)),
            ),
        ],
      ),
    );
  }
}
