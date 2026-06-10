import 'package:cloud_firestore/cloud_firestore.dart';

class AdminClassService {
  AdminClassService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _classes =>
      _firestore.collection('classes');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchClasses() {
    return _classes.orderBy('createdAt', descending: true).snapshots();
  }
}
