import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../admin/ui/admin_layout.dart';
import '../models/finance_account_model.dart';
import '../models/finance_category_model.dart';
import '../models/finance_dashboard_summary_model.dart';
import '../models/finance_invoice_model.dart';
import '../models/finance_income_model.dart';
import '../models/finance_ledger_entry_model.dart';
import '../models/vendor_model.dart';
import '../services/finance_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 7,
      title: 'Finance',
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
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
            case 6:
              await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddCategoryDialog());
              break;
            case 7:
              await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddAccountDialog());
              break;
          }
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case 1:
        return _IncomeTab(service: _service, launchUrlFn: _launch);
      case 2:
        return _ExpenseTab(service: _service, onPay: _showPayInvoice);
      case 3:
        return _SalaryTab(service: _service, onPay: _showPayInvoice);
      case 4:
        return _VendorTab(service: _service);
      case 5:
        return _LedgerTab(service: _service);
      case 6:
        return _SettingsTab(service: _service);
      case 7:
        return _ReportsTab();
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
                  padding: const EdgeInsets.only(bottom: 96),
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

class _IncomeTab extends StatelessWidget {
  const _IncomeTab({required this.service, required this.launchUrlFn});
  final FinanceService service;
  final Future<void> Function(String) launchUrlFn;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<FinanceIncomeModel>>(
        stream: service.watchIncome(),
        builder: (context, snap) {
          final items = snap.data ?? [];
          return items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('No income records.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final i = items[index];
                    return Card(
                      child: ListTile(
                        title: Text(i.title),
                        subtitle: Text('${i.categoryName} • ₹${i.amount.toStringAsFixed(0)} • ${i.paymentMode}'),
                      ),
                    );
                  },
                );
        },
      );
}

class _ExpenseTab extends StatelessWidget {
  const _ExpenseTab({required this.service, required this.onPay});
  final FinanceService service;
  final Future<void> Function(FinanceInvoiceModel invoice) onPay;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<FinanceInvoiceModel>>(
        stream: service.watchInvoicesByType('expense'),
        builder: (context, snap) {
          final items = snap.data ?? [];
          return items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('No expense invoices.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final i = items[index];
                    return Card(
                      child: ListTile(
                        title: Text('${i.invoiceNo} • ${i.partyName}'),
                        subtitle: Text('${i.categoryName} • ₹${i.totalAmount.toStringAsFixed(0)}\nPaid: ₹${i.paidAmount.toStringAsFixed(0)} • Balance: ₹${i.balanceAmount.toStringAsFixed(0)}'),
                        trailing: i.balanceAmount > 0
                            ? TextButton(
                                onPressed: () => onPay(i),
                                child: const Text('Pay'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                );
        },
      );
}

class _SalaryTab extends StatelessWidget {
  const _SalaryTab({required this.service, required this.onPay});
  final FinanceService service;
  final Future<void> Function(FinanceInvoiceModel invoice) onPay;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<FinanceInvoiceModel>>(
        stream: service.watchInvoicesByType('salary'),
        builder: (context, snap) {
          final items = snap.data ?? [];
          return items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('No salary invoices.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final i = items[index];
                    return Card(
                      child: ListTile(
                        title: Text('${i.invoiceNo} • ${i.partyName}'),
                        subtitle: Text('${i.categoryName} • ₹${i.totalAmount.toStringAsFixed(0)}\nPaid: ₹${i.paidAmount.toStringAsFixed(0)} • Balance: ₹${i.balanceAmount.toStringAsFixed(0)}'),
                        trailing: i.balanceAmount > 0
                            ? TextButton(
                                onPressed: () => onPay(i),
                                child: const Text('Pay'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                );
        },
      );
}

class _VendorTab extends StatelessWidget {
  const _VendorTab({required this.service});
  final FinanceService service;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<VendorModel>>(
        stream: service.watchVendors(),
        builder: (context, snap) {
          final items = snap.data ?? [];
          return items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('No vendors.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final i = items[index];
                    return Card(child: ListTile(title: Text(i.name), subtitle: Text(i.serviceType)));
                  },
                );
        },
      );
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({required this.service});
  final FinanceService service;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<FinanceLedgerEntryModel>>(
        stream: service.watchLedger(),
        builder: (context, snap) {
          final items = snap.data ?? [];
          return items.isEmpty
              ? const Padding(padding: EdgeInsets.all(24), child: Text('No ledger entries.'))
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) => LedgerEntryCard(entry: items[index]),
                );
        },
      );
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.service});
  final FinanceService service;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Manage finance categories, accounts, and opening balances.'),
          const SizedBox(height: 16),
          StreamBuilder<List<FinanceCategoryModel>>(
            stream: service.watchCategories(),
            builder: (context, snap) => Text('Categories: ${snap.data?.length ?? 0}'),
          ),
          StreamBuilder<List<FinanceAccountModel>>(
            stream: service.watchAccounts(),
            builder: (context, snap) => Text('Accounts: ${snap.data?.length ?? 0}'),
          ),
        ],
      );
}

class _ReportsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reports placeholders'),
          SizedBox(height: 12),
          Text('Daily Cash Book'),
          Text('Monthly Income & Expense'),
          Text('Category Expense Report'),
          Text('Staff Salary Report'),
          Text('Vendor Payment Report'),
          Text('Profit / Loss Summary'),
        ],
      );
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
    return AlertDialog(
      title: Text('Pay Invoice - ${widget.invoice.partyName}'),
      content: SizedBox(
        width: 520,
        child: Column(
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
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const CircularProgressIndicator() : const Text('Save')),
      ],
    );
  }
}
