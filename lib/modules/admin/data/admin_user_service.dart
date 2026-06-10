import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUserService {
  AdminUserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchUsers() {
    return _users.orderBy('createdAt', descending: true).snapshots();
  }

  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) async {
    await _users.doc(userId).set({'role': role}, SetOptions(merge: true));
  }

  Future<void> setUserActive({
    required String userId,
    required bool isActive,
  }) async {
    await _users.doc(userId).set({'isActive': isActive}, SetOptions(merge: true));
  }
}
