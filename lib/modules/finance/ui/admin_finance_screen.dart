import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/document_number_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../admin/ui/admin_fab.dart';
import '../../admin/ui/admin_layout.dart';
import '../../fees/services/fee_service.dart';
import '../models/finance_account_model.dart';
import '../models/finance_cancelled_transactions_model.dart';
import '../models/finance_category_model.dart';
import '../models/finance_dashboard_summary_model.dart';
import '../models/finance_invoice_model.dart';
import '../models/finance_income_model.dart';
import '../models/finance_ledger_entry_model.dart';
import '../models/vendor_model.dart';
import '../services/finance_service.dart';
import '../widgets/finance_status_chip.dart';
import '../widgets/finance_summary_card.dart';
import '../widgets/ledger_entry_card.dart';
import 'dialogs/add_account_dialog.dart';
import 'dialogs/add_category_dialog.dart';
import 'dialogs/add_expense_dialog.dart';
import 'dialogs/add_income_dialog.dart';
import 'dialogs/add_salary_payment_dialog.dart';
import 'dialogs/add_vendor_dialog.dart';

class AdminFinanceScreen extends StatefulWidget {
  const AdminFinanceScreen({super.key, FinanceService? service, FeeService? feeService, DocumentNumberService? numberService})
      : _service = service,
        _feeService = feeService,
        _numberService = numberService;

  final FinanceService? _service;

  /// Optional injection seam (tests): allocates expense invoice numbers in
  /// the Raise Expense Invoice dialog. Null keeps the dialog's own
  /// `DocumentNumberService()`.
  final DocumentNumberService? _numberService;

  /// Optional injection seam (tests). Used only to void Fee-Collection-
  /// sourced income entries through the Fees module's own void workflow.
  final FeeService? _feeService;

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  late final _service = widget._service ?? FinanceService();

  // Built only when a fee-linked entry is actually voided: FeeService's
  // constructor reaches Firebase Storage immediately, which nothing else on
  // this screen needs.
  FeeService? _defaultFeeService;
  FeeService get _feeService => widget._feeService ?? (_defaultFeeService ??= FeeService(financeService: _service));
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _service.ensureDefaults();
  }

  Future<void> _launch(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _openEditIncome(FinanceIncomeModel income) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddIncomeDialog(initial: income),
    );
  }

  /// Void-specific confirmation, distinct from a generic delete dialog:
  /// explains the actual effect (excluded from totals, record preserved)
  /// rather than "cannot be undone" — matching the wording convention
  /// established for Fee Collection void in the Fees module.
  Future<bool> _confirmVoidIncome(FinanceIncomeModel income) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void Income Entry'),
        content: Text(
          'Void "${income.title.isEmpty ? 'this entry' : income.title}" of '
          '₹${income.amount.toStringAsFixed(0)}? This will remove it from '
          'active Finance totals and reverse it out of the '
          '${income.accountName.isEmpty ? 'linked' : income.accountName} '
          'account balance. The original record is preserved for audit — '
          'it will no longer count as active income, but is not '
          'permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _voidIncome(FinanceIncomeModel income) async {
    if (income.sourceModule == 'fees') return _voidFeeLinkedIncome(income);
    if (!await _confirmVoidIncome(income)) return;
    try {
      await _service.voidIncome(income.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Income entry voided')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to void income entry: $e')),
        );
      }
    }
  }

  /// A Fee-Collection-sourced entry is never voided on the Finance side
  /// alone (FinanceService.voidIncome refuses it). Instead this runs the
  /// Fees module's own void (FeeService.voidReceipt) for the linked
  /// collection, which reverses this Finance entry and its ledger entry and
  /// restores the fee assignment balance — exactly what voiding it from
  /// Fees -> Collections does. voidReceipt checks both sides first: if the
  /// collection was already voided in Fees but this entry was left active
  /// (an earlier partial failure), only the Finance side is brought in
  /// line; missing, ambiguous or inconsistent records are refused before
  /// anything is written. A missing collection is reported up front.
  Future<void> _voidFeeLinkedIncome(FinanceIncomeModel income) async {
    void showMessage(String text) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }

    final collectionId = income.sourceId;
    final receipt = collectionId.isEmpty ? null : await _feeService.getReceiptById(collectionId);
    if (!mounted) return;
    if (receipt == null) {
      showMessage(
        'The linked Fee Collection could not be found, so this entry cannot be voided safely. '
        'Nothing was changed.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void Fee Collection'),
        content: Text(
          'This income was generated from Fee Collection '
          '${receipt.receiptNo.isEmpty ? '' : '${receipt.receiptNo} '}'
          '(₹${income.amount.toStringAsFixed(0)}'
          '${receipt.studentName.isEmpty ? '' : ' from ${receipt.studentName}'}). '
          'Voiding it voids that Fee Collection in Fees — adding the amount back '
          "to the student's outstanding fee balance — and cancels this Finance "
          'entry and its ledger entry. The original records are preserved for '
          'audit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final outcome = await _feeService.voidReceipt(collectionId, expectedFinanceIncomeId: income.id);
      showMessage(switch (outcome) {
        FeeVoidOutcome.voided => 'Fee Collection voided',
        FeeVoidOutcome.financeReconciled =>
          'The Fee Collection was already voided; this Finance entry has now been voided to match.',
      });
    } on FeeVoidException catch (e) {
      // Refused before anything was written; the message says what to do.
      showMessage(e.message);
    } catch (e) {
      showMessage('Failed to void Fee Collection: $e');
    }
  }

  Future<void> _showPayInvoice(FinanceInvoiceModel invoice) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PayInvoiceDialog(invoice: invoice, service: _service),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice payment saved')),
      );
    }
  }

  /// The Raise Expense Invoice dialog for both entry points (Expenses FAB
  /// and the empty-state button), on the same FinanceService as this screen
  /// — the one its Vendors list and invoice lists use.
  Widget _raiseExpenseDialog() => AddExpenseDialog(service: _service, numberService: widget._numberService);

  Future<void> _openEditExpenseInvoice(FinanceInvoiceModel invoice) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddExpenseDialog(initial: invoice, service: _service),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense invoice updated')),
      );
    }
  }

  /// An invoice with any recorded payment is never deleted — the user gets
  /// an explanation instead of a confirmation, so payment history and the
  /// ledger can't be orphaned. [FinanceService.deleteExpenseInvoice]
  /// enforces the same rule server-side.
  Future<void> _deleteExpenseInvoice(FinanceInvoiceModel invoice) async {
    final label = invoice.invoiceNo.isEmpty ? 'this invoice' : invoice.invoiceNo;
    if (invoice.paidAmount > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cannot Delete Invoice'),
          content: Text(
            '$label has ₹${invoice.paidAmount.toStringAsFixed(0)} in recorded '
            'payments. Invoices with payments cannot be deleted, so that '
            'payment history and the ledger stay intact.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Expense Invoice'),
        content: Text(
          'Delete $label for '
          '${invoice.partyName.isEmpty ? 'this vendor' : invoice.partyName} '
          '(₹${invoice.totalAmount.toStringAsFixed(0)})? This invoice has no '
          'payments. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteExpenseInvoice(invoice.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense invoice deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete expense invoice: $e')),
        );
      }
    }
  }

  /// Asks for a required reason. Returns null when the user backs out.
  Future<String?> _askReason({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title, message: message, confirmLabel: confirmLabel),
    );
  }

  /// Cancel keeps the invoice as an auditable record. Only possible once
  /// it has no active payments — the service enforces the same rule.
  Future<void> _cancelExpenseInvoice(FinanceInvoiceModel invoice) async {
    final label = invoice.invoiceNo.isEmpty ? 'this invoice' : invoice.invoiceNo;
    if (invoice.paidAmount > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cannot Cancel Invoice'),
          content: Text(
            '$label has ₹${invoice.paidAmount.toStringAsFixed(0)} in active '
            'payments. If a payment was recorded by mistake and no money '
            'moved, open the invoice and reverse that payment first. If the '
            'money was actually paid, the invoice cannot be cancelled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final reason = await _askReason(
      title: 'Cancel Expense Invoice',
      message: 'Cancel $label? It stays on record as Cancelled for audit, is '
          'removed from active expense totals, and can no longer be edited '
          'or paid. This cannot be undone.',
      confirmLabel: 'Cancel Invoice',
    );
    if (reason == null) return;
    try {
      await _service.cancelExpenseInvoice(id: invoice.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense invoice cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel expense invoice: $e')),
        );
      }
    }
  }

  /// For a payment recorded by mistake only. The original payment is kept
  /// (marked reversed) and its ledger entry cancelled — see
  /// FinanceService.reverseExpenseInvoicePayment.
  Future<void> _reverseExpensePayment(FinanceIncomeModel payment) async {
    final reason = await _askReason(
      title: 'Reverse Payment',
      message: 'Reverse this ₹${payment.amount.toStringAsFixed(0)} payment? '
          'Use this only if the payment was recorded by mistake and no money '
          'actually moved. The original record is kept and marked Reversed, '
          'its ledger entry is cancelled, and the invoice balance is restored.',
      confirmLabel: 'Reverse Payment',
    );
    if (reason == null) return;
    try {
      await _service.reverseExpenseInvoicePayment(paymentId: payment.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment reversed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reverse payment: $e')),
        );
      }
    }
  }

  // Settings manages both categories and accounts, so its FAB offers a
  // choice between the two existing add dialogs instead of picking one.
  Future<void> _showSettingsAddChoice(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Add Category'),
              onTap: () => Navigator.pop(sheetContext, 'category'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Add Account'),
              onTap: () => Navigator.pop(sheetContext, 'account'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'category') {
      await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddCategoryDialog());
    } else if (choice == 'account') {
      await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddAccountDialog());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 7,
      title: 'Finance',
      // Reports (tab 6) is a read-only placeholder with nothing to add.
      floatingActionButton: _tab == 6
          ? null
          : AdminFab(
              icon: Icons.add,
              onPressed: () async {
                switch (_tab) {
                  case 0:
                  case 1:
                    await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddIncomeDialog());
                    break;
                  case 2:
                    await showDialog(context: context, barrierDismissible: false, builder: (_) => _raiseExpenseDialog());
                    break;
                  case 3:
                    await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddSalaryPaymentDialog());
                    break;
                  case 4:
                    await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddVendorDialog());
                    break;
                  case 7:
                    await _showSettingsAddChoice(context);
                    break;
                }
              },
            ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Finance', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const ['Dashboard', 'Income', 'Expenses', 'Salary', 'Vendors', 'Ledger', 'Reports', 'Settings']
                    .asMap()
                    .entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value),
                          selected: _tab == e.key,
                          onSelected: (_) => setState(() => _tab = e.key),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 20),
              _buildBody(),
              const SizedBox(height: 24),
            ],
          ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case 1:
        return _IncomeTab(
          service: _service,
          launchUrlFn: _launch,
          onAddIncome: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const AddIncomeDialog()),
          onEdit: _openEditIncome,
          onVoid: _voidIncome,
        );
      case 2:
        return _ExpenseTab(
          service: _service,
          onPay: _showPayInvoice,
          onEdit: _openEditExpenseInvoice,
          onDelete: _deleteExpenseInvoice,
          onCancel: _cancelExpenseInvoice,
          onReversePayment: _reverseExpensePayment,
          onRaiseInvoice: () => showDialog(context: context, barrierDismissible: false, builder: (_) => _raiseExpenseDialog()),
        );
      case 3:
        return _SalaryTab(
          service: _service,
          onPay: _showPayInvoice,
          onRaiseInvoice: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const AddSalaryPaymentDialog()),
        );
      case 4:
        return _VendorTab(
          service: _service,
          onAddVendor: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const AddVendorDialog()),
        );
      case 5:
        return _LedgerTab(service: _service);
      case 6:
        return _ReportsTab();
      case 7:
        return _SettingsTab(service: _service);
      default:
        return _DashboardTab(service: _service, onViewAllTransactions: () => setState(() => _tab = 5));
    }
  }
}

