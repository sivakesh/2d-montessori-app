import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/models/app_user.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/providers/auth_state_provider.dart';
import '../../auth/providers/user_loader_provider.dart';
import '../public_routes.dart';
import '../public_strings.dart';
import '../public_website_theme.dart';

/// The top bar's text size and colour, for the controls inside it (the
/// language switch and the login controls). Without one, the site's own
/// (13 px, forest green).
class PublicUtilityBarTheme extends InheritedWidget {
  const PublicUtilityBarTheme({super.key, this.fontSize = standardFontSize, this.color, required super.child});

  static const standardFontSize = 13.0;

  final double fontSize;

  /// The login and logout text and icons; null: the site's own.
  final Color? color;

  static PublicUtilityBarTheme? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PublicUtilityBarTheme>();

  @override
  bool updateShouldNotify(PublicUtilityBarTheme old) => old.fontSize != fontSize || old.color != color;
}

/// What the public site's account controls show.
enum PublicAccountStatus {
  /// Still finding out (auth or profile loading): show nothing rather than
  /// a control that may be wrong a moment later.
  loading,

  /// Not signed in: show Login.
  signedOut,

  /// Signed in with a usable profile: show Dashboard and Logout.
  signedIn,

  /// Signed in, but there is no usable profile (none found, it failed to
  /// load, the account is inactive, or the role isn't one the app routes):
  /// show Logout only, never a dashboard.
  signedInWithoutDashboard,
}

/// The visitor's session as the public site sees it, derived from the
/// existing auth providers without writing to any of them.
class PublicAccountState {
  const PublicAccountState(this.status, {this.user, this.dashboardRoute});

  final PublicAccountStatus status;
  final AppUser? user;

  /// Where Dashboard goes: the app's existing role routing, either
  /// `/dashboard` (RoleBasedHome, for a session already in
  /// currentUserProvider — the route the login and OTP screens use) or
  /// `/app` (AuthGate, for a Firebase session whose profile isn't in
  /// currentUserProvider yet; AuthGate syncs it and routes by role).
  final String? dashboardRoute;
}

/// Roles the app's role routing sends to a dashboard (admin/staff ->
/// DashboardScreen, parent -> ParentDashboard).
const _routedRoles = {'admin', 'staff', 'parent'};

PublicAccountState _forUser(AppUser user, String route) {
  final role = user.role.toLowerCase();
  if (!user.isActive || !_routedRoles.contains(role)) {
    return PublicAccountState(PublicAccountStatus.signedInWithoutDashboard, user: user);
  }
  return PublicAccountState(PublicAccountStatus.signedIn, user: user, dashboardRoute: route);
}

/// The session for the public header, menu and footer. It reads:
/// - [currentUserProvider] first: the session user set by the existing
///   login/OTP flows (and by AuthGate's session sync);
/// - otherwise [authStateProvider] and, when a Firebase user is signed in,
///   [userLoaderProvider] (the same profile lookup AuthGate uses).
///
/// It deliberately does not create AuthGate's session-sync provider: that
/// sync would replace a dev-login session (no Firebase account) with
/// "signed out" as soon as it first loaded.
final publicAccountStateProvider = Provider<PublicAccountState>((ref) {
  final sessionUser = ref.watch(currentUserProvider);
  if (sessionUser != null) return _forUser(sessionUser, '/dashboard');
  return ref.watch(authStateProvider).when(
        loading: () => const PublicAccountState(PublicAccountStatus.loading),
        // Same as AuthGate: an auth error means "not signed in".
        error: (_, _) => const PublicAccountState(PublicAccountStatus.signedOut),
        data: (firebaseUser) {
          if (firebaseUser == null) return const PublicAccountState(PublicAccountStatus.signedOut);
          return ref.watch(userLoaderProvider).when(
                loading: () => const PublicAccountState(PublicAccountStatus.loading),
                error: (_, _) => const PublicAccountState(PublicAccountStatus.signedInWithoutDashboard),
                data: (user) => user == null
                    ? const PublicAccountState(PublicAccountStatus.signedInWithoutDashboard)
                    : _forUser(user, PublicRoutes.management),
              );
        },
      );
});

/// Where the controls sit, which sets their look.
enum PublicAccountControlsStyle { utilityBar, menu, footer }

/// Login when signed out; Dashboard and Logout when signed in (Logout only
/// if there is no dashboard to offer); nothing while the session is still
/// loading. Logout uses the existing [authServiceProvider] logout (session
/// log, Firebase sign-out, session user cleared) and then returns to the
/// public homepage.
class PublicAccountControls extends ConsumerWidget {
  const PublicAccountControls({super.key, required this.style});

  final PublicAccountControlsStyle style;

  static const _keys = {
    PublicAccountControlsStyle.utilityBar: ('public-management-login', 'public-dashboard', 'public-logout'),
    PublicAccountControlsStyle.menu: ('public-management-login', 'public-dashboard', 'public-logout'),
    PublicAccountControlsStyle.footer: ('public-footer-management-login', 'public-footer-dashboard', 'public-footer-logout'),
  };

  /// The drawer stays open until the logout finishes (closing it first
  /// would dispose this widget, and its `ref`, mid-logout); returning home
  /// with a fresh stack then removes it.
  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    await ref.read(authServiceProvider).logout(ref, context);
    navigator.pushNamedAndRemoveUntil(PublicRoutes.home, (route) => false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = PublicStrings.of(ref.watch(publicLanguageProvider));
    final account = ref.watch(publicAccountStateProvider);
    final (loginKey, dashboardKey, logoutKey) = _keys[style]!;

    Widget button({required Key key, required IconData icon, required String label, required VoidCallback onPressed}) {
      switch (style) {
        case PublicAccountControlsStyle.utilityBar:
          final bar = PublicUtilityBarTheme.of(context);
          final size = bar?.fontSize ?? PublicUtilityBarTheme.standardFontSize;
          return TextButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon, size: size + 2),
            label: Text(label, style: TextStyle(fontSize: size, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: bar?.color ?? PublicColors.forest, visualDensity: VisualDensity.compact),
          );
        case PublicAccountControlsStyle.menu:
          return OutlinedButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: PublicColors.forest,
              side: const BorderSide(color: PublicColors.line),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        case PublicAccountControlsStyle.footer:
          return TextButton.icon(
            key: key,
            onPressed: onPressed,
            icon: Icon(icon, size: 16, color: PublicColors.goldLight),
            label: Text(label, style: const TextStyle(color: PublicColors.goldLight)),
          );
      }
    }

    final controls = switch (account.status) {
      PublicAccountStatus.loading => const <Widget>[],
      PublicAccountStatus.signedOut => [
          button(
            key: Key(loginKey),
            icon: Icons.lock_outline,
            label: strings.login,
            onPressed: () => PublicRoutes.openManagement(context),
          ),
        ],
      PublicAccountStatus.signedIn || PublicAccountStatus.signedInWithoutDashboard => [
          if (account.dashboardRoute case final route?)
            button(
              key: Key(dashboardKey),
              icon: Icons.dashboard_outlined,
              label: strings.dashboard,
              onPressed: () => Navigator.of(context).pushNamed(route),
            ),
          button(key: Key(logoutKey), icon: Icons.logout_rounded, label: strings.logout, onPressed: () => _logout(context, ref)),
        ],
    };
    if (controls.isEmpty) return const SizedBox.shrink(key: Key('public-account-loading'));
    return Wrap(spacing: style == PublicAccountControlsStyle.menu ? 12 : 4, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: controls);
  }
}
