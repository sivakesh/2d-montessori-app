import 'package:flutter/material.dart';

import '../../admin/ui/admin_layout.dart';
import '../services/finance_service.dart';
import 'expense_efficiency_service.dart';
import 'expense_efficiency_tab.dart';

/// Finance → Reports → Expense Efficiency: hosts the existing
/// [ExpenseEfficiencyTab] (same widget, same service, same data) in the
/// Admin layout, opened from the Reports list with Navigator.push like the
/// app's other screens. Its back button, the system back and the browser
/// back pop this page, returning to Finance with Reports still selected.
///
/// Deliberately unnamed: the address isn't changed, so a page reload never
/// lands on a route the app doesn't define.
class ExpenseEfficiencyPage extends StatelessWidget {
  const ExpenseEfficiencyPage({super.key, required this.finance, required this.service, required this.clock});

  final FinanceService finance;
  final ExpenseEfficiencyService service;
  final DateTime Function() clock;

  static const title = 'Expense Efficiency';

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      selectedIndex: 7, // Finance
      title: title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              key: const Key('expense-efficiency-back'),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Finance Reports'),
            ),
            Text('Finance › Reports › Expense Efficiency', key: const Key('expense-efficiency-breadcrumb'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ExpenseEfficiencyTab(finance: finance, service: service, clock: clock),
          ],
        ),
      ),
    );
  }
}
