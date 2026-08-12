import 'package:core_contracts/core_contracts.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/auth_failures.dart';
import '../domain/user_account.dart';
import '../domain/user_admin_repository.dart';
import 'firebase_failure_mapper.dart';
import 'user_account_mapper.dart';

/// See _AuthCallables in firebase_auth_repository.dart for why these are
/// named `authFns-<name>`.
abstract final class _AdminCallables {
  static const createUser = 'authFns-createUser';
  static const setUserRole = 'authFns-setUserRole';
  static const setUserStatus = 'authFns-setUserStatus';
  static const resetUserPassword = 'authFns-resetUserPassword';
}

class UserAdminFunctionsRepository implements UserAdminRepository {
  UserAdminFunctionsRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _firestore = firestore,
       _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<Result<List<UserAccount>>> observeUsers() {
    return _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          try {
            return Result.ok(
              snapshot.docs
                  .map(UserAccountMapper.fromSnapshot)
                  .toList(growable: false),
            );
          } on StateError catch (e) {
            return Result.failure(UnknownAuthFailure(e.message));
          }
        });
  }

  @override
  Future<Result<CreateUserResult>> createUser({
    required String email,
    required String displayName,
    required UserRole role,
  }) async {
    try {
      final response = await _functions
          .httpsCallable(_AdminCallables.createUser)
          .call<Map<String, dynamic>>({
            'email': email,
            'displayName': displayName,
            'role': role.claimValue,
          });
      final data = response.data;
      return Result.ok(
        CreateUserResult(
          uid: data['uid'] as String,
          temporaryPassword: data['temporaryPassword'] as String,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<Result<void>> setUserRole({
    required String uid,
    required UserRole role,
  }) async {
    try {
      await _functions.httpsCallable(_AdminCallables.setUserRole).call<void>({
        'uid': uid,
        'role': role.claimValue,
      });
      return const Result.ok(null);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<Result<void>> setUserStatus({
    required String uid,
    required AccountStatus status,
  }) async {
    try {
      await _functions.httpsCallable(_AdminCallables.setUserStatus).call<void>({
        'uid': uid,
        'status': status.claimValue,
      });
      return const Result.ok(null);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<Result<ResetPasswordResult>> resetUserPassword(String uid) async {
    try {
      final response = await _functions
          .httpsCallable(_AdminCallables.resetUserPassword)
          .call<Map<String, dynamic>>({'uid': uid});
      return Result.ok(
        ResetPasswordResult(
          temporaryPassword: response.data['temporaryPassword'] as String,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromFunctionsException(e));
    }
  }
}
