import 'package:cloud_firestore/cloud_firestore.dart';

class FeeReceiptModel {
  FeeReceiptModel({required this.id, required this.receiptNo, required this.transactionId, required this.assignmentId, required this.studentId, required this.studentName, required this.admissionNo, required this.className, required this.feeStructureName, required this.amount, required this.paymentMode, required this.paymentDate, required this.referenceNo, required this.createdAt, required this.createdBy, required this.pdfUrl, required this.pdfPath, required this.pdfGeneratedAt});
  final String id, receiptNo, transactionId, assignmentId, studentId, studentName, admissionNo, className, feeStructureName, paymentMode, referenceNo, createdBy, pdfUrl, pdfPath;
  final double amount;
  final DateTime? paymentDate, createdAt, pdfGeneratedAt;
  factory FeeReceiptModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? d(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }
    return FeeReceiptModel(
      id: id,
      receiptNo: data['receiptNo']?.toString() ?? '',
      transactionId: data['transactionId']?.toString() ?? '',
      assignmentId: data['assignmentId']?.toString() ?? '',
      studentId: data['studentId']?.toString() ?? '',
      studentName: data['studentName']?.toString() ?? '',
      admissionNo: data['admissionNo']?.toString() ?? '',
      className: data['className']?.toString() ?? '',
      feeStructureName: data['feeStructureName']?.toString() ?? '',
      amount: n(data['amount']),
      paymentMode: data['paymentMode']?.toString() ?? '',
      paymentDate: d(data['paymentDate']),
      referenceNo: data['referenceNo']?.toString() ?? '',
      createdAt: d(data['createdAt']),
      createdBy: data['createdBy']?.toString() ?? '',
      pdfUrl: data['pdfUrl']?.toString() ?? '',
      pdfPath: data['pdfPath']?.toString() ?? '',
      pdfGeneratedAt: d(data['pdfGeneratedAt']),
    );
  }
  Map<String, dynamic> toMap() => {'receiptNo': receiptNo,'transactionId': transactionId,'assignmentId': assignmentId,'studentId': studentId,'studentName': studentName,'admissionNo': admissionNo,'className': className,'feeStructureName': feeStructureName,'amount': amount,'paymentMode': paymentMode,'paymentDate': paymentDate,'referenceNo': referenceNo,'createdAt': createdAt,'createdBy': createdBy,'pdfUrl': pdfUrl,'pdfPath': pdfPath,'pdfGeneratedAt': pdfGeneratedAt};
}
