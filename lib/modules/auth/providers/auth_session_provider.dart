import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/user_loader_provider.dart';

/// What AuthGate shows.
enum AuthGateView { splash, login, staffDashboard, parentDashboard }

/// AuthGate's routing, derived purely from the auth and user-loading states
/// (no provider is written): signed out, no app user, or an error -> login;
/// still loading -> splash; admin/staff -> staff dashboard; any other role ->
/// parent dashboard. [loadUser] is only called once signed in, so the user
/// loader isn't watched for signed-out visitors.
AuthGateView resolveAuthGateView(AsyncValue<User?> authState, AsyncValue<AppUser?> Function() loadUser) {
  return authState.when(
    data: (firebaseUser) {
      if (firebaseUser == null) return AuthGateView.login;
      return loadUser().when(
        data: (user) {
          if (user == null) return AuthGateView.login;
          final role = user.role;
          return role == 'admin' || role == 'staff' ? AuthGateView.staffDashboard : AuthGateView.parentDashboard;
        },
        loading: () => AuthGateView.splash,
        error: (_, _) => AuthGateView.login,
      );
    },
    loading: () => AuthGateView.splash,
    error: (_, _) => AuthGateView.login,
  );
}

/// Keeps [currentUserProvider] in step with the signed-in account, outside
/// any widget build: whenever [userLoaderProvider] (which reloads on every
/// Firebase sign-in/sign-out) settles, the session user becomes the loaded
/// user — or null when signed out, when no app user exists, or when loading
/// failed, so a previous account is never left behind. Nothing is written
/// while it is still loading, and nothing on creation (no fireImmediately):
/// changes are applied when the loader's future completes, which never
/// happens during a build.
///
/// Explicit sign-in flows still set [currentUserProvider] themselves (the
/// dev login has no Firebase account, so the loader never overrides it), and
/// logout still clears it.
///
/// Watched by AuthGate, and kept alive for the app's lifetime once created,
/// so later account changes are applied even when AuthGate isn't shown.
final authSessionSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<AppUser?>>(userLoaderProvider, (previous, next) {
    if (next.isLoading) return;
    ref.read(currentUserProvider.notifier).state = next.hasError ? null : next.value;
  });
});
