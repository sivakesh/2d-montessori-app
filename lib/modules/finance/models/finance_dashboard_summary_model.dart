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
    this.unclassifiedBalance = 0,
    this.openingBalance = 0,
    this.cashOpeningBalance = 0,
    this.bankOpeningBalance = 0,
    this.upiOpeningBalance = 0,
    this.unclassifiedOpeningBalance = 0,
    double? closingBalance,
    this.hasUnclassifiedActivity = false,
  }) : closingBalance = closingBalance ?? openingBalance + netBalance;

  final double totalIncome;
  final double totalExpenses;

  /// Net Movement: total income − total expenses for the period. Excludes
  /// opening balances.
  final double netBalance;

  /// Closing balances per account type: that type's opening balance plus
  /// its net movement.
  final double cashBalance;
  final double bankBalance;
  final double upiBalance;
  final double thisMonthIncome;
  final double thisMonthExpenses;

  /// Closing balance (opening balance plus net movement) of non-cancelled
  /// ledger entries whose account is missing or isn't a cash/bank/upi
  /// account, and of accounts of any other type, so it appears in none of
  /// the three balances above (see FinanceService.watchDashboardSummary).
  final double unclassifiedBalance;

  /// Opening balance for the period across all accounts, and its split by
  /// account type. Each is already included in the matching balance above.
  final double openingBalance;
  final double cashOpeningBalance;
  final double bankOpeningBalance;
  final double upiOpeningBalance;
  final double unclassifiedOpeningBalance;

  /// [openingBalance] + [netBalance]; equals cash + bank + upi +
  /// unclassified balances.
  final double closingBalance;

  /// True when any unclassified account has a non-zero opening balance or
  /// any non-cancelled, non-zero ledger entry counted in this summary is
  /// unclassified — even if those amounts net to zero, so
  /// [unclassifiedBalance] alone can't show it. An unclassified account
  /// with no balance and no activity doesn't set it.
  final bool hasUnclassifiedActivity;
}

