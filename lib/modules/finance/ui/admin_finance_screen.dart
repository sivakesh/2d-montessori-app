import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/widgets/responsive_dialog_shell.dart';
import '../../admin/ui/admin_fab.dart';
import '../../admin/ui/admin_layout.dart';
import '../models/finance_account_model.dart';
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
  const AdminFinanceScreen({super.key});

  @override
  State<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends State<AdminFinanceScreen> {
  final _service = FinanceService();
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
                    await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddExpenseDialog());
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
        );
      case 2:
        return _ExpenseTab(
          service: _service,
          onPay: _showPayInvoice,
          onRaiseInvoice: () => showDialog(context: context, barrierDismissible: false, builder: (_) => const AddExpenseDialog()),
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
                            label: 'Net Balance',
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
                        ],
                      ),
                      const SizedBox(height: 28),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _DashboardSectionHeader(title: 'Recent Transactions'),
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
class _IncomeTab extends StatelessWidget {
  const _IncomeTab({required this.service, required this.launchUrlFn, required this.onAddIncome});
  final FinanceService service;
  final Future<void> Function(String) launchUrlFn;
  final VoidCallback onAddIncome;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinanceIncomeModel>>(
      stream: service.watchIncome(),
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
            else
              Column(
                children: items
                    .map((i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _IncomeEntryCard(income: i),
                        ))
                    .toList(),
              ),
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
  const _IncomeEntryCard({required this.income});
  final FinanceIncomeModel income;

  @override
  Widget build(BuildContext context) {
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
                Text(
                  income.title.trim().isEmpty ? 'Income' : income.title.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary),
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
        ],
      ),
    );
  }
}

/// The Finance "Expenses" tab: vendor-invoice lifecycle at a glance
/// (raise -> unpaid/partial/paid -> pay). Built purely from the existing
/// `watchInvoicesByType('expense')` stream and the existing `payInvoice`
/// flow — no new business logic, no new Firestore queries.
class _ExpenseTab extends StatelessWidget {
  const _ExpenseTab({required this.service, required this.onPay, required this.onRaiseInvoice});

  final FinanceService service;
  final Future<void> Function(FinanceInvoiceModel invoice) onPay;
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
        final outstanding = items.fold<double>(0, (total, i) => total + i.balanceAmount);
        final paid = items.fold<double>(0, (total, i) => total + i.paidAmount);
        final totalInvoiced = items.fold<double>(0, (total, i) => total + i.totalAmount);

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
              Column(
                children: items
                    .map((invoice) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _InvoiceCard(invoice: invoice, onPay: () => onPay(invoice), partyLabel: 'Vendor'),
                        ))
                    .toList(),
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
    default:
      return (label: 'UNPAID', color: const Color(0xFFD32F2F));
  }
}

/// Invoice card shared by the Expenses and Salary tabs — same lifecycle
/// (unpaid/partial/paid, Pay action), only the [partyLabel] differs
/// ("Vendor" vs "Staff").
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, required this.onPay, required this.partyLabel});

  final FinanceInvoiceModel invoice;
  final VoidCallback onPay;
  final String partyLabel;

  @override
  Widget build(BuildContext context) {
    final status = _invoiceStatusPresentation(invoice.status);
    final isPaid = invoice.status == 'paid';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showDialog(context: context, builder: (_) => _InvoiceDetailsDialog(invoice: invoice, partyLabel: partyLabel)),
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
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: isPaid
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
            ),
          ],
        ),
      ),
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
  const _InvoiceDetailsDialog({required this.invoice, required this.partyLabel});

  final FinanceInvoiceModel invoice;
  final String partyLabel;

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
              Column(
                children: items
                    .map((invoice) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _InvoiceCard(invoice: invoice, onPay: () => onPay(invoice), partyLabel: 'Staff'),
                        ))
                    .toList(),
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
              Column(
                children: items
                    .map((vendor) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _VendorCard(vendor: vendor),
                        ))
                    .toList(),
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
                      // Reuses the Dashboard's own netBalance figure rather
                      // than recomputing a second "closing balance".
                      label: 'Closing Balance',
                      value: '₹${(summary?.netBalance ?? 0).toStringAsFixed(0)}',
                      icon: Icons.savings_outlined,
                      color: const Color(0xFF5E35B1),
                    ),
                  ],
                ),
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
                const SizedBox(height: 28),
                const _DashboardSectionHeader(title: 'Transactions'),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const _EmptyTransactions()
                else
                  Column(
                    children: items
                        .map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: LedgerEntryCard(entry: e),
                            ))
                        .toList(),
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
/// (not just counts), read-only — FinanceService has no update/delete for
/// either, so there is no existing CRUD to preserve beyond creation (already
/// handled by the Settings FAB's Add Category / Add Account choice sheet).
class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.service});
  final FinanceService service;

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
                        child: _CategoryRow(category: category),
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
              children: items.map((account) => _AccountRow(account: account)).toList(),
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
  const _CategoryRow({required this.category});
  final FinanceCategoryModel category;

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
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account});
  final FinanceAccountModel account;

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
                      account.type.toUpperCase(),
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (!account.isActive) const FinanceStatusChip(label: 'INACTIVE', color: Colors.grey),
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

  @override
  void initState() {
    super.initState();
    _amount.text = widget.invoice.balanceAmount.toStringAsFixed(0);
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
    setState(() => _saving = true);
    try {
      await widget.service.payInvoice(
        invoiceId: widget.invoice.id,
        invoiceType: widget.invoice.type,
        amount: amount,
        paidDate: DateTime.now(),
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
