import 'dart:async';

import 'package:core_contracts/core_contracts.dart';
import 'package:feature_identity/feature_identity.dart';

/// Test double for [AuthRepository]. Every method's return value is
/// configurable via the corresponding `next*` field so tests can force
/// success/failure paths without touching Firebase.
class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthState>.broadcast();

  Result<void> nextSignInResult = const Result.ok(null);
  Result<void> nextSignOutResult = const Result.ok(null);
  Result<void> nextSendPasswordResetResult = const Result.ok(null);
  Result<void> nextConfirmPasswordResetResult = const Result.ok(null);
  Result<void> nextChangeOwnPasswordResult = const Result.ok(null);
  Result<void> nextCompleteFirstLoginResult = const Result.ok(null);
  Result<void> nextRefreshClaimsResult = const Result.ok(null);

  ({String email, String password})? lastSignIn;
  String? lastPasswordResetEmail;
  ({String oobCode, String newPassword})? lastConfirmPasswordReset;
  String? lastChangeOwnPassword;
  int completeFirstLoginCallCount = 0;
  int signOutCallCount = 0;

  void emit(AuthState state) => _controller.add(state);

  @override
  Stream<AuthState> observeAuthState() => _controller.stream;

  @override
  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    lastSignIn = (email: email, password: password);
    return nextSignInResult;
  }

  @override
  Future<Result<void>> signOut() async {
    signOutCallCount++;
    return nextSignOutResult;
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    lastPasswordResetEmail = email;
    return nextSendPasswordResetResult;
  }

  @override
  Future<Result<void>> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  }) async {
    lastConfirmPasswordReset = (oobCode: oobCode, newPassword: newPassword);
    return nextConfirmPasswordResetResult;
  }

  @override
  Future<Result<void>> changeOwnPassword(String newPassword) async {
    lastChangeOwnPassword = newPassword;
    return nextChangeOwnPasswordResult;
  }

  @override
  Future<Result<void>> completeFirstLogin() async {
    completeFirstLoginCallCount++;
    return nextCompleteFirstLoginResult;
  }

  @override
  Future<Result<void>> refreshOwnClaims() async => nextRefreshClaimsResult;

  Future<void> dispose() => _controller.close();
}
