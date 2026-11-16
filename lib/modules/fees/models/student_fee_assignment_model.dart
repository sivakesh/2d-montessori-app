import 'package:cloud_firestore/cloud_firestore.dart';

import 'fee_amount_revision.dart';
import 'fee_discount.dart';

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
    required this.academicYearId,
    required this.totalFee,
    required this.discountAmount,
    required this.payableAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    required this.assignedAt,
    required this.updatedAt,
    this.feeMonth = '',
    this.dueDate,
    this.studentDiscount,
    this.feeRevision = 0,
    this.revisions = const [],
  });
  final String id, studentId, studentName, admissionNo, classId, className, feeStructureId, feeStructureName, academicYear, status;

  /// Canonical FK to `AcademicYearModel.id`, added in FEES-AY-IMPLEMENT-01.
  /// Empty (`''`) means this assignment predates this field (legacy) or was
  /// created against a FeeStructure whose own year couldn't be resolved to
  /// a canonical id. Never invented on read — see [academicYear]'s sibling
  /// doc comment on `AdminClassModel.academicYearId` for the same
  /// "authoritative when non-empty, compatibility string otherwise" rule.
  final String academicYearId;
  final double totalFee, discountAmount, payableAmount, paidAmount, balanceAmount;
  final DateTime? assignedAt, updatedAt;

  /// For a Monthly fee structure: the month this assignment is for, as
  /// `YYYY-MM` (FeeMonth). '' for other structures, and for assignments
  /// made before months were recorded (never inferred).
  final String feeMonth;

  /// The date this assignment is due (a calendar date, stored at local
  /// midnight as a Timestamp). Null for assignments made before due dates
  /// were recorded: never inferred.
  final DateTime? dueDate;

  /// The student's global discount applied to this assignment (its
  /// snapshot), or null: none applied (every assignment made before student
  /// discounts existed). [discountAmount] is always the total discount:
  /// this plus any manual discount.
  final FeeDiscountSnapshot? studentDiscount;

  /// How many times its fee amount has been revised (FeeRevision); 0 for
  /// every assignment never revised, including all made before revisions
  /// existed. Also the version a revision must start from (concurrency).
  final int feeRevision;

  /// Its fee revisions, oldest first (empty: never revised).
  final List<FeeAmountRevision> revisions;

  bool get isRevised => revisions.isNotEmpty;

  /// The gross fee before its first revision (its [totalFee] when never
  /// revised).
  double get originalTotalFee => revisions.isEmpty ? totalFee : revisions.first.previousTotalFee;

  /// Collected above [payableAmount] (after the fee was revised below what
  /// had been collected): a credit held, never refunded automatically; 0
  /// otherwise. Derived, so it stays right when a receipt is voided.
  double get excessCollected {
    final p = (paidAmount * 100).round() - (payableAmount * 100).round();
    return p > 0 ? p / 100 : 0;
  }

  /// The student-discount part of [discountAmount].
  double get studentDiscountAmount => studentDiscount?.amount ?? 0;

  /// The manual (assignment-specific) part of [discountAmount].
  double get manualDiscountAmount {
    final v = ((discountAmount - studentDiscountAmount) * 100).round() / 100;
    return v < 0 ? 0 : v;
  }

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
      academicYearId: data['academicYearId']?.toString() ?? '',
      totalFee: n(data['totalFee']),
      discountAmount: n(data['discountAmount']),
      payableAmount: n(data['payableAmount']),
      paidAmount: n(data['paidAmount']),
      balanceAmount: n(data['balanceAmount']),
      status: data['status']?.toString() ?? 'unpaid',
      assignedAt: d(data['assignedAt']),
      updatedAt: d(data['updatedAt']),
      feeMonth: data['feeMonth']?.toString() ?? '',
      dueDate: d(data['dueDate']),
      studentDiscount: FeeDiscountSnapshot.fromMap(data[FeeDiscountSnapshot.field]),
      feeRevision: (data[FeeRevision.revisionField] as num?)?.toInt() ?? 0,
      revisions: [
        for (final r in (data[FeeRevision.historyField] as List? ?? const [])) ?FeeAmountRevision.fromMap(r),
      ],
    );
  }
  Map<String, dynamic> toMap() => {
    'studentId': studentId,'studentName': studentName,'admissionNo': admissionNo,'classId': classId,'className': className,'feeStructureId': feeStructureId,'feeStructureName': feeStructureName,'academicYear': academicYear,'academicYearId': academicYearId,'totalFee': totalFee,'discountAmount': discountAmount,'payableAmount': payableAmount,'paidAmount': paidAmount,'balanceAmount': balanceAmount,'status': status,'assignedAt': assignedAt,'updatedAt': updatedAt,
    if (feeMonth.isNotEmpty) 'feeMonth': feeMonth,
    'dueDate': ?dueDate,
    if (studentDiscount case final s?) FeeDiscountSnapshot.field: s.toMap(),
    if (feeRevision > 0) FeeRevision.revisionField: feeRevision,
    if (revisions.isNotEmpty) FeeRevision.historyField: [for (final r in revisions) r.toMap()],
  };
}
