import 'package:cloud_firestore/cloud_firestore.dart';

class FeeTransactionModel {
  FeeTransactionModel({required this.id, required this.assignmentId, required this.studentId, required this.studentName, required this.admissionNo, required this.classId, required this.className, required this.feeStructureId, required this.feeStructureName, required this.amount, required this.paymentDate, required this.paymentMode, required this.referenceNo, required this.remarks, required this.collectedBy, required this.createdAt});
  final String id, assignmentId, studentId, studentName, admissionNo, classId, className, feeStructureId, feeStructureName, paymentMode, referenceNo, remarks, collectedBy;
  final double amount;
  final DateTime? paymentDate, createdAt;
  factory FeeTransactionModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? d(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }
    return FeeTransactionModel(
      id: id,
      assignmentId: data['assignmentId']?.toString() ?? '',
      studentId: data['studentId']?.toString() ?? '',
      studentName: data['studentName']?.toString() ?? '',
      admissionNo: data['admissionNo']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      className: data['className']?.toString() ?? '',
      feeStructureId: data['feeStructureId']?.toString() ?? '',
      feeStructureName: data['feeStructureName']?.toString() ?? '',
      amount: n(data['amount']),
      paymentDate: d(data['paymentDate']),
      paymentMode: data['paymentMode']?.toString() ?? '',
      referenceNo: data['referenceNo']?.toString() ?? '',
      remarks: data['remarks']?.toString() ?? '',
      collectedBy: data['collectedBy']?.toString() ?? '',
      createdAt: d(data['createdAt']),
    );
  }
  Map<String, dynamic> toMap() => {'assignmentId': assignmentId,'studentId': studentId,'studentName': studentName,'admissionNo': admissionNo,'classId': classId,'className': className,'feeStructureId': feeStructureId,'feeStructureName': feeStructureName,'amount': amount,'paymentDate': paymentDate,'paymentMode': paymentMode,'referenceNo': referenceNo,'remarks': remarks,'collectedBy': collectedBy,'createdAt': createdAt};
}
