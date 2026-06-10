import 'package:cloud_firestore/cloud_firestore.dart';

class AdminStudentService {
  AdminStudentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _students =>
      _firestore.collection('students');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchStudents() {
    return _students.orderBy('createdAt', descending: true).snapshots();
  }
}
