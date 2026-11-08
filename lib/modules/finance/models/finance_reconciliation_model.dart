import 'package:flutter/foundation.dart';

/// One account checked by FinanceService.reconcileAccounts: the running
/// balance stored on it and the balance its ledger gives.
@immutable
class AccountReconciliation {
  const AccountReconciliation({
    required this.accountId,
    required this.name,
    required this.type,
    required this.isActive,
    required this.openingBalance,
    required this.storedBalance,
    required this.calculatedBalance,
    required this.entryCount,
    this.openingBalanceDate,
  });

  final String accountId;
  final String name;

  /// Stored type, lower case ('cash', 'bank', 'upi', 'wallet', 'other', or
  /// anything else an older record holds).
  final String type;
  final bool isActive;
  final double openingBalance;

  /// The day [openingBalance] applies from, if set. Informational: the
  /// stored and calculated balances are current, so they include the
  /// opening balance whatever its date.
  final DateTime? openingBalanceDate;

  /// A non-zero opening balance with no date.
  bool get hasUndatedOpeningBalance => (openingBalance * 100).round() != 0 && openingBalanceDate == null;

  /// `currentBalance` as stored on the account (changed by each transaction).
  final double storedBalance;

  /// Opening balance + its non-cancelled ledger entries (income in,
  /// anything else out): the figure Finance shows.
  final double calculatedBalance;

  /// Its non-cancelled ledger entries.
  final int entryCount;

  /// Stored minus calculated.
  double get difference => storedBalance - calculatedBalance;

  /// To the paisa.
  bool get matches => (difference * 100).round() == 0;
  bool get isNegative => (calculatedBalance * 100).round() < 0;

  /// Cash, Bank, UPI, or Other (how Finance groups its balances).
  String get group => switch (type) { 'cash' => 'Cash', 'bank' => 'Bank', 'upi' => 'UPI', _ => 'Other' };
}

/// A non-cancelled ledger entry whose account is missing: no account id,
/// or one that no longer exists. Its amount is in no account's balance.
@immutable
class LedgerAccountProblem {
  const LedgerAccountProblem({required this.entryId, required this.title, required this.entryType, required this.amount, required this.accountId, required this.accountName, this.transactionDate});

  final String entryId;
  final String title;
  final String entryType;
  final double amount;
  final String accountId;

  /// The account name saved on the entry.
  final String accountName;
  final DateTime? transactionDate;

  bool get hasNoAccount => accountId.trim().isEmpty;
}

/// The result of FinanceService.reconcileAccounts (read only: nothing is
/// corrected).
@immutable
class FinanceReconciliation {
  const FinanceReconciliation({required this.accounts, required this.problems});

  /// Every account, Cash, Bank, UPI, then Other, each by name.
  final List<AccountReconciliation> accounts;
  final List<LedgerAccountProblem> problems;

  List<AccountReconciliation> get mismatched => [for (final a in accounts) if (!a.matches) a];
  List<AccountReconciliation> get negative => [for (final a in accounts) if (a.isNegative) a];
  bool get allClear => mismatched.isEmpty && problems.isEmpty;
}
