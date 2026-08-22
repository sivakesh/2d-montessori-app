import 'package:cloud_firestore/cloud_firestore.dart';

import '../../admin/students/models/admin_student_model.dart';

/// Read-only composition service for the Parent MVP. Deliberately thin: it
/// only resolves "which students belong to this parent" and hands back the
/// existing [AdminStudentModel] records for them — attendance, fees and
/// notifications are each fetched by the Parent Dashboard itself, directly
/// through the existing AttendanceService/FeeService/AdminNotificationService,
/// exactly the same way DashboardScreen already composes several services'
/// data for the Admin/Staff dashboard.
///
/// No new collection is introduced here. `user_student_links` is the same
/// join collection the Admin "Students → Parent Links" tab
/// (admin_student_form.dart's `_saveParentLinks`) already writes to, and the
/// same one admin_profile_form.dart already reads from — this mirrors that
/// exact query, just scoped to the signed-in parent's own `userId` instead
/// of an admin-chosen one.
class ParentService {
  ParentService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _links =>
      _firestore.collection('user_student_links');
  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');

  /// Students linked to [parentUserId]. Never queries the `students`
  /// collection broadly — resolves the specific linked student ids first
  /// via `user_student_links`, then fetches exactly those documents by id.
  /// Inactive/soft-deleted students are excluded, matching how the Admin
  /// Students list already treats `isActive`.
  Future<List<AdminStudentModel>> getLinkedStudents(String parentUserId) async {
    if (parentUserId.isEmpty) return [];

    final linkSnap = await _links
        .where('userId', isEqualTo: parentUserId)
        .get();
    final studentIds = linkSnap.docs
        .map((doc) => doc.data()['studentId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (studentIds.isEmpty) return [];

    final studentDocs = await Future.wait(
      studentIds.map((id) => _students.doc(id).get()),
    );

    return studentDocs
        .where((doc) => doc.exists && doc.data() != null)
        .map((doc) => AdminStudentModel.fromMap(doc.id, doc.data()!))
        .where((student) => student.isActive)
        .toList();
  }
}
