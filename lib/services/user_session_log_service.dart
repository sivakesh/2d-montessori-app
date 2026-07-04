import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:montessori_app/core/config/app_env.dart';
import 'package:montessori_app/modules/auth/data/user_service.dart';
import 'package:montessori_app/services/user_agent.dart';

class UserSessionLogService {
  UserSessionLogService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    UserService? userService,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _userService = userService ?? UserService();

  final FirebaseAuth _firebaseAuth;
  final FirebaseFirestore _firestore;
  final UserService _userService;

  static bool _sessionOpenedLogged = false;

  Future<void> logSessionOpened({String source = 'dashboard'}) async {
    if (_sessionOpenedLogged) return;
    _sessionOpenedLogged = true;
    await _log(action: 'session_opened', source: source);
  }

  Future<void> logLogin({String source = 'auth_flow'}) async {
    await _log(action: 'login', source: source);
  }

  Future<void> logLogout({String source = 'logout_button'}) async {
    await _log(action: 'logout', source: source);
    _sessionOpenedLogged = false;
  }

  Future<void> _log({
    required String action,
    required String source,
  }) async {
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) return;

      final profile = await _resolveProfile(firebaseUser);
      final now = DateTime.now().toLocal();
      final payload = <String, dynamic>{
        'userId': firebaseUser.uid,
        'userDocId': profile.userDocId,
        'name': profile.name,
        'phone': profile.phone,
        'email': profile.email,
        'role': profile.role,
        'action': action,
        'module': _moduleForRole(profile.role),
        'platform': _platformLabel(),
        'userAgent': kIsWeb ? getWebUserAgent() : '',
        'appVersion': null,
        'createdAt': FieldValue.serverTimestamp(),
        'createdDate': _formatDate(now),
        'source': source,
        'isDev': currentEnvironment == AppEnvironment.dev,
      };

      await _firestore.collection('user_session_logs').add(payload);
    } catch (error) {
      debugPrint('Session log failed: $error');
    }
  }

  Future<_SessionProfile> _resolveProfile(User firebaseUser) async {
    final phone = firebaseUser.phoneNumber ?? '';

    final byUid = await _userService.getUserByUid(firebaseUser.uid);
    if (byUid != null) {
      return _SessionProfile.fromMap(
        userDocId: byUid['id']?.toString() ?? firebaseUser.uid,
        data: byUid,
        fallbackPhone: phone,
      );
    }

    if (phone.isNotEmpty) {
      final byPhone = await _userService.getUserByPhone(phone);
      if (byPhone != null) {
        return _SessionProfile.fromMap(
          userDocId: byPhone['id']?.toString() ?? _userService.normalizePhone(phone),
          data: byPhone,
          fallbackPhone: phone,
        );
      }
    }

    return _SessionProfile(
      userDocId: firebaseUser.uid,
      name: firebaseUser.displayName ?? 'Unknown',
      phone: phone,
      email: firebaseUser.email ?? '',
      role: 'unknown',
    );
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.android) return 'android';
    if (platform == TargetPlatform.iOS) return 'ios';
    return 'desktop';
  }

  String _moduleForRole(String role) {
    final normalized = role.toLowerCase();
    if (normalized == 'admin') return 'admin';
    if (normalized == 'staff') return 'staff';
    if (normalized == 'parent') return 'parent';
    return 'unknown';
  }

  String _formatDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }
}

class _SessionProfile {
  const _SessionProfile({
    required this.userDocId,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
  });

  factory _SessionProfile.fromMap({
    required String userDocId,
    required Map<String, dynamic> data,
    required String fallbackPhone,
  }) {
    return _SessionProfile(
      userDocId: userDocId,
      name: data['name']?.toString() ??
          data['displayName']?.toString() ??
          'Unknown',
      phone: data['phoneNumber']?.toString() ??
          data['phone']?.toString() ??
          fallbackPhone,
      email: data['email']?.toString() ?? '',
      role: data['role']?.toString() ?? 'unknown',
    );
  }

  final String userDocId;
  final String name;
  final String phone;
  final String email;
  final String role;
}
