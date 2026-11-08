import 'fee_receipt_model.dart';

/// One payment against a fee assignment, as the Collection Details view
/// shows it: the fee receipt (the collection record itself, linked to its
/// assignment by `assignmentId`), whether it has been voided, and the notes
/// kept on its fee transaction. Built read-only by
/// FeeService.getCollectionHistory; nothing here is ever written back.
class FeeCollectionRecord {
  const FeeCollectionRecord({required this.receipt, required this.isVoided, this.voidedAt, this.remarks = ''});

  final FeeReceiptModel receipt;

  /// Voided (cancelled) through Void: the receipt is kept for audit with
  /// `isDeleted` set, and its amount no longer counts as paid.
  final bool isVoided;
  final DateTime? voidedAt;

  /// The collection's notes, from its fee transaction ('' when none, or
  /// when the transaction can't be found).
  final String remarks;

  /// Whether this payment counts towards the amount collected.
  bool get counts => !isVoided;
}
