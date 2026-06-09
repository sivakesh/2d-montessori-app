import 'package:cloud_firestore/cloud_firestore.dart';

class ClassService {
  ClassService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _classes =>
      _firestore.collection('classes');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchClasses() {
    return _classes.orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> createClass(String name) async {
    await _classes.add({
      'name': name,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateClass({
    required String classId,
    required String name,
    required bool isActive,
  }) async {
    await _classes.doc(classId).update({
      'name': name,
      'isActive': isActive,
    });
  }
}
