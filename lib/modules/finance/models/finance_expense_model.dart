import 'package:cloud_firestore/cloud_firestore.dart';

class FinanceExpenseModel {
  FinanceExpenseModel({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.categoryName,
    required this.vendorId,
    required this.vendorName,
    required this.amount,
    required this.expenseDate,
    required this.paymentMode,
    required this.accountId,
    required this.accountName,
    required this.referenceNo,
    required this.billNo,
    required this.remarks,
    required this.attachmentUrls,
    required this.ledgerEntryId,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });
  final String id, title, categoryId, categoryName, vendorId, vendorName, paymentMode, accountId, accountName, referenceNo, billNo, remarks, ledgerEntryId, createdBy;
  final double amount;
  final DateTime? expenseDate, createdAt, updatedAt;
  final List<String> attachmentUrls;
  factory FinanceExpenseModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? p(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return FinanceExpenseModel(
      id: id,
      title: data['title']?.toString() ?? '',
      categoryId: data['categoryId']?.toString() ?? '',
      categoryName: data['categoryName']?.toString() ?? '',
      vendorId: data['vendorId']?.toString() ?? '',
      vendorName: data['vendorName']?.toString() ?? '',
      amount: n(data['amount']),
      expenseDate: p(data['expenseDate']),
      paymentMode: data['paymentMode']?.toString() ?? '',
      accountId: data['accountId']?.toString() ?? '',
      accountName: data['accountName']?.toString() ?? '',
      referenceNo: data['referenceNo']?.toString() ?? '',
      billNo: data['billNo']?.toString() ?? '',
      remarks: data['remarks']?.toString() ?? '',
      attachmentUrls: (data['attachmentUrls'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      ledgerEntryId: data['ledgerEntryId']?.toString() ?? '',
      createdAt: p(data['createdAt']),
      updatedAt: p(data['updatedAt']),
      createdBy: data['createdBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap(
    String id, {
    required String ledgerEntryId,
    required String createdBy,
  }) =>
      {
        'id': id,
        'title': title,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'vendorId': vendorId,
        'vendorName': vendorName,
        'amount': amount,
        'expenseDate': expenseDate,
        'paymentMode': paymentMode,
        'accountId': accountId,
        'accountName': accountName,
        'referenceNo': referenceNo,
        'billNo': billNo,
        'remarks': remarks,
        'attachmentUrls': attachmentUrls,
        'ledgerEntryId': ledgerEntryId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
      };

  Map<String, dynamic> toLedgerMap(String id, {required String createdBy}) => {
        'id': id,
        'entryType': 'expense',
        'sourceModule': 'finance',
        'sourceId': this.id,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'subCategoryName': vendorName,
        'title': title,
        'description': remarks,
        'amount': amount,
        'transactionDate': expenseDate,
        'paymentMode': paymentMode,
        'accountId': accountId,
        'accountName': accountName,
        'referenceNo': referenceNo,
        'attachmentUrls': attachmentUrls,
        'status': 'confirmed',
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
      };
}
