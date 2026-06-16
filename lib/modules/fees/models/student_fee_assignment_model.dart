import 'package:cloud_firestore/cloud_firestore.dart';

class StudentFeeAssignmentModel {
  StudentFeeAssignmentModel({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.admissionNo,
    required this.classId,
    required this.className,
    required this.feeStructureId,
    required this.feeStructureName,
    required this.academicYear,
    required this.totalFee,
    required this.discountAmount,
    required this.payableAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    required this.assignedAt,
    required this.updatedAt,
  });
  final String id, studentId, studentName, admissionNo, classId, className, feeStructureId, feeStructureName, academicYear, status;
  final double totalFee, discountAmount, payableAmount, paidAmount, balanceAmount;
  final DateTime? assignedAt, updatedAt;
  factory StudentFeeAssignmentModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? d(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : null;
    double n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }
    return StudentFeeAssignmentModel(
      id: id,
      studentId: data['studentId']?.toString() ?? '',
      studentName: data['studentName']?.toString() ?? '',
      admissionNo: data['admissionNo']?.toString() ?? '',
      classId: data['classId']?.toString() ?? '',
      className: data['className']?.toString() ?? '',
      feeStructureId: data['feeStructureId']?.toString() ?? '',
      feeStructureName: data['feeStructureName']?.toString() ?? '',
      academicYear: data['academicYear']?.toString() ?? '',
      totalFee: n(data['totalFee']),
      discountAmount: n(data['discountAmount']),
      payableAmount: n(data['payableAmount']),
      paidAmount: n(data['paidAmount']),
      balanceAmount: n(data['balanceAmount']),
      status: data['status']?.toString() ?? 'unpaid',
      assignedAt: d(data['assignedAt']),
      updatedAt: d(data['updatedAt']),
    );
  }
  Map<String, dynamic> toMap() => {
    'studentId': studentId,'studentName': studentName,'admissionNo': admissionNo,'classId': classId,'className': className,'feeStructureId': feeStructureId,'feeStructureName': feeStructureName,'academicYear': academicYear,'totalFee': totalFee,'discountAmount': discountAmount,'payableAmount': payableAmount,'paidAmount': paidAmount,'balanceAmount': balanceAmount,'status': status,'assignedAt': assignedAt,'updatedAt': updatedAt,
  };
}
