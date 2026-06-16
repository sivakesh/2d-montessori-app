import 'package:cloud_firestore/cloud_firestore.dart';

class StaffSalaryPaymentModel {
  StaffSalaryPaymentModel({
    required this.id,
    required this.staffUserId,
    required this.staffName,
    required this.salaryMonth,
    required this.salaryYear,
    required this.baseSalary,
    required this.allowanceAmount,
    required this.deductionAmount,
    required this.netPayable,
    required this.paidAmount,
    required this.balanceAmount,
    required this.paymentDate,
    required this.paymentMode,
    required this.accountId,
    required this.accountName,
    required this.referenceNo,
    required this.status,
    required this.remarks,
    required this.ledgerEntryId,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });
  final String id, staffUserId, staffName, salaryMonth, salaryYear, paymentMode, accountId, accountName, referenceNo, status, remarks, ledgerEntryId, createdBy;
  final double baseSalary, allowanceAmount, deductionAmount, netPayable, paidAmount, balanceAmount;
  final DateTime? paymentDate, createdAt, updatedAt;
  factory StaffSalaryPaymentModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? p(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    return StaffSalaryPaymentModel(
      id: id,
      staffUserId: data['staffUserId']?.toString() ?? '',
      staffName: data['staffName']?.toString() ?? '',
      salaryMonth: data['salaryMonth']?.toString() ?? '',
      salaryYear: data['salaryYear']?.toString() ?? '',
      baseSalary: n(data['baseSalary']),
      allowanceAmount: n(data['allowanceAmount']),
      deductionAmount: n(data['deductionAmount']),
      netPayable: n(data['netPayable']),
      paidAmount: n(data['paidAmount']),
      balanceAmount: n(data['balanceAmount']),
      paymentDate: p(data['paymentDate']),
      paymentMode: data['paymentMode']?.toString() ?? '',
      accountId: data['accountId']?.toString() ?? '',
      accountName: data['accountName']?.toString() ?? '',
      referenceNo: data['referenceNo']?.toString() ?? '',
      status: data['status']?.toString() ?? 'unpaid',
      remarks: data['remarks']?.toString() ?? '',
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
        'staffUserId': staffUserId,
        'staffName': staffName,
        'salaryMonth': salaryMonth,
        'salaryYear': salaryYear,
        'baseSalary': baseSalary,
        'allowanceAmount': allowanceAmount,
        'deductionAmount': deductionAmount,
        'netPayable': netPayable,
        'paidAmount': paidAmount,
        'balanceAmount': balanceAmount,
        'paymentDate': paymentDate,
        'paymentMode': paymentMode,
        'accountId': accountId,
        'accountName': accountName,
        'referenceNo': referenceNo,
        'status': status,
        'remarks': remarks,
        'ledgerEntryId': ledgerEntryId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'createdBy': createdBy,
      };
}