const _warningColor = Color(0xFFB26A00);

/// Whether the Unclassified card/note is shown: when unclassified balances
/// or activity exist, even if they net to ₹0.
bool _showsUnclassified(FinanceDashboardSummaryModel summary) =>
    summary.hasUnclassifiedActivity || summary.unclassifiedBalance != 0;

/// Shown under the Cash/Bank/UPI cards on both the Dashboard and the
/// Ledger, straight from [FinanceDashboardSummaryModel] (nothing is
/// recalculated here): how the account balances add up to the Closing
/// Balance and, when there is one, what the unclassified amount is.
class _AccountBalancesReconciliation extends StatelessWidget {
  const _AccountBalancesReconciliation({required this.summary});

  final FinanceDashboardSummaryModel summary;

  @override
  Widget build(BuildContext context) {
    String amount(double v) => '₹${v.toStringAsFixed(0)}';
    final unclassified = summary.unclassifiedBalance;
    final showUnclassified = _showsUnclassified(summary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Closing Balance ${amount(summary.closingBalance)} = Cash ${amount(summary.cashBalance)}'
          ' + Bank ${amount(summary.bankBalance)} + UPI ${amount(summary.upiBalance)}'
          '${showUnclassified ? ' + Unclassified ${amount(unclassified)}' : ''}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (showUnclassified) ...[
          const SizedBox(height: 4),
          Text(
            '${amount(unclassified)} is not shown in Cash, Bank or UPI'
            '${unclassified == 0 ? ' (its opening balances and transactions net to ₹0)' : ''}: it is the opening balances '
            "and/or transactions of accounts whose type can't be classified as Cash, Bank or UPI, "
            'or whose account is missing'
            '${summary.unclassifiedOpeningBalance != 0 ? ' (includes ${amount(summary.unclassifiedOpeningBalance)} opening balance)' : ''}.',
            style: const TextStyle(fontSize: 12, color: _warningColor),
          ),
        ],
      ],
    );
  }
}

/// Dashboard card: how many unique transactions were cancelled/voided and
/// their original amount, from FinanceService.watchCancelledTransactions.
/// Informational only — those amounts are already excluded from every
/// total and balance above. Shows loading and failure explicitly rather
/// than a zero; tapping opens a read-only list.
class _CancelledTransactionsCard extends StatefulWidget {
  const _CancelledTransactionsCard({required this.service});

  final FinanceService service;

  @override
  State<_CancelledTransactionsCard> createState() => _CancelledTransactionsCardState();
}

class _CancelledTransactionsCardState extends State<_CancelledTransactionsCard> {
  late final Stream<FinanceCancelledTransactionsSummary> _summary = widget.service.watchCancelledTransactions();

  static const _accent = Color(0xFF607D8B);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FinanceCancelledTransactionsSummary>(
      stream: _summary,
      builder: (context, snap) {
        final data = snap.data;
        Widget metric(String value, String label) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.3),
                ),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            );
        final Widget body;
        if (snap.hasError) {
          body = const Text(
            "Couldn't load cancelled transactions. Reopen the Dashboard to try again.",
            style: TextStyle(fontSize: 13, color: _warningColor),
          );
        } else if (data == null) {
          body = const Text('Loading…', style: TextStyle(fontSize: 13, color: AppColors.textSecondary));
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 28,
                runSpacing: 8,
                children: [
                  metric('${data.count}', 'Cancelled count'),
                  metric('₹${data.originalAmount.toStringAsFixed(0)}', 'Original amount cancelled'),
                ],
              ),
              if (data.exclusions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${data.exclusions.length} record${data.exclusions.length == 1 ? '' : 's'} with an unclear status not counted',
                  style: const TextStyle(fontSize: 12, color: _warningColor),
                ),
              ],
            ],
          );
        }
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: data == null ? null : () => showDialog<void>(
                context: context,
                builder: (_) => _CancelledTransactionsDialog(summary: data),
              ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 112),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: _accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.block_outlined, color: _accent, size: 19),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Cancelled / Voided Transactions',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                body,
                const SizedBox(height: 8),
                const Text(
                  'Not included in any total or balance.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Type filter for the cancelled-transactions list, by
/// [FinanceCancelledTransaction.typeLabel]. Display only.
enum _CancelledTypeFilter {
  all('All', '', {}),
  income('Income', 'income', {'Manual income', 'Fee collection'}),
  expenses('Expenses', 'expense', {'Expense payment'}),
  salary('Salary', 'salary', {'Salary payment'});

  const _CancelledTypeFilter(this.label, this.noun, this.typeLabels);

  final String label;

  /// Used in the empty message, e.g. "No cancelled or voided income transactions."
  final String noun;
  final Set<String> typeLabels;

  bool includes(FinanceCancelledTransaction t) => this == all || typeLabels.contains(t.typeLabel);

  /// The non-All filter a transaction belongs to, if any (e.g. not an
  /// "Other (source)" type).
  static _CancelledTypeFilter? groupOf(FinanceCancelledTransaction t) {
    for (final f in values) {
      if (f != all && f.typeLabels.contains(t.typeLabel)) return f;
    }
    return null;
  }
}

class _CancelledTransactionsDialog extends StatefulWidget {
  const _CancelledTransactionsDialog({required this.summary});

  final FinanceCancelledTransactionsSummary summary;

  @override
  State<_CancelledTransactionsDialog> createState() => _CancelledTransactionsDialogState();
}

class _CancelledTransactionsDialogState extends State<_CancelledTransactionsDialog> {
  _CancelledTypeFilter _filter = _CancelledTypeFilter.all;
  final _search = TextEditingController();

  /// Kept here so the size survives a filter/search with no rows (which
  /// removes the pager); null until changed.
  int? _pageSize;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The row's own displayed text: heading, type, source, reference, linked
  /// receipt/invoice number and id, record and ledger ids, reason, status.
  static Iterable<String> _searchFields(FinanceCancelledTransaction t) => [
        t.title,
        t.typeLabel,
        _CancelledTypeFilter.groupOf(t)?.label ?? 'Other',
        t.sourceLabel,
        t.reference,
        t.linkedDocumentNumber,
        t.linkedDocumentId,
        t.id,
        t.ledgerId,
        t.reason,
        t.statusLabel,
      ];

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final query = _normalizeSearch(_search.text);
    final searching = query.isNotEmpty;
    // Count and amount below come from this filtered (type + search) list
    // only; the summary itself (and every total elsewhere) is unchanged.
    final shown = summary.transactions.where((t) => _filter.includes(t) && _matchesSearch(query, _searchFields(t))).toList();
    final shownAmount = shown.fold<double>(0, (total, t) => total + t.amount);
    final isAll = _filter == _CancelledTypeFilter.all;
    final countLabel = searching ? (isAll ? 'Matching' : 'Matching ${_filter.label}') : (isAll ? 'Counted' : _filter.label);
    String day(DateTime? d) => d == null ? 'Not recorded' : DateFormat('dd MMM yyyy').format(d);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              Expanded(child: Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
            ],
          ),
        );
    return ResponsiveDialogShell.form(
      desktopWidth: 560,
      desktopHeight: 620,
      title: 'Cancelled / Voided Transactions',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Each voided or reversed Finance record is counted once, at its original amount; its ledger line and '
            'Fees receipt are not counted again. These amounts are not included in any total or balance.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            key: const Key('cancelled-type-filter'),
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final f in _CancelledTypeFilter.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
          if (summary.transactions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _FinanceSearchField(
              keyPrefix: 'cancelled',
              controller: _search,
              hint: 'Search title, type, reference, receipt/invoice no. or ID',
              onChanged: (_) => setState(() {}),
            ),
          ],
          const Divider(height: 24),
          if (summary.transactions.isEmpty)
            const Text('No cancelled or voided transactions.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary))
          else if (shown.isEmpty && searching)
            Text(
              'No cancelled or voided ${isAll ? '' : '${_filter.noun} '}transactions match "${_search.text.trim()}".',
              key: const Key('cancelled-search-empty'),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            )
          else if (shown.isEmpty)
            Text(
              'No cancelled or voided ${_filter.noun} transactions.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          // Only the current page's rows are built; the count and amount
          // below stay over the complete filtered list.
          if (shown.isNotEmpty)
            _PagedList<FinanceCancelledTransaction>(
              keyPrefix: 'cancelled',
              items: shown,
              idOf: (t) => t.id,
              resetToken: (_filter, query),
              initialPageSize: _pageSize,
              onPageSizeChanged: (size) => _pageSize = size,
              itemBuilder: (t) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${t.typeLabel} • ${t.title}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        FinanceStatusChip(
                          label: (_CancelledTypeFilter.groupOf(t)?.label ?? 'Other').toUpperCase(),
                          color: const Color(0xFF607D8B),
                        ),
                        if (t.reviewNote.isNotEmpty) const FinanceStatusChip(label: 'NEEDS REVIEW', color: _warningColor),
                      ],
                    ),
                    row('Source', t.sourceLabel),
                    if (t.linkedDocumentLabel.isNotEmpty)
                      row(
                        t.linkedDocumentLabel,
                        t.linkedDocumentNumber.isNotEmpty
                            ? t.linkedDocumentNumber
                            : t.linkedDocumentFound
                                ? '${t.linkedDocumentLabel} number not recorded'
                                : '${t.linkedDocumentLabel} record not found',
                      ),
                    if (t.linkedDocumentLabel == 'Receipt' && t.linkedDocumentId.isNotEmpty) row('Collection ID', t.linkedDocumentId),
                    if (t.linkedDocumentLabel == 'Invoice' && t.linkedDocumentId.isNotEmpty) row('Invoice ID', t.linkedDocumentId),
                    if (t.linkedDocumentStatus.isNotEmpty) row('${t.linkedDocumentLabel} status', t.linkedDocumentStatus),
                    row('Reference', t.reference.isEmpty ? 'Reference not recorded' : t.reference),
                    row(t.linkedDocumentLabel == 'Receipt' ? 'Finance record ID' : 'Record ID', t.id),
                    row('Ledger entry', t.ledgerId.isEmpty ? 'None linked' : '${t.ledgerId} (${t.ledgerStatus.isEmpty ? 'not found' : t.ledgerStatus})'),
                    row('Original date', day(t.originalDate)),
                    row('Cancelled on', day(t.cancelledAt)),
                    row('Original amount', '₹${t.amount.toStringAsFixed(0)}'),
                    row('Reason', t.reason.isEmpty ? 'Not recorded' : t.reason),
                    row('Status', t.statusLabel),
                    if (t.reviewNote.isNotEmpty) row('Needs review', '${t.reviewNote}. Still counted: the voided Finance record is what totals used.'),
                  ],
                ),
              ),
            ),
          if (shown.isNotEmpty)
            Text(
              '$countLabel: ${shown.length} transaction${shown.length == 1 ? '' : 's'}, '
              '₹${shownAmount.toStringAsFixed(0)} in total — the sum of the amounts listed '
              '${shown.length > 10 ? 'on all pages' : 'above'}.'
              '${isAll && !searching ? '' : ' All types: ${summary.count}, ₹${summary.originalAmount.toStringAsFixed(0)}.'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          if (summary.exclusions.isNotEmpty) ...[
            const Divider(height: 24),
            const Text('Needs review — not counted', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _warningColor)),
            if (!isAll || searching)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  searching
                      ? 'Shown under every filter and search: their type or link is unclear.'
                      : 'Shown under every filter: their type or link is unclear.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
            for (final e in summary.exclusions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${e.title}: ${e.reason}. Record ID ${e.id} (${e.collection}).',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
          ],
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/// The Finance "Dashboard" tab: a premium at-a-glance overview built purely
/// from FinanceService's existing streams — no new business logic, no new
/// Firestore queries beyond the ones already used by the Expense/Salary tabs.
class _DashboardTab extends StatelessWidget {
  const _DashboardTab({required this.service, required this.onViewAllTransactions});

