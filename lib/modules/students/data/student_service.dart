import 'package:cloud_firestore/cloud_firestore.dart';
import '../../parent/data/parent_projection_service.dart';

class StudentService {
  StudentService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchStudents({
    bool activeOnly = true,
    String? classId,
  }) {
    Query<Map<String, dynamic>> base = _students.orderBy(
      'createdAt',
      descending: true,
    );
    if (activeOnly) {
      base = base.where('isActive', isEqualTo: true);
    }
    if (classId != null && classId.isNotEmpty) {
      base = base.where('classId', isEqualTo: classId);
    }
    return base.snapshots();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  getAllStudents() async {
    final snapshot = await _students.where('isActive', isEqualTo: true).get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudentsByClass(
    String classId,
  ) async {
    // ignore: avoid_print
    print('Fetching students for class: $classId');
    final snapshot = await _students
        .where('classId', isEqualTo: classId)
        .where('isActive', isEqualTo: true)
        .get();
    return snapshot.docs;
  }

  Future<void> createStudent(Map<String, dynamic> data) async {
    final doc = await _students.add(data);
    await _refreshParentCopy(doc.id);
  }

  Future<void> updateStudent({
    required String studentId,
    required Map<String, dynamic> data,
  }) async {
    await _students.doc(studentId).update(data);
    await _refreshParentCopy(studentId);
  }

  /// After a change to student [id]: refreshes the copy parents read
  /// (parent_student_profiles) and the class list on their access records
  /// (docs/parent_access_security.md). Runs after the change has been saved
  /// and never throws.
  Future<void> _refreshParentCopy(String id) => ParentProjectionService(firestore: _firestore).syncStudentQuietly(id);
}
