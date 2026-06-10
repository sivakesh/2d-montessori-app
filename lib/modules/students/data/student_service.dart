import 'package:cloud_firestore/cloud_firestore.dart';

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
    await _students.add(data);
  }

  Future<void> updateStudent({
    required String studentId,
    required Map<String, dynamic> data,
  }) async {
    await _students.doc(studentId).update(data);
  }
}
