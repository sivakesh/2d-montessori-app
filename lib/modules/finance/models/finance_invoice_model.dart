import 'package:cloud_firestore/cloud_firestore.dart';

class FinanceInvoiceModel {
  FinanceInvoiceModel({
    required this.id,
    required this.type,
    required this.partyId,
    required this.partyName,
    required this.categoryName,
    required this.invoiceNo,
    required this.invoiceDate,
    required this.dueDate,
    required this.amount,
    required this.taxAmount,
    required this.deductions,
    required this.bonus,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.description,
    required this.attachmentUrl,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.reversedAt,
  });

  final String id;
  final String type;
  final String partyId;
  final String partyName;
  final String categoryName;
  final String invoiceNo;
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final double amount;
  final double taxAmount;
  final double deductions;
  final double bonus;
  final double totalAmount;
  final double paidAmount;
  final double balanceAmount;
  final String description;
  final String attachmentUrl;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final DateTime? reversedAt;

  factory FinanceInvoiceModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parse(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double numVal(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return FinanceInvoiceModel(
      id: id,
      type: data['type']?.toString() ?? 'expense',
      partyId: data['partyId']?.toString() ?? '',
      partyName: data['partyName']?.toString() ?? '',
      categoryName: data['categoryName']?.toString() ?? '',
      invoiceNo: data['invoiceNo']?.toString() ?? '',
      invoiceDate: parse(data['invoiceDate']),
      dueDate: parse(data['dueDate']),
      amount: numVal(data['amount']),
      taxAmount: numVal(data['taxAmount']),
      deductions: numVal(data['deductions']),
      bonus: numVal(data['bonus']),
      totalAmount: numVal(data['totalAmount']),
      paidAmount: numVal(data['paidAmount']),
      balanceAmount: numVal(data['balanceAmount']),
      description: data['description']?.toString() ?? '',
      attachmentUrl: data['attachmentUrl']?.toString() ?? '',
      status: data['status']?.toString() ?? 'unpaid',
      createdAt: parse(data['createdAt']),
      updatedAt: parse(data['updatedAt']),
      createdBy: data['createdBy']?.toString() ?? '',
      reversedAt: parse(data['reversedAt']),
    );
  }
}
