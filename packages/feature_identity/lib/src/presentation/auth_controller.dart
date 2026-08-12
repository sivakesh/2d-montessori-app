import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';

/// Single source of truth for "what is the current session" — every
/// screen that needs to react to sign-in/out, suspension or a role change
/// listens to this via [IdentityScope] rather than talking to
/// [AuthRepository] directly. Actions (sign in, create user, ...) are
/// invoked by the screens themselves through use cases; this controller
/// only mirrors [AuthRepository.observeAuthState].
class AuthController extends ChangeNotifier {
  AuthController(this._repository) {
    _subscription = _repository.observeAuthState().listen((state) {
      _state = state;
      notifyListeners();
    });
  }

  final AuthRepository _repository;
  late final StreamSubscription<AuthState> _subscription;
  AuthState _state = const AuthStateUnknown();

  AuthState get state => _state;

  /// Re-fetches the ID token so a role/status change (this session's own,
  /// after re-authenticating, or observed indirectly) is reflected without
  /// waiting for the natural refresh cycle. Used by the error/retry screens.
  Future<void> refreshClaims() => _repository.refreshOwnClaims();

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
