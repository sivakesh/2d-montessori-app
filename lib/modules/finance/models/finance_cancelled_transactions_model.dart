/// One cancelled/voided source transaction: a voided `finance_income`
/// record (manual income, fee collection income, or a reversed expense/
/// salary invoice payment), counted once whatever other records (its
/// ledger mirror, the Fees receipt) are also marked cancelled.
class FinanceCancelledTransaction {
  const FinanceCancelledTransaction({
    required this.id,
    required this.sourceLabel,
    required this.typeLabel,
    required this.title,
    required this.reference,
    required this.originalDate,
    required this.cancelledAt,
    required this.amount,
    required this.reason,
    required this.statusLabel,
    this.linkedDocumentLabel = '',
    this.linkedDocumentId = '',
    this.linkedDocumentNumber = '',
    this.linkedDocumentFound = false,
    this.linkedDocumentStatus = '',
    this.ledgerId = '',
    this.ledgerStatus = '',
    this.reviewNote = '',
  });

  /// The finance_income document id (shown as "Record ID").
  final String id;

  /// Where the transaction originated: "Fees", "Finance → Income",
  /// "Finance → Expenses" or "Finance → Salary".
  final String sourceLabel;
  final String typeLabel;
  final String title;

  /// The payment reference typed in when it was recorded (`referenceNo`);
  /// '' when none was recorded. Never a document id.
  final String reference;
  final DateTime? originalDate;
  final DateTime? cancelledAt;

  /// The record's own stored amount (its original value).
  final double amount;

  /// Stored cancellation/reversal reason; '' when none was recorded.
  final String reason;

  /// "Voided" or "Reversed".
  final String statusLabel;

  /// "Receipt" (fees_receipts, for fee collections) or "Invoice"
  /// (finance_invoices, for invoice payments); '' for manual income.
  final String linkedDocumentLabel;

  /// The linked document's id (the Fee Collection id / invoice id).
  final String linkedDocumentId;

  /// Its human-readable number (receiptNo / invoiceNo); '' when none.
  final String linkedDocumentNumber;

  /// Whether the linked document exists.
  final bool linkedDocumentFound;

  /// The linked document's own status, e.g. "Voided" / "Active" for a
  /// receipt or the invoice's status; '' when unknown.
  final String linkedDocumentStatus;

  /// The linked ledger entry's id and status ('' when there is none).
  final String ledgerId;
  final String ledgerStatus;

  /// Why this counted record needs review (e.g. its linked receipt or
  /// invoice is missing); '' when nothing needs review.
  final String reviewNote;
}

/// A record whose cancellation status or source link is unclear, so it is
/// not counted (see FinanceService.watchCancelledTransactions).
class FinanceCancellationExclusion {
  const FinanceCancellationExclusion({required this.id, required this.title, required this.reason, this.collection = 'finance_income'});

  final String id;
  final String title;
  final String reason;

  /// The Firestore collection [id] belongs to.
  final String collection;
}

class FinanceCancelledTransactionsSummary {
  const FinanceCancelledTransactionsSummary({required this.transactions, required this.exclusions});

  /// Unique cancelled source transactions, most recently cancelled first.
  final List<FinanceCancelledTransaction> transactions;

  /// Records left out because their status or link is ambiguous.
  final List<FinanceCancellationExclusion> exclusions;

  int get count => transactions.length;

  /// Sum of the original amounts. Informational only: never part of any
  /// active total or balance.
  double get originalAmount => transactions.fold<double>(0, (total, t) => total + t.amount);
}
