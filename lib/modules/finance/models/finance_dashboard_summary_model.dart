class FinanceDashboardSummaryModel {
  FinanceDashboardSummaryModel({
    required this.totalIncome,
    required this.totalExpenses,
    required this.netBalance,
    required this.cashBalance,
    required this.bankBalance,
    required this.upiBalance,
    required this.thisMonthIncome,
    required this.thisMonthExpenses,
  });

  final double totalIncome;
  final double totalExpenses;
  final double netBalance;
  final double cashBalance;
  final double bankBalance;
  final double upiBalance;
  final double thisMonthIncome;
  final double thisMonthExpenses;
}

