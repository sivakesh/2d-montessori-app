import 'package:flutter/material.dart';

import '../domain/auth_session.dart';
import 'identity_scope.dart';
import 'screens/admin_shell.dart';
import 'screens/auth_error_screen.dart';
import 'screens/forced_password_change_screen.dart';
import 'screens/login_screen.dart';
import 'screens/suspended_account_screen.dart';
import 'screens/unprovisioned_account_screen.dart';

/// The admin app's single route-protection point (see the milestone
/// requirement "Route protection for the Admin portal"). Every
/// [AuthState] the domain layer can produce has an exhaustive `switch`
/// arm here — a new state added to `AuthState` without a matching arm is
/// a compile error, not a silently-unprotected screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = IdentityScope.of(context);
    final state = scope.controller.state;

    return switch (state) {
      AuthStateUnknown() => const _LoadingScreen(),
      AuthStateSignedOut() => const LoginScreen(),
      AuthStateError(:final failure) => AuthErrorScreen(
        message: failure.message,
      ),
      AuthStateUnprovisioned(:final email) => UnprovisionedAccountScreen(
        email: email,
      ),
      AuthStateSuspended() => const SuspendedAccountScreen(),
      AuthStateSignedIn(:final session) => _routeSignedIn(session),
    };
  }

  Widget _routeSignedIn(AuthSession session) {
    if (session.mustChangePassword) {
      return const ForcedPasswordChangeScreen();
    }
    return AdminShell(session: session);
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
