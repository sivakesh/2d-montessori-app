import '../../admin/students/models/admission_date.dart';

/// A student as the Fees module lists and filters them: the stable
/// document id plus the fields shown. Read from `students`; never written.
class FeeStudent {
  const FeeStudent({required this.id, required this.name, this.admissionNo = '', this.classId = '', this.isActive = true, this.admissionDate});

  factory FeeStudent.fromMap(String id, Map<String, dynamic> data) => FeeStudent(
        id: id,
        name: data['name']?.toString() ?? '',
        admissionNo: data['admissionNo']?.toString() ?? '',
        classId: data['classId']?.toString() ?? '',
        isActive: data['isActive'] != false,
        admissionDate: AdmissionDate.parse(data['admissionDate']),
      );

  final String id, name, admissionNo;

  /// The student's current class (`students.classId`).
  final String classId;
  final bool isActive;

  /// `students.admissionDate`; null when not recorded (never inferred).
  final DateTime? admissionDate;
}
