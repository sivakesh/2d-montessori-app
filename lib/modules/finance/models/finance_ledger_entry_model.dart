import 'package:cloud_firestore/cloud_firestore.dart';

class FinanceLedgerEntryModel {
  FinanceLedgerEntryModel({
    required this.id,
    required this.entryType,
    required this.sourceModule,
    required this.sourceId,
    required this.categoryId,
    required this.categoryName,
    required this.subCategoryName,
    required this.title,
    required this.description,
    required this.amount,
    required this.transactionDate,
    required this.paymentMode,
    required this.accountId,
    required this.accountName,
    required this.referenceNo,
    required this.attachmentUrls,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });
  final String id, entryType, sourceModule, sourceId, categoryId, categoryName, subCategoryName, title, description, paymentMode, accountId, accountName, referenceNo, status, createdBy;
  final double amount;
  final DateTime? transactionDate, createdAt, updatedAt;
  final List<String> attachmentUrls;
  factory FinanceLedgerEntryModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? p(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return FinanceLedgerEntryModel(
      id: id,
      entryType: data['entryType']?.toString() ?? 'income',
      sourceModule: data['sourceModule']?.toString() ?? 'manual',
      sourceId: data['sourceId']?.toString() ?? '',
      categoryId: data['categoryId']?.toString() ?? '',
      categoryName: data['categoryName']?.toString() ?? '',
      subCategoryName: data['subCategoryName']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      amount: n(data['amount']),
      transactionDate: p(data['transactionDate']),
      paymentMode: data['paymentMode']?.toString() ?? '',
      accountId: data['accountId']?.toString() ?? '',
      accountName: data['accountName']?.toString() ?? '',
      referenceNo: data['referenceNo']?.toString() ?? '',
      attachmentUrls: (data['attachmentUrls'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      status: data['status']?.toString() ?? 'confirmed',
      createdAt: p(data['createdAt']),
      updatedAt: p(data['updatedAt']),
      createdBy: data['createdBy']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap({required String createdBy}) => {
        'id': id,
        'entryType': entryType,
        'sourceModule': sourceModule,
        'sourceId': sourceId,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'subCategoryName': subCategoryName,
        'title': title,
        'description': description,
        'amount': amount,
        'transactionDate': transactionDate,
        'paymentMode': paymentMode,
        'accountId': accountId,
        'accountName': accountName,
        'referenceNo': referenceNo,
        'attachmentUrls': attachmentUrls,
        'status': status,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
      };
}
