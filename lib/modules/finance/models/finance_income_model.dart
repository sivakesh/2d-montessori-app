import 'package:cloud_firestore/cloud_firestore.dart';

class FinanceIncomeModel {
  FinanceIncomeModel({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.categoryName,
    required this.programType,
    required this.studentId,
    required this.studentName,
    required this.classId,
    required this.className,
    required this.amount,
    required this.incomeDate,
    required this.paymentMode,
    required this.accountId,
    required this.accountName,
    required this.referenceNo,
    required this.remarks,
    required this.attachmentUrls,
    required this.ledgerEntryId,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    this.sourceModule = '',
    this.isDeleted = false,
  });
  final String id, title, categoryId, categoryName, programType, studentId, studentName, classId, className, paymentMode, accountId, accountName, referenceNo, remarks, ledgerEntryId, createdBy;
  final double amount;
  final DateTime? incomeDate, createdAt, updatedAt;
  final List<String> attachmentUrls;
  /// Raw Firestore field already written by FinanceService.createFeeIncomeEntry
  /// ('fees') — never written by the plain createIncome path, where it's
  /// absent and defaults to ''. Used by the Finance UI to detect and lock
  /// editing/voiding of a Fee-Collection-generated entry (see
  /// FinanceService.updateIncome/voidIncome's doc comments for why).
  final String sourceModule;
  /// Raw Firestore field already written by FinanceService's void/reversal
  /// paths (_voidIncomeDoc). Not present on an active entry.
  final bool isDeleted;
  factory FinanceIncomeModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? p(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return FinanceIncomeModel(
      id: id,
      title: data['title']?.toString() ?? '',
      categoryId: data['categoryId']?.toString() ?? '',
      categoryName: data['categoryName']?.toString() ?? '',
      programType: data['programType']?.toString() ?? '',
      studentId: data['studentId']?.toString() ?? '',
      studentName: data['studentName']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      className: data['className']?.toString() ?? '',
      amount: n(data['amount']),
      incomeDate: p(data['incomeDate']),
      paymentMode: data['paymentMode']?.toString() ?? '',
      accountId: data['accountId']?.toString() ?? '',
      accountName: data['accountName']?.toString() ?? '',
      referenceNo: data['referenceNo']?.toString() ?? '',
      remarks: data['remarks']?.toString() ?? '',
      attachmentUrls: (data['attachmentUrls'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
      ledgerEntryId: data['ledgerEntryId']?.toString() ?? '',
      createdAt: p(data['createdAt']),
      updatedAt: p(data['updatedAt']),
      createdBy: data['createdBy']?.toString() ?? '',
      sourceModule: data['sourceModule']?.toString() ?? '',
      isDeleted: data['isDeleted'] == true,
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
        'programType': programType,
        'studentId': studentId,
        'studentName': studentName,
        'classId': classId,
        'className': className,
        'amount': amount,
        'incomeDate': incomeDate,
        'paymentMode': paymentMode,
        'accountId': accountId,
        'accountName': accountName,
        'referenceNo': referenceNo,
        'remarks': remarks,
        'attachmentUrls': attachmentUrls,
        'ledgerEntryId': ledgerEntryId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
      };

  Map<String, dynamic> toLedgerMap(String id, {required String createdBy}) => {
        'id': id,
        'entryType': 'income',
        'sourceModule': 'finance',
        'sourceId': this.id,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'subCategoryName': programType,
        'title': title,
        'description': remarks,
        'amount': amount,
        'transactionDate': incomeDate,
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