  final FinanceService service;
  final VoidCallback onViewAllTransactions;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<FinanceDashboardSummaryModel>(
      stream: service.watchDashboardSummary(),
      builder: (context, summarySnap) {
        final summary = summarySnap.data;
        return StreamBuilder<List<FinanceInvoiceModel>>(
          stream: service.watchInvoicesByType('expense'),
          builder: (context, expenseInvoicesSnap) {
            return StreamBuilder<List<FinanceInvoiceModel>>(
              stream: service.watchInvoicesByType('salary'),
              builder: (context, salaryInvoicesSnap) {
                final outstanding = _outstandingTotal(expenseInvoicesSnap.data) + _outstandingTotal(salaryInvoicesSnap.data);
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.fabScrollClearance),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardSectionHeader(title: 'Overview'),
                      const SizedBox(height: 12),
                      _ResponsiveCardGrid(
                        desktopColumns: 4,
                        tabletColumns: 2,
                        children: [
                          FinanceSummaryCard(
                            label: 'Total Income',
                            value: '₹${(summary?.totalIncome ?? 0).toStringAsFixed(0)}',
                            icon: Icons.trending_up,
                            color: AppColors.primary,
                          ),
                          FinanceSummaryCard(
                            label: 'Total Expenses',
                            value: '₹${(summary?.totalExpenses ?? 0).toStringAsFixed(0)}',
                            icon: Icons.trending_down,
                            color: const Color(0xFFD32F2F),
                          ),
                          FinanceSummaryCard(
                            label: 'Net Movement',
                            value: '₹${(summary?.netBalance ?? 0).toStringAsFixed(0)}',
                            icon: Icons.account_balance_wallet_outlined,
                            color: AppColors.secondary,
                          ),
                          FinanceSummaryCard(
                            label: 'Outstanding',
                            value: '₹${outstanding.toStringAsFixed(0)}',
                            icon: Icons.receipt_long_outlined,
                            color: const Color(0xFFB26A00),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _DashboardSectionHeader(title: 'Account Balances'),
                      const SizedBox(height: 12),
                      _ResponsiveCardGrid(
                        desktopColumns: 3,
                        tabletColumns: 2,
                        children: [
                          FinanceSummaryCard(
                            label: 'Cash',
                            value: '₹${(summary?.cashBalance ?? 0).toStringAsFixed(0)}',
                            icon: Icons.payments_outlined,
                            color: AppColors.primary,
                          ),
                          FinanceSummaryCard(
                            label: 'Bank',
                            value: '₹${(summary?.bankBalance ?? 0).toStringAsFixed(0)}',
                            icon: Icons.account_balance_outlined,
                            color: AppColors.secondary,
                          ),
                          FinanceSummaryCard(
                            label: 'UPI',
                            value: '₹${(summary?.upiBalance ?? 0).toStringAsFixed(0)}',
                            icon: Icons.qr_code_rounded,
                            color: const Color(0xFF5E35B1),
                          ),
                          if (summary != null && _showsUnclassified(summary))
                            FinanceSummaryCard(
                              label: 'Unclassified',
                              value: '₹${summary.unclassifiedBalance.toStringAsFixed(0)}',
                              icon: Icons.help_outline,
                              color: _warningColor,
                            ),
                        ],
                      ),
                      if (summary != null) _AccountBalancesReconciliation(summary: summary),
                      const SizedBox(height: 16),
                      _ResponsiveCardGrid(
                        desktopColumns: 3,
                        tabletColumns: 2,
                        children: [_CancelledTransactionsCard(service: service)],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Flexible so a narrow screen wraps the title
                          // instead of overflowing; "View all" keeps its size.
                          const Expanded(child: _DashboardSectionHeader(title: 'Recent Transactions')),
                          TextButton(
                            onPressed: onViewAllTransactions,
                            child: const Text('View all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      StreamBuilder<List<FinanceLedgerEntryModel>>(
                        stream: service.watchLedger(),
                        builder: (context, ledgerSnap) {
                          if (!ledgerSnap.hasData) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final items = ledgerSnap.data!;
                          if (items.isEmpty) {
                            return const _EmptyTransactions();
                          }
                          return Column(
                            children: items
                                .take(5)
                                .map((e) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: LedgerEntryCard(entry: e),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  double _outstandingTotal(List<FinanceInvoiceModel>? invoices) {
    if (invoices == null) return 0;
    return invoices.fold<double>(0, (total, invoice) => total + invoice.balanceAmount);
  }
}

class _DashboardSectionHeader extends StatelessWidget {
  const _DashboardSectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      );
}

/// Lays [children] out at up to [desktopColumns] per row, stepping down to
/// [tabletColumns] and finally a single column as width shrinks — the same
/// LayoutBuilder + Wrap responsive pattern already used elsewhere in the app
/// (e.g. the Fees dashboard cards).
class _ResponsiveCardGrid extends StatelessWidget {
  const _ResponsiveCardGrid({
    required this.children,
    required this.desktopColumns,
    required this.tabletColumns,
  });

  final List<Widget> children;
  final int desktopColumns;
  final int tabletColumns;

  static const _spacing = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? desktopColumns
            : constraints.maxWidth >= 640
                ? tabletColumns
                : 1;
        final cardWidth = (constraints.maxWidth - (_spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: children.map((child) => SizedBox(width: cardWidth, child: child)).toList(),
        );
      },
    );
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 36, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'No transactions yet',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Income and expenses will appear here once recorded.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Shared "Section title / supporting text" header used at the top of every
/// Finance tab, matching the Dashboard/Expenses typography exactly.
class _FinanceTabHeader extends StatelessWidget {
  const _FinanceTabHeader({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      );
}

/// Shared empty-state card (icon + title + supporting text + optional CTA)
/// used across the Finance tabs, matching the Dashboard's "No transactions
/// yet" card styling.
class _FinanceEmptyState extends StatelessWidget {
  const _FinanceEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          if (ctaLabel != null && onCta != null) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCta,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.add),
              label: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Finance "Income" tab: genuine income only (fee collections + manual
/// income entries). Built purely from the existing `watchIncome()` stream,
/// with the existing `programType != 'invoice'` filter that excludes
/// invoice-payment records that also live in the same collection.
///
/// The list is paged in the UI only (10/25/50 per page): Total Income and
/// Transactions are always from the full filtered list, and only the
/// current page's cards are built. The stream is held in state so changing
/// page doesn't resubscribe it.
class _IncomeTab extends StatefulWidget {
  const _IncomeTab({
    required this.service,
    required this.launchUrlFn,
    required this.onAddIncome,
    required this.onEdit,
    required this.onVoid,
  });
  final FinanceService service;
  final Future<void> Function(String) launchUrlFn;
  final VoidCallback onAddIncome;
  final ValueChanged<FinanceIncomeModel> onEdit;
  final ValueChanged<FinanceIncomeModel> onVoid;

  @override
  State<_IncomeTab> createState() => _IncomeTabState();
}

class _IncomeTabState extends State<_IncomeTab> {
  static const _pageSizes = [10, 25, 50];

  late Stream<List<FinanceIncomeModel>> _income = widget.service.watchIncome();
  int _pageSize = _pageSizes.first;
  int _page = 0;

  /// Ids of the last filtered list, in order; a different list sends the
  /// view back to the first page.
  List<String> _lastIds = const [];

  final _search = TextEditingController();

  /// Normalized query (see [_normalizeSearch]) the current page belongs to.
  String _lastQuery = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static Iterable<String> _searchFields(FinanceIncomeModel i) => [i.title, i.remarks, i.categoryName, i.referenceNo, i.studentName];

  @override
  void didUpdateWidget(covariant _IncomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) _income = widget.service.watchIncome();
  }

  @override
  Widget build(BuildContext context) {
    final onAddIncome = widget.onAddIncome;
    final onEdit = widget.onEdit;
    final onVoid = widget.onVoid;
    return StreamBuilder<List<FinanceIncomeModel>>(
      stream: _income,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        // finance_income also stores expense/salary invoice payments
        // (payInvoice writes programType: 'invoice' there); the Income tab
        // must only show actual income (fee collections, manual income).
        final items = snap.data!.where((i) => i.programType != 'invoice').toList();
        final totalIncome = items.fold<double>(0, (total, i) => total + i.amount);
        // Search filters the listed rows only; the cards use [items].
        final query = _normalizeSearch(_search.text);
        final shown = items.where((i) => _matchesSearch(query, _searchFields(i))).toList();

        final ids = [for (final i in shown) i.id];
        if (!listEquals(ids, _lastIds) || query != _lastQuery) {
          _lastIds = ids;
          _lastQuery = query;
          _page = 0;
        }
        final pageCount = shown.isEmpty ? 1 : (shown.length + _pageSize - 1) ~/ _pageSize;
        if (_page >= pageCount) _page = 0;
        final start = _page * _pageSize;
        final end = (start + _pageSize).clamp(0, shown.length);
        final pageItems = shown.sublist(start, end);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FinanceTabHeader(
              title: 'Income',
              subtitle: 'Fee collections and other income received by the school',
            ),
            const SizedBox(height: 16),
            _ResponsiveCardGrid(
              desktopColumns: 2,
              tabletColumns: 2,
              children: [
                FinanceSummaryCard(
                  label: 'Total Income',
                  value: '₹${totalIncome.toStringAsFixed(0)}',
                  icon: Icons.trending_up,
                  color: AppColors.primary,
                ),
                FinanceSummaryCard(
                  label: 'Transactions',
                  value: '${items.length}',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.secondary,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Income Transactions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              _FinanceEmptyState(
                icon: Icons.payments_outlined,
                title: 'No income yet',
                subtitle: 'Fee collections and other income will appear here.',
                ctaLabel: 'Add Income',
                onCta: onAddIncome,
              )
            else ...[
              _FinanceSearchField(
                keyPrefix: 'income',
                controller: _search,
                hint: 'Search description, category, reference or payer',
                onChanged: (_) => setState(() {}),
              ),
              if (shown.isEmpty) _FinanceSearchEmpty(keyPrefix: 'income', noun: 'income transactions', query: _search.text),
              if (shown.isNotEmpty) ...[
                Column(
                  children: pageItems
                      .map((i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _IncomeEntryCard(income: i, onEdit: onEdit, onVoid: onVoid),
                          ))
                      .toList(),
                ),
                Wrap(
                  key: const Key('income-pagination'),
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Showing ${start + 1}–$end of ${shown.length}',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Per page', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        DropdownButton<int>(
                          key: const Key('income-page-size'),
                          value: _pageSize,
                          underline: const SizedBox.shrink(),
                          items: [for (final size in _pageSizes) DropdownMenuItem(value: size, child: Text('$size'))],
                          // Keeps the current page if it still exists;
                          // otherwise back to the first page (see build).
                          onChanged: (size) => setState(() => _pageSize = size ?? _pageSize),
                        ),
                        IconButton(
                          tooltip: 'Previous page',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _page > 0 ? () => setState(() => _page--) : null,
                        ),
                        Text('Page ${_page + 1} of $pageCount', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        IconButton(
                          tooltip: 'Next page',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: _page < pageCount - 1 ? () => setState(() => _page++) : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// Presentation-only card for a [FinanceIncomeModel], matching
/// [LedgerEntryCard]'s visual language (icon circle, title, category •
/// account meta line, formatted date, prominent signed amount).
class _IncomeEntryCard extends StatelessWidget {
  const _IncomeEntryCard({required this.income, required this.onEdit, required this.onVoid});
  final FinanceIncomeModel income;
  final ValueChanged<FinanceIncomeModel> onEdit;
  final ValueChanged<FinanceIncomeModel> onVoid;

  @override
  Widget build(BuildContext context) {
    final isFeeSourced = income.sourceModule == 'fees';
    final metaLine = [income.categoryName, income.accountName].where((v) => v.trim().isNotEmpty).join(' • ');
    final dateLine = income.incomeDate != null ? DateFormat('dd MMM yyyy').format(income.incomeDate!) : '';
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
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.arrow_downward_rounded, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        income.title.trim().isEmpty ? 'Income' : income.title.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
                      ),
                    ),
                    if (isFeeSourced) ...[
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'From Fees',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ],
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
                  Text(dateLine, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '+₹${income.amount.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.primary),
          ),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => onEdit(income),
          ),
          // Only active entries are listed (watchIncome filters voided
          // ones). Fee-sourced entries are voided through their Fee
          // Collection (see _voidFeeLinkedIncome), never Finance-only.
          IconButton(
            tooltip: isFeeSourced ? 'Void Fee Collection' : 'Void',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.block, size: 20, color: Colors.red),
            onPressed: () => onVoid(income),
          ),
        ],
      ),
    );
  }
}

/// Free-text search over a Finance list (display only): the query is
/// trimmed and matched case-insensitively as a substring of any of the
/// row's [fields]. An empty query matches everything.
String _normalizeSearch(String query) => query.trim().toLowerCase();
bool _matchesSearch(String normalizedQuery, Iterable<String> fields, {Iterable<String> exactFields = const []}) =>
    normalizedQuery.isEmpty ||
    fields.any((f) => f.toLowerCase().contains(normalizedQuery)) ||
    exactFields.any((f) => f.toLowerCase() == normalizedQuery);

/// The search box above a Finance list: updates as you type and has a
/// Clear action. Keys: `<keyPrefix>-search`, `<keyPrefix>-search-clear`.
class _FinanceSearchField extends StatelessWidget {
  const _FinanceSearchField({required this.keyPrefix, required this.controller, required this.hint, required this.onChanged});

  final String keyPrefix;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key('$keyPrefix-search'),
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  key: Key('$keyPrefix-search-clear'),
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// "No … match "query"." shown when a search matches nothing.
class _FinanceSearchEmpty extends StatelessWidget {
  const _FinanceSearchEmpty({required this.keyPrefix, required this.noun, required this.query});

  final String keyPrefix;
  final String noun;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('$keyPrefix-search-empty'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'No $noun match "${query.trim()}".',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// A search box over a [_PagedList]. Keeps the query in its own state so
/// typing never rebuilds the parent tab (or re-subscribes its stream).
/// Only the displayed rows are filtered; the caller's totals keep using the
/// complete [items]. A query change returns to page 1 and keeps the page
/// size.
class _SearchablePagedList<T> extends StatefulWidget {
  const _SearchablePagedList({
    required this.keyPrefix,
    required this.items,
    required this.idOf,
    required this.searchFieldsOf,
    required this.itemBuilder,
    required this.hint,
    required this.noun,
    this.exactSearchFieldsOf,
  });

  final String keyPrefix;
  final List<T> items;
  final String Function(T item) idOf;
  final Iterable<String> Function(T item) searchFieldsOf;

  /// Optional values matched only by the whole query (e.g. a status, so
  /// "active" doesn't also match "inactive").
  final Iterable<String> Function(T item)? exactSearchFieldsOf;
  final Widget Function(T item) itemBuilder;
  final String hint;

  /// For the no-match message, e.g. "expense invoices".
  final String noun;

  @override
  State<_SearchablePagedList<T>> createState() => _SearchablePagedListState<T>();
}

class _SearchablePagedListState<T> extends State<_SearchablePagedList<T>> {
  final _controller = TextEditingController();
  String _query = '';

  /// Kept here so the size survives a no-match search (which removes the
  /// pager); null until changed, i.e. the pager's default.
  int? _pageSize;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalizeSearch(_query);
    final exact = widget.exactSearchFieldsOf;
    final shown = widget.items
        .where((item) => _matchesSearch(query, widget.searchFieldsOf(item), exactFields: exact == null ? const [] : exact(item)))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FinanceSearchField(
          keyPrefix: widget.keyPrefix,
          controller: _controller,
          hint: widget.hint,
          onChanged: (v) => setState(() => _query = v),
        ),
        if (shown.isEmpty)
          _FinanceSearchEmpty(keyPrefix: widget.keyPrefix, noun: widget.noun, query: _query)
        else
          _PagedList<T>(
            keyPrefix: widget.keyPrefix,
            items: shown,
            idOf: widget.idOf,
            itemBuilder: widget.itemBuilder,
            resetToken: query,
            initialPageSize: _pageSize,
            onPageSizeChanged: (size) => _pageSize = size,
          ),
      ],
    );
  }
}

/// UI-only pagination for an already-filtered, already-ordered list (used
/// by the Expenses, Salary and Ledger tabs; same controls and behaviour as the
/// Income tab's): 10/25/50 per page, Previous/Next, "Showing x–y of n" and
/// "Page p of q". Only the current page's items are built. Returns to the
/// first page when the list's ids change, or when a page size leaves the
/// current page out of range. The caller shows its own empty state, so
/// [items] is never empty here; totals stay with the caller.
class _PagedList<T> extends StatefulWidget {
  const _PagedList({
    required this.keyPrefix,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    this.resetToken,
    this.initialPageSize,
    this.onPageSizeChanged,
  });

  /// Prefix for the control keys, e.g. `expense-pagination`.
  final String keyPrefix;
  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(T item) itemBuilder;

  /// Optional: a change also returns to the first page (e.g. a filter
  /// change that happens to leave the same items).
  final Object? resetToken;

  /// Optional: lets a parent keep the chosen page size when this list is
  /// rebuilt from scratch (e.g. after a search matched nothing).
  final int? initialPageSize;
  final ValueChanged<int>? onPageSizeChanged;

  @override
  State<_PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<_PagedList<T>> {
  static const _pageSizes = [10, 25, 50];

  late int _pageSize = widget.initialPageSize ?? _pageSizes.first;
  int _page = 0;
  List<String> _lastIds = const [];
  late Object? _lastResetToken = widget.resetToken;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final ids = [for (final item in items) widget.idOf(item)];
    if (!listEquals(ids, _lastIds) || widget.resetToken != _lastResetToken) {
      _lastIds = ids;
      _lastResetToken = widget.resetToken;
      _page = 0;
    }
    final pageCount = items.isEmpty ? 1 : (items.length + _pageSize - 1) ~/ _pageSize;
    if (_page >= pageCount) _page = 0;
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, items.length);
    const label = TextStyle(fontSize: 13, color: AppColors.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items.sublist(start, end)) widget.itemBuilder(item),
        Wrap(
          key: Key('${widget.keyPrefix}-pagination'),
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Showing ${start + 1}–$end of ${items.length}', style: label),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Per page', style: label),
                DropdownButton<int>(
                  key: Key('${widget.keyPrefix}-page-size'),
                  value: _pageSize,
                  underline: const SizedBox.shrink(),
                  items: [for (final size in _pageSizes) DropdownMenuItem(value: size, child: Text('$size'))],
                  onChanged: (size) {
                    setState(() => _pageSize = size ?? _pageSize);
                    widget.onPageSizeChanged?.call(_pageSize);
                  },
                ),
                IconButton(
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                ),
                Text('Page ${_page + 1} of $pageCount', style: label),
                IconButton(
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _page < pageCount - 1 ? () => setState(() => _page++) : null,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// The Finance "Expenses" tab: vendor-invoice lifecycle at a glance
/// (raise -> unpaid/partial/paid -> pay). Built purely from the existing
/// `watchInvoicesByType('expense')` stream and the existing `payInvoice`
/// flow — no new business logic, no new Firestore queries.
class _ExpenseTab extends StatelessWidget {
  const _ExpenseTab({
    required this.service,
    required this.onPay,
    required this.onEdit,
    required this.onDelete,
    required this.onCancel,
    required this.onReversePayment,
    required this.onRaiseInvoice,
  });

  final FinanceService service;
  final Future<void> Function(FinanceInvoiceModel invoice) onPay;
  final Future<void> Function(FinanceInvoiceModel invoice) onEdit;
  final Future<void> Function(FinanceInvoiceModel invoice) onDelete;
  final Future<void> Function(FinanceInvoiceModel invoice) onCancel;
  final Future<void> Function(FinanceIncomeModel payment) onReversePayment;
  final VoidCallback onRaiseInvoice;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinanceInvoiceModel>>(
      stream: service.watchInvoicesByType('expense'),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data!;
        // Presentation-only aggregates over the invoice list — distinct from
        // FinanceService's ledger-based accounting totals. Raising an invoice
        // never affects the ledger/account balance; only paidAmount here
        // reflects money that has actually moved.
        // A cancelled invoice stays listed for audit but is no longer an
        // active expense, so it's excluded from these totals.
        final active = items.where((i) => i.status != 'cancelled');
        final outstanding = active.fold<double>(0, (total, i) => total + i.balanceAmount);
        final paid = active.fold<double>(0, (total, i) => total + i.paidAmount);
        final totalInvoiced = active.fold<double>(0, (total, i) => total + i.totalAmount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FinanceTabHeader(title: 'Expenses', subtitle: 'Manage vendor bills and expense payments'),
            const SizedBox(height: 16),
            _ResponsiveCardGrid(
              desktopColumns: 3,
              tabletColumns: 2,
              children: [
                FinanceSummaryCard(
                  label: 'Outstanding',
                  value: '₹${outstanding.toStringAsFixed(0)}',
                  icon: Icons.hourglass_bottom_outlined,
                  color: const Color(0xFFB26A00),
                ),
                FinanceSummaryCard(
                  label: 'Paid',
                  value: '₹${paid.toStringAsFixed(0)}',
                  icon: Icons.check_circle_outline,
                  color: AppColors.secondary,
                ),
                FinanceSummaryCard(
                  label: 'Total Expenses',
                  value: '₹${totalInvoiced.toStringAsFixed(0)}',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (items.isEmpty)
              _FinanceEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No expense invoices',
                subtitle: 'Raise an expense invoice to start tracking vendor payments.',
                ctaLabel: 'Raise Expense Invoice',
                onCta: onRaiseInvoice,
              )
            else
              // Search and paging filter the rows only; the cards above
              // use the complete list.
              _SearchablePagedList<FinanceInvoiceModel>(
                keyPrefix: 'expense',
                items: items,
                idOf: (invoice) => invoice.id,
                hint: 'Search vendor, invoice no., category, description or status',
                noun: 'expense invoices',
                searchFieldsOf: (i) => [i.partyName, i.invoiceNo, i.categoryName, i.description, i.status, _invoiceStatusPresentation(i.status).label],
                itemBuilder: (invoice) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InvoiceCard(
                    invoice: invoice,
                    onPay: () => onPay(invoice),
                    onEdit: () => onEdit(invoice),
                    onDelete: () => onDelete(invoice),
                    onCancel: () => onCancel(invoice),
                    service: service,
                    onReversePayment: onReversePayment,
                    showPaymentDates: true,
                    partyLabel: 'Vendor',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

({String label, Color color}) _invoiceStatusPresentation(String status) {
  switch (status) {
    case 'paid':
      return (label: 'PAID', color: AppColors.secondary);
    case 'partial':
      return (label: 'PARTIALLY PAID', color: const Color(0xFFB26A00));
    // Only expense invoices can be cancelled (FinanceService.cancelExpenseInvoice).
    case 'cancelled':
      return (label: 'CANCELLED', color: Colors.grey);
    default:
      return (label: 'UNPAID', color: const Color(0xFFD32F2F));
  }
}

/// Invoice card shared by the Expenses and Salary tabs — same lifecycle
/// (unpaid/partial/paid, Pay action), only the [partyLabel] differs
/// ("Vendor" vs "Staff").
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.onPay,
    required this.partyLabel,
    this.onEdit,
    this.onDelete,
    this.onCancel,
    this.service,
    this.onReversePayment,
    this.showPaymentDates = false,
  });

  final FinanceInvoiceModel invoice;
  final VoidCallback onPay;
  final String partyLabel;

  /// Expenses-only, like [onEdit]/[onDelete]: cancel the invoice, and (via
  /// [service] + [onReversePayment]) show its payment history with a
  /// Reverse action in the details dialog. Salary passes none of these.
  final VoidCallback? onCancel;
  final FinanceService? service;
  final Future<void> Function(FinanceIncomeModel payment)? onReversePayment;

  /// Salary and Expenses: show the actual date(s) of recorded payments on
  /// the card (read from the payment records, never from the invoice's own
  /// dates).
  final bool showPaymentDates;

  /// Edit/Delete actions — passed only by the Expenses tab; the Salary tab
  /// omits them, so its cards render exactly as before.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final status = _invoiceStatusPresentation(invoice.status);
    final isPaid = invoice.status == 'paid';
    final isCancelled = invoice.status == 'cancelled';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showDialog(
        context: context,
        builder: (_) => _InvoiceDetailsDialog(
          invoice: invoice,
          partyLabel: partyLabel,
          service: service,
          onReversePayment: onReversePayment,
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.invoiceNo.isEmpty ? 'Invoice' : invoice.invoiceNo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        invoice.partyName.isEmpty ? partyLabel : invoice.partyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FinanceStatusChip(label: status.label, color: status.color),
              ],
            ),
            if (invoice.categoryName.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(invoice.categoryName, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _AmountStat(label: 'Amount', value: invoice.totalAmount),
                _AmountStat(label: 'Paid', value: invoice.paidAmount),
                _AmountStat(label: 'Balance', value: invoice.balanceAmount),
              ],
            ),
            if (showPaymentDates && service != null && invoice.paidAmount > 0) ...[
              const SizedBox(height: 10),
              _InvoicePaymentDatesLine(invoice: invoice, service: service!),
            ],
            if (isCancelled && invoice.cancellationReason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Cancelled: ${invoice.cancellationReason}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (onEdit != null && !isCancelled)
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEdit,
                  ),
                if (onDelete != null && !isCancelled)
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    onPressed: onDelete,
                  ),
                if (onCancel != null && !isCancelled)
                  IconButton(
                    tooltip: 'Cancel Invoice',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.block, size: 20, color: Colors.red),
                    onPressed: onCancel,
                  ),
                const Spacer(),
                isCancelled
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.block, size: 16, color: Colors.grey),
                        SizedBox(width: 6),
                        Text('Cancelled', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                      ],
                    )
                  : isPaid
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 16, color: AppColors.secondary),
                        SizedBox(width: 6),
                        Text('Paid', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.secondary)),
                      ],
                    )
                  : FilledButton(
                      onPressed: onPay,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: const Text('Pay'),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A payment's recorded date, or "Not recorded" for older/malformed
/// records — never a substitute such as the invoice or creation date.
String _formatPaymentDate(DateTime? date) =>
    date == null ? 'Not recorded' : DateFormat('dd MMM yyyy').format(date);

/// Salary/Expenses card line listing the date of each active (non-reversed) payment
/// recorded against [invoice], oldest first. Loads once per invoice and
/// paid amount, so it refreshes after a new payment without re-querying on
/// every rebuild. Its states are distinct: loading shows "Loading payment
/// date…"; a failed lookup says so and offers Retry (read-only, never a
/// substitute date); a successful lookup with no active payment shows
/// nothing, as before; otherwise the date(s) are listed.
class _InvoicePaymentDatesLine extends StatefulWidget {
  const _InvoicePaymentDatesLine({required this.invoice, required this.service});

  final FinanceInvoiceModel invoice;
  final FinanceService service;

  @override
  State<_InvoicePaymentDatesLine> createState() => _InvoicePaymentDatesLineState();
}

class _InvoicePaymentDatesLineState extends State<_InvoicePaymentDatesLine> {
  late Future<List<FinanceIncomeModel>> _payments;

  @override
  void initState() {
    super.initState();
    _payments = widget.service.getInvoicePayments(widget.invoice.id);
  }

  @override
  void didUpdateWidget(covariant _InvoicePaymentDatesLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invoice.id != widget.invoice.id || oldWidget.invoice.paidAmount != widget.invoice.paidAmount) {
      _payments = widget.service.getInvoicePayments(widget.invoice.id);
    }
  }

  void _retry() {
    setState(() {
      _payments = widget.service.getInvoicePayments(widget.invoice.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    return FutureBuilder<List<FinanceIncomeModel>>(
      future: _payments,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Text('Loading payment date…', style: style);
        }
        if (snap.hasError || !snap.hasData) {
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              const Text("Payment date couldn't be loaded.", style: TextStyle(fontSize: 13, color: _warningColor)),
              TextButton(
                onPressed: _retry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
            ],
          );
        }
        final active = snap.data!.where((p) => !p.isDeleted).toList()
          ..sort((a, b) {
            final aDate = a.incomeDate;
            final bDate = b.incomeDate;
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return aDate.compareTo(bDate);
          });
        if (active.isEmpty) return const SizedBox.shrink();
        final text = active.length == 1
            ? 'Payment Date: ${_formatPaymentDate(active.single.incomeDate)}'
            : 'Payment Dates: ${active.map((p) => '₹${p.amount.toStringAsFixed(0)} on ${_formatPaymentDate(p.incomeDate)}').join(', ')}';
        return Text(text, style: style);
      },
    );
  }
}

class _AmountStat extends StatelessWidget {
  const _AmountStat({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            '₹${value.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
          ),
        ],
      );
}

class _InvoiceDetailsDialog extends StatelessWidget {
  const _InvoiceDetailsDialog({
    required this.invoice,
    required this.partyLabel,
    this.service,
    this.onReversePayment,
  });

  final FinanceInvoiceModel invoice;
  final String partyLabel;

  /// When set (Expenses only), the dialog lists this invoice's payment
  /// history, with a Reverse action on each active payment.
  final FinanceService? service;
  final Future<void> Function(FinanceIncomeModel payment)? onReversePayment;

  @override
  Widget build(BuildContext context) {
    final status = _invoiceStatusPresentation(invoice.status);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        );

    return ResponsiveDialogShell.form(
      desktopWidth: 480,
      desktopHeight: 560,
      title: invoice.invoiceNo.isEmpty ? 'Invoice' : invoice.invoiceNo,
      content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FinanceStatusChip(label: status.label, color: status.color),
              const Divider(height: 24),
              row(partyLabel, invoice.partyName.isEmpty ? '—' : invoice.partyName),
              row('Category', invoice.categoryName.isEmpty ? '—' : invoice.categoryName),
              row('Amount', '₹${invoice.amount.toStringAsFixed(0)}'),
              if (invoice.taxAmount > 0) row('Tax', '₹${invoice.taxAmount.toStringAsFixed(0)}'),
              row('Total Amount', '₹${invoice.totalAmount.toStringAsFixed(0)}'),
              row('Paid Amount', '₹${invoice.paidAmount.toStringAsFixed(0)}'),
              row('Balance', '₹${invoice.balanceAmount.toStringAsFixed(0)}'),
              if (invoice.description.isNotEmpty) row('Description', invoice.description),
              if (invoice.invoiceDate != null) row('Invoice Date', DateFormat('dd MMM yyyy').format(invoice.invoiceDate!)),
              if (invoice.createdAt != null) row('Created', DateFormat('dd MMM yyyy').format(invoice.createdAt!)),
              if (invoice.status == 'cancelled') ...[
                if (invoice.cancellationReason.isNotEmpty) row('Cancel Reason', invoice.cancellationReason),
                if (invoice.cancelledAt != null) row('Cancelled On', DateFormat('dd MMM yyyy').format(invoice.cancelledAt!)),
                if (invoice.cancelledBy.isNotEmpty) row('Cancelled By', invoice.cancelledBy),
              ],
              if (service != null) ...[
                const Divider(height: 24),
                const Text('Payments', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                FutureBuilder<List<FinanceIncomeModel>>(
                  future: service!.getInvoicePayments(invoice.id),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          "Couldn't load payments, so the payment date can't be shown. Close and reopen this invoice to try again.",
                          style: TextStyle(fontSize: 13, color: _warningColor),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      );
                    }
                    final payments = snap.data!;
                    final active = payments.where((p) => !p.isDeleted).toList();
                    // Salary/Expenses: a separate Payment Date row only when
                    // there is exactly one active payment; with several, each
                    // payment's own date is listed below instead of implying
                    // one shared date.
                    final paymentDateRow = (invoice.type == 'salary' || invoice.type == 'expense') && active.length == 1
                        ? row('Payment Date', _formatPaymentDate(active.single.incomeDate))
                        : null;
                    if (payments.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No payments recorded.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ?paymentDateRow,
                        ...payments.map((p) {
                        final details = [
                          if (p.incomeDate != null) DateFormat('dd MMM yyyy').format(p.incomeDate!),
                          p.paymentMode,
                          if (p.referenceNo.isNotEmpty) 'Ref ${p.referenceNo}',
                        ].join(' • ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('₹${p.amount.toStringAsFixed(0)}'),
                          subtitle: Text(details),
                          trailing: p.isDeleted
                              ? const FinanceStatusChip(label: 'REVERSED', color: Colors.grey)
                              : onReversePayment == null
                                  ? null
                                  : TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        onReversePayment!(p);
                                      },
                                      child: const Text('Reverse', style: TextStyle(color: Colors.red)),
                                    ),
                        );
                      }),
                      ],
                    );
                  },
                ),
              ],
              if (invoice.attachmentUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextButton.icon(
                    onPressed: () => launchUrl(Uri.parse(invoice.attachmentUrl), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: const Text('View Attachment'),
                  ),
                ),
            ],
          ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

/// The Finance "Salary" tab: mirrors the Expenses tab's invoice lifecycle
/// (raise -> unpaid/partial/paid -> pay) via the shared [_InvoiceCard], with
/// the existing `watchInvoicesByType('salary')` stream and `payInvoice`
/// flow — no new business logic, no new Firestore queries.
class _SalaryTab extends StatelessWidget {
  const _SalaryTab({required this.service, required this.onPay, required this.onRaiseInvoice});

  final FinanceService service;
  final Future<void> Function(FinanceInvoiceModel invoice) onPay;
  final VoidCallback onRaiseInvoice;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinanceInvoiceModel>>(
      stream: service.watchInvoicesByType('salary'),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data!;
        final outstanding = items.fold<double>(0, (total, i) => total + i.balanceAmount);
        final paid = items.fold<double>(0, (total, i) => total + i.paidAmount);
        final totalInvoiced = items.fold<double>(0, (total, i) => total + i.totalAmount);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FinanceTabHeader(title: 'Salary', subtitle: 'Manage staff salary invoices and payments'),
            const SizedBox(height: 16),
            _ResponsiveCardGrid(
              desktopColumns: 3,
              tabletColumns: 2,
              children: [
                FinanceSummaryCard(
                  label: 'Outstanding',
                  value: '₹${outstanding.toStringAsFixed(0)}',
                  icon: Icons.hourglass_bottom_outlined,
                  color: const Color(0xFFB26A00),
                ),
                FinanceSummaryCard(
                  label: 'Paid',
                  value: '₹${paid.toStringAsFixed(0)}',
                  icon: Icons.check_circle_outline,
                  color: AppColors.secondary,
                ),
                FinanceSummaryCard(
                  label: 'Total Salary',
                  value: '₹${totalInvoiced.toStringAsFixed(0)}',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (items.isEmpty)
              _FinanceEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No salary invoices',
                subtitle: 'Raise a salary invoice to start tracking staff payments.',
                ctaLabel: 'Raise Salary Invoice',
                onCta: onRaiseInvoice,
              )
            else
              _SearchablePagedList<FinanceInvoiceModel>(
                keyPrefix: 'salary',
                items: items,
                idOf: (invoice) => invoice.id,
                hint: 'Search staff, invoice no., description or status',
                noun: 'salary invoices',
                searchFieldsOf: (i) => [i.partyName, i.invoiceNo, i.description, i.status, _invoiceStatusPresentation(i.status).label],
                itemBuilder: (invoice) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InvoiceCard(
                    invoice: invoice,
                    onPay: () => onPay(invoice),
                    partyLabel: 'Staff',
                    service: service,
                    showPaymentDates: true,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VendorTab extends StatelessWidget {
  const _VendorTab({required this.service, required this.onAddVendor});
  final FinanceService service;
  final VoidCallback onAddVendor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VendorModel>>(
      stream: service.watchVendors(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FinanceTabHeader(title: 'Vendors', subtitle: 'Manage vendors and supplier information'),
            const SizedBox(height: 16),
            if (items.isEmpty)
              _FinanceEmptyState(
                icon: Icons.storefront_outlined,
                title: 'No vendors yet',
                subtitle: 'Add a vendor to start tracking their invoices and payments.',
                ctaLabel: 'Add Vendor',
                onCta: onAddVendor,
              )
            else
              // Search and paging filter the displayed cards only, in the
              // existing watchVendors() (name) order.
              _SearchablePagedList<VendorModel>(
                keyPrefix: 'vendor',
                items: items,
                idOf: (vendor) => vendor.id,
                hint: 'Search name, service type, phone, email or status',
                noun: 'vendors',
                searchFieldsOf: (v) => [v.name, v.serviceType, v.phone, v.email],
                exactSearchFieldsOf: (v) => [v.isActive ? 'active' : 'inactive'],
                itemBuilder: (vendor) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _VendorCard(vendor: vendor),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor});
  final VendorModel vendor;

  @override
  Widget build(BuildContext context) {
    final contactLine = [vendor.phone, vendor.email].where((v) => v.trim().isNotEmpty).join(' • ');
    return Container(
      width: double.infinity,
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
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.storefront_outlined, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vendor.name.trim().isEmpty ? 'Vendor' : vendor.name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                ),
                if (vendor.serviceType.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(vendor.serviceType.trim(), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
                if (contactLine.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    contactLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (!vendor.isActive) ...[
            const SizedBox(width: 12),
            const FinanceStatusChip(label: 'INACTIVE', color: Colors.grey),
          ],
        ],
      ),
    );
  }
}

/// The Finance "Ledger" tab: the same [LedgerEntryCard] and `watchLedger()`
/// stream the Dashboard's "Recent Transactions -> View all" link leads to —
/// just the full, unfiltered list instead of the latest 5.
class _LedgerTab extends StatelessWidget {
  const _LedgerTab({required this.service});
  final FinanceService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinanceLedgerEntryModel>>(
      stream: service.watchLedger(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snap.data!;
        // Only confirmed ledger entries represent actual money movement —
        // unpaid/partial invoice balances never reach the ledger in the
        // first place (invoices only post here once paid), so no separate
        // "exclude outstanding" filter is needed beyond skipping cancelled
        // entries, the same rule FinanceService's own summary uses.
        final confirmed = items.where((e) => e.status != 'cancelled');
        final inflow = confirmed.where((e) => e.entryType == 'income').fold<double>(0, (total, e) => total + e.amount);
        final outflow = confirmed.where((e) => e.entryType == 'expense').fold<double>(0, (total, e) => total + e.amount);
        final netMovement = inflow - outflow;

        return StreamBuilder<FinanceDashboardSummaryModel>(
          stream: service.watchDashboardSummary(),
          builder: (context, summarySnap) {
            final summary = summarySnap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FinanceTabHeader(
                  title: 'Ledger',
                  subtitle: 'A complete record of every income and expense transaction',
                ),
                const SizedBox(height: 20),
                const _DashboardSectionHeader(title: 'Ledger Summary'),
                const SizedBox(height: 12),
                _ResponsiveCardGrid(
                  desktopColumns: 4,
                  tabletColumns: 2,
                  children: [
                    FinanceSummaryCard(
                      label: 'Total Inflow',
                      value: '₹${inflow.toStringAsFixed(0)}',
                      icon: Icons.trending_up,
                      color: AppColors.primary,
                    ),
                    FinanceSummaryCard(
                      label: 'Total Outflow',
                      value: '₹${outflow.toStringAsFixed(0)}',
                      icon: Icons.trending_down,
                      color: const Color(0xFFD32F2F),
                    ),
                    FinanceSummaryCard(
                      label: 'Net Movement',
                      value: '₹${netMovement.toStringAsFixed(0)}',
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppColors.secondary,
                    ),
                    FinanceSummaryCard(
                      // Opening balances + Net Movement, computed once in
                      // FinanceService.watchDashboardSummary (not here).
                      label: 'Closing Balance',
                      value: '₹${(summary?.closingBalance ?? 0).toStringAsFixed(0)}',
                      icon: Icons.savings_outlined,
                      color: const Color(0xFF5E35B1),
                    ),
                  ],
                ),
                if ((summary?.openingBalance ?? 0) != 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Closing Balance includes ₹${summary!.openingBalance.toStringAsFixed(0)} in account opening balances.',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 28),
                const _DashboardSectionHeader(title: 'Account Balances'),
                const SizedBox(height: 12),
                _ResponsiveCardGrid(
                  desktopColumns: 3,
                  tabletColumns: 2,
                  children: [
                    FinanceSummaryCard(
                      label: 'Cash',
                      value: '₹${(summary?.cashBalance ?? 0).toStringAsFixed(0)}',
                      icon: Icons.payments_outlined,
                      color: AppColors.primary,
                    ),
                    FinanceSummaryCard(
                      label: 'Bank',
                      value: '₹${(summary?.bankBalance ?? 0).toStringAsFixed(0)}',
                      icon: Icons.account_balance_outlined,
                      color: AppColors.secondary,
                    ),
                    FinanceSummaryCard(
                      label: 'UPI',
                      value: '₹${(summary?.upiBalance ?? 0).toStringAsFixed(0)}',
                      icon: Icons.qr_code_rounded,
                      color: const Color(0xFF5E35B1),
                    ),
                  ],
                ),
                if (summary != null) _AccountBalancesReconciliation(summary: summary),
                const SizedBox(height: 28),
                const _DashboardSectionHeader(title: 'Transactions'),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const _EmptyTransactions()
                else
                  // Searched and paged in the UI only; the inflow/outflow/net
                  // movement and balance figures above use the complete list.
                  _SearchablePagedList<FinanceLedgerEntryModel>(
                    keyPrefix: 'ledger',
                    items: items,
                    idOf: (e) => e.id,
                    hint: 'Search description, category, reference, account or vendor',
                    noun: 'transactions',
                    // subCategoryName holds the vendor name on direct expenses.
                    searchFieldsOf: (e) => [e.title, e.description, e.categoryName, e.subCategoryName, e.referenceNo, e.accountName],
                    itemBuilder: (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: LedgerEntryCard(entry: e),
                    ),
                  ),
                // Reserves clearance so the last transaction can scroll
                // fully clear of the floating "Add" FAB.
                const SizedBox(height: AppSizes.fabScrollClearance),
              ],
            );
          },
        );
      },
    );
  }
}

/// The Finance "Settings" tab: lists the actual categories and accounts
/// (not just counts). Categories can be edited and deleted through
/// FinanceService.updateCategory/deleteCategory (default categories are
/// locked; a category in use can't be renamed, retyped or deleted, only
/// deactivated). Accounts can be edited and deleted through
/// FinanceService.updateAccount/deleteAccount (an account in use keeps its
/// type and opening balance and can't be deleted, only deactivated; one that
/// new payments depend on stays active). Adding either is handled by the
/// Settings FAB's Add Category / Add Account choice sheet.
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.service});
  final FinanceService service;

  static void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _editCategory(BuildContext context, FinanceCategoryModel category) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddCategoryDialog(category: category, service: service),
    );
    if (saved == true && context.mounted) _message(context, 'Category updated');
  }

  Future<void> _deleteCategory(BuildContext context, FinanceCategoryModel category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Delete "${category.name}"? This is only allowed when no income, expense, invoice or ledger '
          'record uses it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final List<String> refs;
    try {
      refs = await service.categoryReferences(category);
    } catch (e) {
      if (context.mounted) _message(context, "Couldn't check where this category is used, so it wasn't deleted: $e");
      return;
    }
    if (!context.mounted) return;
    if (refs.isNotEmpty) {
      final deactivate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Category In Use'),
          content: Text(
            '"${category.name}" is used by ${refs.join(', ')}, so it can\'t be deleted without leaving those '
            'records pointing at a missing category. '
            '${category.isActive ? 'Deactivate it instead to hide it from new entries; existing records keep it.' : 'It is already inactive.'}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Close')),
            if (category.isActive)
              FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Deactivate')),
          ],
        ),
      );
      if (deactivate != true || !context.mounted) return;
      try {
        await service.updateCategory(id: category.id, name: category.name, type: category.type, isActive: false);
        if (context.mounted) _message(context, 'Category deactivated');
      } catch (e) {
        if (context.mounted) _message(context, 'Failed to deactivate category: ${e is StateError ? e.message : e}');
      }
      return;
    }
    try {
      await service.deleteCategory(category.id);
      if (context.mounted) _message(context, 'Category deleted');
    } catch (e) {
      if (context.mounted) _message(context, 'Failed to delete category: ${e is StateError ? e.message : e}');
    }
  }

  Future<void> _editAccount(BuildContext context, FinanceAccountModel account) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddAccountDialog(account: account, service: service),
    );
    if (saved == true && context.mounted) _message(context, 'Account updated');
  }

  /// Confirms, then checks usage: an account that records point at, that
  /// holds a balance, or that new payments depend on is never deleted —
  /// the user gets the reason and, where allowed, a Deactivate option.
  Future<void> _deleteAccount(BuildContext context, FinanceAccountModel account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Account'),
        content: Text(
          'Delete "${account.name}"? This is only allowed when no Finance record uses it, its balances are zero '
          'and new payments don\'t depend on it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final FinanceAccountUsage usage;
    try {
      usage = await service.accountUsage(account);
    } catch (e) {
      if (context.mounted) _message(context, "Couldn't check how this account is used, so it wasn't deleted: $e");
      return;
    }
    if (!context.mounted) return;
    final blocked = usage.deleteBlockedReason(account.name);
    if (blocked != null) {
      final canDeactivate = account.isActive && usage.deactivateBlockedReason(account.name) == null;
      final deactivate = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(usage.isRequired ? 'Account Required' : 'Account In Use'),
          content: Text(
            '$blocked '
            '${canDeactivate ? 'Deactivate it instead: it receives no new payments, and its history and balances stay as they are.' : account.isActive ? '' : 'It is already inactive.'}'
                .trim(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Close')),
            if (canDeactivate) FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Deactivate')),
          ],
        ),
      );
      if (deactivate != true || !context.mounted) return;
      try {
        await service.updateAccount(
          id: account.id,
          name: account.name,
          type: account.type,
          openingBalance: account.openingBalance,
          isActive: false,
        );
        if (context.mounted) _message(context, 'Account deactivated');
      } catch (e) {
        if (context.mounted) _message(context, 'Failed to deactivate account: ${e is StateError ? e.message : e}');
      }
      return;
    }
    try {
      await service.deleteAccount(account.id);
      if (context.mounted) _message(context, 'Account deleted');
    } catch (e) {
      if (context.mounted) _message(context, 'Failed to delete account: ${e is StateError ? e.message : e}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FinanceTabHeader(
          title: 'Finance Settings',
          subtitle: 'Manage finance categories, accounts, and opening balances.',
        ),
        const SizedBox(height: 24),
        const Text(
          'Category Settings',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<FinanceCategoryModel>>(
          stream: service.watchCategories(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "Couldn't load categories. Reopen Settings to try again.",
                  style: TextStyle(fontSize: 13, color: _warningColor),
                ),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return const _FinanceEmptyState(
                icon: Icons.sell_outlined,
                title: 'No categories yet',
                subtitle: 'Categories you add will appear here.',
              );
            }
            return Column(
              children: items
                  .map((category) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CategoryRow(
                          category: category,
                          onEdit: () => _editCategory(context, category),
                          onDelete: () => _deleteCategory(context, category),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 28),
        const Text(
          'Account Settings',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<FinanceAccountModel>>(
          stream: service.watchAccounts(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  "Couldn't load accounts. Reopen Settings to try again.",
                  style: TextStyle(fontSize: 13, color: _warningColor),
                ),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return const _FinanceEmptyState(
                icon: Icons.account_balance_outlined,
                title: 'No accounts yet',
                subtitle: 'Accounts you add will appear here.',
              );
            }
            return _ResponsiveCardGrid(
              desktopColumns: 3,
              tabletColumns: 2,
              children: items
                  .map((account) => _AccountRow(
                        account: account,
                        onEdit: () => _editAccount(context, account),
                        onDelete: () => _deleteAccount(context, account),
                      ))
                  .toList(),
            );
          },
        ),
        // Reserves clearance so the last account can scroll fully clear
        // of the floating "Add" FAB.
        const SizedBox(height: AppSizes.fabScrollClearance),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, this.onEdit, this.onDelete});
  final FinanceCategoryModel category;

  /// Not offered for default (isSystem) categories.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncome = category.type == 'income';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              category.name.trim().isEmpty ? 'Category' : category.name.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          FinanceStatusChip(
            label: category.type.toUpperCase(),
            color: isIncome ? AppColors.secondary : const Color(0xFFD32F2F),
          ),
          if (!category.isActive) ...[
            const SizedBox(width: 8),
            const FinanceStatusChip(label: 'INACTIVE', color: Colors.grey),
          ],
          if (category.isSystem)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'Default category',
                child: Icon(Icons.lock_outline, size: 18, color: AppColors.textSecondary),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: onEdit,
            ),
            IconButton(
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
              onPressed: onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, this.onEdit, this.onDelete});
  final FinanceAccountModel account;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  static IconData _iconFor(String type) {
    final t = type.toLowerCase();
    if (t.contains('cash')) return Icons.payments_outlined;
    if (t.contains('upi')) return Icons.qr_code_rounded;
    return Icons.account_balance_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_iconFor(account.type), color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name.trim().isEmpty ? 'Account' : account.name.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                    ),
                    Text(
                      account.type.isEmpty ? 'NO TYPE · UNCLASSIFIED' : account.type.toUpperCase(),
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!account.isActive) const FinanceStatusChip(label: 'INACTIVE', color: Colors.grey),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _AmountStat(label: 'Opening Balance', value: account.openingBalance),
              _AmountStat(label: 'Current Balance', value: account.currentBalance),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportsTab extends StatelessWidget {
  // Report generation isn't implemented yet — these are placeholders that
  // visually belong to the app, not invented functionality.
  static const _reports = [
    (title: 'Daily Cash Book', description: 'Day-wise cash, bank and UPI movement.', icon: Icons.menu_book_outlined),
    (title: 'Monthly Income & Expense', description: 'Month-wise income vs. expense summary.', icon: Icons.bar_chart_outlined),
    (title: 'Category Expense Report', description: 'Spending broken down by category.', icon: Icons.pie_chart_outline),
    (title: 'Staff Salary Report', description: 'Salary invoices and payments by staff member.', icon: Icons.groups_outlined),
    (title: 'Vendor Payment Report', description: 'Payments made to each vendor.', icon: Icons.storefront_outlined),
    (title: 'Profit / Loss Summary', description: 'Overall income minus expenses.', icon: Icons.trending_up),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FinanceTabHeader(title: 'Reports', subtitle: 'View and generate financial reports'),
        const SizedBox(height: 16),
        ..._reports.map(
          (report) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ReportCard(title: report.title, description: report.description, icon: report.icon),
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.description, required this.icon});

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const FinanceStatusChip(label: 'COMING SOON', color: Colors.grey),
        ],
      ),
    );
  }
}

/// Confirmation dialog with a required reason (Expenses cancel/reverse).
/// Owns its controller so it is disposed only after the dialog is gone.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.message, required this.confirmLabel});

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: InputDecoration(labelText: 'Reason *', errorText: _error),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () {
            final reason = _controller.text.trim();
            if (reason.isEmpty) {
              setState(() => _error = 'Reason is required');
              return;
            }
            Navigator.of(context).pop(reason);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _PayInvoiceDialog extends StatefulWidget {
  const _PayInvoiceDialog({
    required this.invoice,
    required this.service,
  });

  final FinanceInvoiceModel invoice;
  final FinanceService service;

  @override
  State<_PayInvoiceDialog> createState() => _PayInvoiceDialogState();
}

class _PayInvoiceDialogState extends State<_PayInvoiceDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _remarks = TextEditingController();
  String _paymentMode = 'cash';
  bool _saving = false;

  /// The date the payment was actually made. Offered for expense and salary
  /// invoices; any other type keeps the existing "today" behaviour. Starts
  /// at now — exactly the value previously saved — and a picked date
  /// replaces it.
  DateTime _paidDate = DateTime.now();
  String? _paidDateError;

  bool get _showsPaymentDate => widget.invoice.type == 'expense' || widget.invoice.type == 'salary';

  @override
  void initState() {
    super.initState();
    _amount.text = widget.invoice.balanceAmount.toStringAsFixed(0);
  }

  Future<void> _pickPaidDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDate: _paidDate,
    );
    if (picked != null) {
      setState(() {
        _paidDate = picked;
        _paidDateError = null;
      });
    }
  }

  /// A payment date cannot be in the future (a payment can only be
  /// recorded once it has been made).
  String? _validatePaidDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(_paidDate.year, _paidDate.month, _paidDate.day);
    if (day.isAfter(today)) return 'Payment date cannot be in the future';
    return null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0 || amount > widget.invoice.balanceAmount) return;
    if (_showsPaymentDate) {
      final dateError = _validatePaidDate();
      if (dateError != null) {
        setState(() => _paidDateError = dateError);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.service.payInvoice(
        invoiceId: widget.invoice.id,
        invoiceType: widget.invoice.type,
        amount: amount,
        paidDate: _showsPaymentDate ? _paidDate : DateTime.now(),
        paymentMode: _paymentMode,
        referenceNo: _reference.text.trim(),
        remarks: _remarks.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pay invoice: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogShell.form(
      desktopWidth: 520,
      desktopHeight: 460,
      title: 'Pay Invoice - ${widget.invoice.partyName}',
      content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _amount, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number),
            if (_showsPaymentDate)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Payment Date *'),
                subtitle: Text(
                  _paidDateError ?? DateFormat('dd MMM yyyy').format(_paidDate),
                  style: _paidDateError == null ? null : const TextStyle(color: Colors.red),
                ),
                trailing: TextButton(
                  onPressed: _saving ? null : _pickPaidDate,
                  child: const Text('Change'),
                ),
              ),
            DropdownButtonFormField<String>(
              initialValue: _paymentMode,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: const ['cash', 'bank', 'upi'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setState(() => _paymentMode = v ?? _paymentMode),
            ),
            TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Reference No')),
            TextField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks')),
          ],
        ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
