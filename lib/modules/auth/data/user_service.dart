import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getUserByPhone(String phone) async {
    final result = await _firestore
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;

    return result.docs.first.data();
  }

  Future<Map<String, dynamic>?> getUserByUid(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();

    if (!doc.exists) return null;

    return doc.data();
  }

  Future<void> createUser(String uid, String phone) async {
    await _firestore.collection('users').doc(uid).set({
      'phone': phone,
      'role': 'staff',
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': true,
    });
  }
}
