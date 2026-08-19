import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
        backgroundColor: const Color(0xFF2E7D32),
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
        child: StreamBuilder<FinanceDashboardSummaryModel>(
          stream: _service.watchDashboardSummary(),
          builder: (context, summarySnap) {
            final summary = summarySnap.data;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finance', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      FinanceSummaryCard(label: 'Total Income', value: '₹${summary?.totalIncome.toStringAsFixed(0) ?? '0'}', icon: Icons.trending_up),
                      FinanceSummaryCard(label: 'Total Expenses', value: '₹${summary?.totalExpenses.toStringAsFixed(0) ?? '0'}', icon: Icons.trending_down, color: Colors.redAccent),
                      FinanceSummaryCard(label: 'Net Balance', value: '₹${summary?.netBalance.toStringAsFixed(0) ?? '0'}', icon: Icons.account_balance_wallet),
                      FinanceSummaryCard(label: 'Cash', value: '₹${summary?.cashBalance.toStringAsFixed(0) ?? '0'}', icon: Icons.payments),
                      FinanceSummaryCard(label: 'Bank', value: '₹${summary?.bankBalance.toStringAsFixed(0) ?? '0'}', icon: Icons.account_balance),
                      FinanceSummaryCard(label: 'UPI', value: '₹${summary?.upiBalance.toStringAsFixed(0) ?? '0'}', icon: Icons.qr_code),
                    ],
                  ),
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
                  const SizedBox(height: 16),
                  _buildBody(),
                ],
              ),
            );
          },
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
        return _DashboardTab(service: _service);
    }
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({required this.service});
  final FinanceService service;
  @override
  Widget build(BuildContext context) => StreamBuilder<List<FinanceLedgerEntryModel>>(
        stream: service.watchLedger(),
        builder: (context, snap) {
          final items = snap.data ?? [];
          if (items.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Text('No finance transactions yet.'));
          return Padding(
            padding: const EdgeInsets.only(bottom: 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent Transactions', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                ...items.take(5).map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LedgerEntryCard(entry: e),
                    )),
              ],
            ),
          );
        },
      );
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
