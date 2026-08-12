import 'dart:async';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';

class FakeUserAdminRepository implements UserAdminRepository {
  final _usersController =
      StreamController<Result<List<UserAccount>>>.broadcast();

  Result<CreateUserResult> nextCreateUserResult = const Result.failure(
    ValidationFailure('not configured'),
  );
  Result<void> nextSetUserRoleResult = const Result.ok(null);
  Result<void> nextSetUserStatusResult = const Result.ok(null);
  Result<ResetPasswordResult> nextResetUserPasswordResult =
      const Result.failure(ValidationFailure('not configured'));

  ({String email, String displayName, UserRole role})? lastCreateUser;
  ({String uid, UserRole role})? lastSetUserRole;
  ({String uid, AccountStatus status})? lastSetUserStatus;
  String? lastResetUserPasswordUid;

  void emitUsers(Result<List<UserAccount>> result) =>
      _usersController.add(result);

  @override
  Stream<Result<List<UserAccount>>> observeUsers() => _usersController.stream;

  @override
  Future<Result<CreateUserResult>> createUser({
    required String email,
    required String displayName,
    required UserRole role,
  }) async {
    lastCreateUser = (email: email, displayName: displayName, role: role);
    return nextCreateUserResult;
  }

  @override
  Future<Result<void>> setUserRole({
    required String uid,
    required UserRole role,
  }) async {
    lastSetUserRole = (uid: uid, role: role);
    return nextSetUserRoleResult;
  }

  @override
  Future<Result<void>> setUserStatus({
    required String uid,
    required AccountStatus status,
  }) async {
    lastSetUserStatus = (uid: uid, status: status);
    return nextSetUserStatusResult;
  }

  @override
  Future<Result<ResetPasswordResult>> resetUserPassword(String uid) async {
    lastResetUserPasswordUid = uid;
    return nextResetUserPasswordResult;
  }

  Future<void> dispose() => _usersController.close();
}
