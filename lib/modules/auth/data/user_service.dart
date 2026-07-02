import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';

class UserService {
  UserService([FirebaseFirestore? db])
    : _firestore = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String normalizePhone(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= 10) {
      return digitsOnly.substring(digitsOnly.length - 10);
    }
    return digitsOnly;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findUserDocumentByPhone(
    String phone,
  ) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty) return null;

    const fields = ['phone', 'phoneNumber', 'mobile', 'contactNumber'];
    for (final field in fields) {
      final result = await _firestore
          .collection('users')
          .where(field, isEqualTo: normalizedPhone)
          .limit(1)
          .get();
      if (result.docs.isNotEmpty) {
        return result.docs.first;
      }
    }

    final allUsers = await _firestore.collection('users').get();
    for (final doc in allUsers.docs) {
      final data = doc.data();
      for (final field in fields) {
        final value = data[field]?.toString();
        if (value == null || value.isEmpty) continue;
        if (normalizePhone(value) == normalizedPhone) {
          return doc;
        }
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> getUserByPhone(String phone) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty) return null;

    final doc = await _firestore.collection('users').doc(normalizedPhone).get();
    final data = doc.data();

    if (data == null) return null;

    return {
      ...data,
      'id': doc.id,
      'phoneNumber': data['phoneNumber'] ?? doc.id,
    };
  }

  Future<Map<String, dynamic>?> getUserByUid(String uid) async {
    final result = await _firestore
        .collection('users')
        .where('firebaseAuthUid', isEqualTo: uid)
        .limit(1)
        .get();

    if (result.docs.isEmpty) return null;

    final doc = result.docs.first;
    final data = doc.data();
    return {
      ...data,
      'id': doc.id,
      'phoneNumber': data['phoneNumber'] ?? doc.id,
    };
  }

  Future<Map<String, dynamic>?> getUser(String uid) async {
    return getUserByUid(uid);
  }

  Future<Map<String, dynamic>?> getUserByFirebaseAuthUid(
    String firebaseAuthUid,
  ) async {
    return getUserByUid(firebaseAuthUid);
  }

  Future<Map<String, dynamic>?> findUserByPhone(String phoneNumber) async {
    return getUserByPhone(phoneNumber);
  }

  CollectionReference<Map<String, dynamic>> get _prodUsers =>
      _firestore.collection('prod_users');

  Future<Map<String, dynamic>?> getProdUserByPhone(String phone) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty) return null;

    final doc = await _prodUsers.doc(normalizedPhone).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  Future<Map<String, dynamic>?> getProdUserByUid(String uid) async {
    final result = await _prodUsers
        .where('authUid', isEqualTo: uid)
        .limit(1)
        .get();
    if (result.docs.isEmpty) return null;
    return result.docs.first.data();
  }

  Future<MapEntry<String, Map<String, dynamic>>?> resolveProdUser({
    required String authUid,
    required String phone,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty) return null;
    final user = await getUserByPhone(normalizedPhone);
    if (user == null) return null;
    return MapEntry(normalizedPhone, user);
  }

  Future<MapEntry<String, Map<String, dynamic>>> resolveProdUserAfterPhoneAuth({
    required String authUid,
    required String rawPhone,
    String name = 'User',
    String email = '',
  }) async {
    final normalizedPhone = normalizePhone(rawPhone);
    if (normalizedPhone.isEmpty) {
      throw StateError('User setup failed');
    }

    debugPrint('writing prod_users/$normalizedPhone');
    final userData = await getOrCreateProdUser(
      firebaseAuthUid: authUid,
      phoneNumber: normalizedPhone,
    );

    return MapEntry(normalizedPhone, userData);
  }

  Future<Map<String, dynamic>> getOrCreateProdUser({
    required String firebaseAuthUid,
    required String phoneNumber,
  }) async {
    final normalizedPhone = normalizePhone(phoneNumber);
    final ref = _firestore.collection('users').doc(normalizedPhone);
    final doc = await ref.get();
    final data = doc.data();

    if (data != null && data['isActive'] == false) {
      throw firebase_auth.FirebaseAuthException(
        code: 'user-disabled',
        message: 'This account has been deactivated. Please contact admin.',
      );
    }

    final payload = <String, dynamic>{
      if (data != null) ...data,
      'phoneNumber': normalizedPhone,
      'firebaseAuthUid': firebaseAuthUid,
      'role': data?['role'] ?? 'parent',
      'isActive': data?['isActive'] ?? true,
      'isOnboarded': true,
      'linkedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (data == null || data['createdAt'] == null)
        'createdAt': FieldValue.serverTimestamp(),
    };

    await ref.set(payload, SetOptions(merge: true));

    final saved = await ref.get();
    final savedData = saved.data();

    if (savedData == null) {
      throw firebase_auth.FirebaseAuthException(
        code: 'user-create-failed',
        message: 'Could not create your account. Please try again.',
      );
    }

    return {...savedData, 'id': saved.id, 'phoneNumber': normalizedPhone};
  }

  Future<Map<String, dynamic>> getOrCreateDevUser(String phoneNumber) async {
    if (kReleaseMode) {
      throw Exception('DEV flow cannot run in release mode.');
    }

    final normalizedPhone = normalizePhone(phoneNumber);
    final existing = await getUserByPhone(normalizedPhone);

    if (existing != null) {
      if (existing['isActive'] == false) {
        throw Exception('This account has been deactivated. Contact admin.');
      }
      return existing;
    }

    return createDevUser(normalizedPhone);
  }

  Future<void> linkProdUserToAuth({
    required String phone,
    required String authUid,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    await _prodUsers.doc(normalizedPhone).set({
      'firebaseAuthUid': authUid,
      'phoneNumber': normalizedPhone,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> createProdUser({
    required String authUid,
    required String phone,
    String name = '',
    String email = '',
  }) async {
    final normalizedPhone = normalizePhone(phone);
    await _prodUsers.doc(normalizedPhone).set({
      'authUid': authUid,
      'uid': authUid,
      'phoneNumber': normalizedPhone,
      'phone': normalizedPhone,
      'name': name,
      'email': email,
      'role': 'parent',
      'status': 'active',
      'environment': 'prod',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  Future<MapEntry<String, Map<String, dynamic>>?> resolveUserByAuthUidOrPhone({
    required String authUid,
    required String phone,
  }) async {
    final normalizedPhone = normalizePhone(phone);

    final authDoc = await _firestore.collection('users').doc(authUid).get();
    if (authDoc.exists && authDoc.data() != null) {
      return MapEntry(authDoc.id, authDoc.data()!);
    }

    final authUidQuery = await _firestore
        .collection('users')
        .where('authUid', isEqualTo: authUid)
        .limit(1)
        .get();
    if (authUidQuery.docs.isNotEmpty) {
      final doc = authUidQuery.docs.first;
      return MapEntry(doc.id, doc.data());
    }

    if (normalizedPhone.isNotEmpty) {
      final phoneDoc = await findUserDocumentByPhone(normalizedPhone);
      if (phoneDoc != null) {
        return MapEntry(phoneDoc.id, phoneDoc.data());
      }
    }

    return null;
  }

  Future<void> linkUserToAuth({
    required String userId,
    required String authUid,
    required String phoneNumber,
  }) async {
    await _firestore.collection('users').doc(userId).set({
      'authUid': authUid,
      'uid': authUid,
      'phoneNumber': normalizePhone(phoneNumber),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<AppUser>> getStaffUsers() async {
    final result = await _firestore
        .collection('users')
        .where('isActive', isEqualTo: true)
        .get();
    const staffRoles = {'staff', 'teacher', 'admin_staff'};
    final seen = <String>{};
    final staff = <AppUser>[];

    for (final doc in result.docs) {
      final user = AppUser.fromMap(doc.id, doc.data());
      if (!staffRoles.contains(user.role.toLowerCase())) continue;
      if (!seen.add(user.id)) continue;
      staff.add(user);
    }

    return staff;
  }

  Future<List<AppUser>> getAttendanceStaffUsers() async {
    final result = await _firestore
        .collection('users')
        .where('isActive', isEqualTo: true)
        .where('role', isEqualTo: 'staff')
        .get();

    final seen = <String>{};
    final staff = <AppUser>[];

    for (final doc in result.docs) {
      final user = AppUser.fromMap(doc.id, doc.data());
      if (!seen.add(user.id)) continue;
      staff.add(user);
    }

    return staff;
  }

  Future<void> createUser(String uid, String phone) async {
    final normalizedPhone = normalizePhone(phone);
    await _firestore.collection('users').doc(normalizedPhone).set({
      'phoneNumber': normalizedPhone,
      'firebaseAuthUid': uid,
      'role': 'parent',
      'status': 'active',
      'isOnboarded': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isActive': true,
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> createDevUser(String phoneNumber) async {
    final normalizedPhone = normalizePhone(phoneNumber);
    final ref = _firestore.collection('users').doc(normalizedPhone);
    await ref.set({
      'phoneNumber': normalizedPhone,
      'firebaseAuthUid': null,
      'role': 'parent',
      'isActive': true,
      'isOnboarded': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final created = await ref.get();
    final data = created.data();
    if (data == null) {
      throw Exception('Failed to create dev user.');
    }

    return {...data, 'id': created.id, 'phoneNumber': normalizedPhone};
  }
}
