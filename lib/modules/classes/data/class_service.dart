import 'package:cloud_firestore/cloud_firestore.dart';

class ClassService {
  ClassService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _classes =>
      _firestore.collection('classes');

  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getClasses() async {
    final snapshot = await _classes.orderBy('createdAt', descending: true).get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllClasses() async {
    final snapshot = await _classes.get();
    return snapshot.docs;
  }

  Future<void> createClass(dynamic data) async {
    if (data is String) {
      await _classes.add({
        'name': data,
        'isActive': true,
        'approvalStatus': 'Pending Approval',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin',
      });
      return;
    }
    await _classes.add(Map<String, dynamic>.from(data as Map));
  }

  Future<void> updateClass({
    required String classId,
    Map<String, dynamic>? data,
    String? name,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{};
    if (data != null) payload.addAll(data);
    if (name != null) payload['name'] = name;
    if (isActive != null) payload['isActive'] = isActive;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    await _classes.doc(classId).set(payload, SetOptions(merge: true));
  }

  Future<void> deleteClass(String classId) async {
    await _classes.doc(classId).delete();
  }

  Future<void> seedSampleClasses() async {
    final existing = await _classes.get();
    final existingNames = existing.docs
        .map((doc) => doc.data()['name']?.toString().trim().toLowerCase() ?? '')
        .toSet();

    final samples = <Map<String, dynamic>>[
      {
        'name': 'Pre Mont',
        'section': 'A',
        'academicYear': '2026-2027',
        'capacity': 18,
        'teacherName': 'Ms. Ananya',
        'description': 'Introductory class for preschoolers.',
        'isActive': true,
        'approvalStatus': 'Approved',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': 'seed',
      },
      {
        'name': 'Mont 1',
        'section': 'A',
        'academicYear': '2026-2027',
        'capacity': 22,
        'teacherName': 'Mr. Rahul',
        'description': 'Foundation Montessori class.',
        'isActive': true,
        'approvalStatus': 'Approved',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': 'seed',
      },
      {
        'name': 'Mont 2',
        'section': 'B',
        'academicYear': '2026-2027',
        'capacity': 24,
        'teacherName': 'Ms. Priya',
        'description': 'Intermediate Montessori class.',
        'isActive': true,
        'approvalStatus': 'Approved',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': 'seed',
      },
      {
        'name': 'Mont 3',
        'section': 'A',
        'academicYear': '2026-2027',
        'capacity': 26,
        'teacherName': 'Ms. Kavya',
        'description': 'Advanced Montessori class.',
        'isActive': true,
        'approvalStatus': 'Approved',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': 'seed',
      },
    ];

    for (final sample in samples) {
      final name = sample['name'].toString().trim().toLowerCase();
      if (existingNames.contains(name)) continue;
      await _classes.add(sample);
    }
  }

  Future<int> getStudentCountByClassId(String classId) async {
    final snapshot = await _students.where('classId', isEqualTo: classId).get();
    return snapshot.docs.length;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getStudentsByClassId(
    String classId,
  ) async {
    final snapshot = await _students.where('classId', isEqualTo: classId).get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllTeachers() async {
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'staff')
        .get();
    return snapshot.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllClassStudents(
    String classId,
  ) {
    return getStudentsByClassId(classId);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchClasses() {
    return _classes.orderBy('createdAt', descending: true).snapshots();
  }
}
