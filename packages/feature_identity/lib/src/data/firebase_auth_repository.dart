import 'package:core_contracts/core_contracts.dart';
import 'package:firebase_adapters/firebase_adapters.dart';

import '../domain/auth_failures.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';
import 'firebase_failure_mapper.dart';

/// Cloud Functions callable names must match the grouped-export naming
/// Firebase derives from `export * as authFns from './auth'` in
/// functions/src/index.ts — deployed/emulated as `authFns-<name>`.
abstract final class _AuthCallables {
  static const completeFirstLogin = 'authFns-completeFirstLogin';
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  }) : _auth = auth,
       _firestore = firestore,
       _functions = functions;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  @override
  Stream<AuthState> observeAuthState() {
    return _auth.idTokenChanges().asyncMap(_resolveState);
  }

  Future<AuthState> _resolveState(User? user) async {
    if (user == null) return const AuthStateSignedOut();

    try {
      final tokenResult = await user.getIdTokenResult();
      final role = UserRole.fromClaimValue(
        tokenResult.claims?['role'] as String?,
      );
      if (role == null) {
        return AuthStateUnprovisioned(uid: user.uid, email: user.email ?? '');
      }
      final status =
          AccountStatus.fromClaimValue(
            tokenResult.claims?['status'] as String?,
          ) ??
          AccountStatus.suspended;

      final profileSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();
      final profile = profileSnapshot.data();

      final session = AuthSession(
        uid: user.uid,
        email: user.email ?? '',
        displayName:
            (profile?['displayName'] as String?)?.trim().isNotEmpty == true
            ? profile!['displayName'] as String
            : (user.displayName ?? user.email ?? ''),
        photoUrl: profile?['photoUrl'] as String? ?? user.photoURL,
        role: role,
        status: status,
        mustChangePassword: profile?['mustChangePassword'] as bool? ?? true,
      );

      return status == AccountStatus.suspended
          ? AuthStateSuspended(session)
          : AuthStateSignedIn(session);
    } on FirebaseAuthException catch (e) {
      return AuthStateError(FirebaseFailureMapper.fromAuthException(e));
    } on FirebaseException catch (e) {
      return AuthStateError(
        UnknownAuthFailure(e.message ?? 'Failed to load your profile.'),
      );
    }
  }

  @override
  Future<Result<void>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return const Result.ok(null);
    } on FirebaseAuthException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromAuthException(e));
    }
  }

  @override
  Future<Result<void>> signOut() async {
    await _auth.signOut();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return const Result.ok(null);
    } on FirebaseAuthException catch (e) {
      // Do not leak whether an account exists for this email.
      if (e.code == 'user-not-found') return const Result.ok(null);
      return Result.failure(FirebaseFailureMapper.fromAuthException(e));
    }
  }

  @override
  Future<Result<void>> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  }) async {
    try {
      await _auth.confirmPasswordReset(code: oobCode, newPassword: newPassword);
      return const Result.ok(null);
    } on FirebaseAuthException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromAuthException(e));
    }
  }

  @override
  Future<Result<void>> changeOwnPassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) return const Result.failure(InvalidCredentialsFailure());
    try {
      await user.updatePassword(newPassword);
      return const Result.ok(null);
    } on FirebaseAuthException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromAuthException(e));
    }
  }

  @override
  Future<Result<void>> completeFirstLogin() async {
    try {
      await _functions
          .httpsCallable(_AuthCallables.completeFirstLogin)
          .call<void>();
      return const Result.ok(null);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromFunctionsException(e));
    }
  }

  @override
  Future<Result<void>> refreshOwnClaims() async {
    final user = _auth.currentUser;
    if (user == null) return const Result.failure(InvalidCredentialsFailure());
    try {
      await user.getIdTokenResult(true);
      return const Result.ok(null);
    } on FirebaseAuthException catch (e) {
      return Result.failure(FirebaseFailureMapper.fromAuthException(e));
    }
  }
}
