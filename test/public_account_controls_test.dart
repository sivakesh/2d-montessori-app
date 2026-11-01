// Public website account controls (header utility bar, mobile menu, footer):
// - Signed out: Login (opens /app, the existing AuthGate login).
// - Signed in (parent/staff/admin): Dashboard and Logout.
// - Dashboard uses the existing role routing: /dashboard (RoleBasedHome)
//   for a session user, or /app (AuthGate) for a Firebase session not yet
//   synced. Admin/staff -> DashboardScreen, parent -> ParentDashboard.
// - Logout uses the existing AuthService.logout and returns to the public
//   homepage with a fresh stack.
// - The controls follow sign-in/sign-out without a refresh; while auth or
//   the profile is loading nothing is shown; with no usable profile (none,
//   failed, inactive, unknown role) only Logout is offered.
// - Visiting the public site never clears a dev-login session.
//
// The real dashboards create Firebase services when mounted, so the
// /dashboard and /app test routes render the existing routing's *decision*
// (RoleBasedHome.build / resolveAuthGateView) instead of mounting them —
// the same approach as test/prod03_role_navigation_test.dart.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/services/auth_interface.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_session_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/providers/user_loader_provider.dart';
import 'package:montessori_app/modules/auth/ui/role_based_home.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_section_page.dart';

AppUser _user(String role, {bool active = true}) => AppUser(id: 'u-$role', phone: '9000000$role', role: role, isActive: active, name: 'Test $role');

/// Stands in for the app's AuthService: logout does what the real one does
/// to app state (session user cleared, Firebase signed out).
class _FakeAuthService implements AuthService {
  _FakeAuthService(this.onSignOut);

  final void Function() onSignOut;
  int logouts = 0;

  @override
  Future<AppUser?> signIn() async => null;

  @override
  Future<void> signOut() async => onSignOut();

  @override
  Future<void> logout(WidgetRef ref, BuildContext context) async {
    logouts++;
    onSignOut();
    ref.read(currentUserProvider.notifier).state = null;
    ref.invalidate(currentUserProvider);
  }
}

const _desktop = Size(1400, 1000);
const _mobile = Size(375, 800);

void main() {
  late StreamController<User?> auth;

  /// The latest auth state: like FirebaseAuth.authStateChanges(), every new
  /// listener first receives it (a bare broadcast stream would drop events
  /// sent before the provider was first read).
  User? currentAuth;
  late Completer<AppUser?>? profile;
  late AppUser? Function()? profileFor;
  late _FakeAuthService authService;

  /// Whether the auth state is known yet (false models "still loading").
  var initialAuthSent = false;
  late ProviderContainer container;

  setUp(() {
    initialAuthSent = false;
    auth = StreamController<User?>.broadcast();
    profile = null;
    profileFor = null;
    currentAuth = null;
    auth.stream.listen((user) => currentAuth = user);
    authService = _FakeAuthService(() => auth.add(null));
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) async* {
        if (initialAuthSent) yield currentAuth;
        yield* auth.stream;
      }),
      userLoaderProvider.overrideWith((ref) async {
        final user = await ref.watch(authStateProvider.future);
        if (user == null) return null;
        if (profile != null) return profile!.future;
        return profileFor?.call();
      }),
      authServiceProvider.overrideWithValue(authService),
    ]);
    addTearDown(container.dispose);
    addTearDown(auth.close);
  });

  Future<void> pumpSite(WidgetTester tester, {Size size = _desktop, User? firebaseUser, bool emitAuth = true, bool settle = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: const PublicHomePage(),
        routes: {
          PublicRoutes.programs: (_) => const PublicSectionPage(route: PublicRoutes.programs),
          // The existing role routing's decision, without mounting dashboards.
          '/dashboard': (_) => Consumer(
                builder: (context, ref, _) => Scaffold(body: Text('RoleBasedHome -> ${const RoleBasedHome().build(context, ref).runtimeType}', key: const Key('destination'))),
              ),
          PublicRoutes.management: (_) => Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: Text('AuthGate -> ${resolveAuthGateView(ref.watch(authStateProvider), () => ref.watch(userLoaderProvider)).name}', key: const Key('destination')),
                ),
              ),
        },
      ),
    ));
    if (emitAuth) {
      initialAuthSent = true;
      auth.add(firebaseUser);
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(Key(k));
  String destination(WidgetTester tester) => tester.widget<Text>(key('destination')).data!;

  void expectSignedOut() {
    expect(key('public-management-login'), findsOneWidget, reason: 'header Login');
    expect(key('public-footer-management-login'), findsOneWidget, reason: 'footer Login');
    for (final k in ['public-dashboard', 'public-logout', 'public-footer-dashboard', 'public-footer-logout']) {
      expect(key(k), findsNothing, reason: k);
    }
  }

  void expectSignedIn({bool dashboard = true}) {
    expect(key('public-management-login'), findsNothing);
    expect(key('public-footer-management-login'), findsNothing);
    expect(key('public-dashboard'), dashboard ? findsOneWidget : findsNothing);
    expect(key('public-footer-dashboard'), dashboard ? findsOneWidget : findsNothing);
    expect(key('public-logout'), findsOneWidget);
    expect(key('public-footer-logout'), findsOneWidget);
  }

  testWidgets('1. signed-out visitor sees Login (header and footer), which opens /app', (tester) async {
    await pumpSite(tester);
    expectSignedOut();
    await tapAndSettle(tester, key('public-management-login'));
    expect(destination(tester), 'AuthGate -> login');
  });

  for (final role in ['parent', 'staff', 'admin']) {
    testWidgets('2-4. signed-in $role sees Dashboard and Logout (header, footer, mobile menu)', (tester) async {
      container.read(currentUserProvider.notifier).state = _user(role);
      await pumpSite(tester);
      expectSignedIn();

      await pumpSite(tester, size: _mobile);
      expect(key('public-dashboard'), findsNothing, reason: 'mobile header keeps the menu button only');
      await tapAndSettle(tester, key('public-menu-button'));
      expect(find.descendant(of: key('public-menu'), matching: key('public-dashboard')), findsOneWidget);
      expect(find.descendant(of: key('public-menu'), matching: key('public-logout')), findsOneWidget);
      expect(find.descendant(of: key('public-menu'), matching: key('public-management-login')), findsNothing);
    });
  }

  group('5. Dashboard opens the role destination through the existing routing', () {
    for (final (role, expected) in [('admin', 'DashboardScreen'), ('staff', 'DashboardScreen'), ('parent', 'ParentDashboard')]) {
      testWidgets('session $role -> /dashboard -> $expected', (tester) async {
        container.read(currentUserProvider.notifier).state = _user(role);
        await pumpSite(tester);
        await tapAndSettle(tester, key('public-dashboard'));
        expect(destination(tester), 'RoleBasedHome -> $expected');
        // Back returns to the public site.
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pumpAndSettle();
        expect(find.byType(PublicHomePage), findsOneWidget);
      });
    }

    for (final (role, expected) in [('admin', 'staffDashboard'), ('staff', 'staffDashboard'), ('parent', 'parentDashboard')]) {
      testWidgets('Firebase session $role (profile not yet in the session) -> /app -> AuthGate $expected', (tester) async {
        profileFor = () => _user(role);
        await pumpSite(tester, firebaseUser: MockUser(uid: 'uid-$role'));
        expectSignedIn();
        await tapAndSettle(tester, key('public-footer-dashboard'));
        expect(destination(tester), 'AuthGate -> $expected');
      });
    }
  });

  testWidgets('6. Logout uses the AuthService, signs out and returns to the homepage with a fresh stack', (tester) async {
    container.read(currentUserProvider.notifier).state = _user('admin');
    await pumpSite(tester);
    tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(PublicRoutes.programs);
    await tester.pumpAndSettle();
    expect(find.byType(PublicSectionPage), findsOneWidget);

    await tapAndSettle(tester, key('public-logout'));
    expect(authService.logouts, 1);
    expect(container.read(currentUserProvider), isNull);
    expect(find.byType(PublicHomePage), findsOneWidget);
    expect(find.byType(PublicSectionPage), findsNothing);
    expect(tester.state<NavigatorState>(find.byType(Navigator).first).canPop(), isFalse);
    expectSignedOut();
    expect(tester.takeException(), isNull);
  });

  testWidgets('6b. Logout from the mobile menu', (tester) async {
    container.read(currentUserProvider.notifier).state = _user('parent');
    await pumpSite(tester, size: _mobile);
    await tapAndSettle(tester, key('public-menu-button'));
    await tapAndSettle(tester, find.descendant(of: key('public-menu'), matching: key('public-logout')));
    expect(authService.logouts, 1);
    expect(key('public-menu'), findsNothing, reason: 'menu closed');
    expect(find.byType(PublicHomePage), findsOneWidget);
    expect(key('public-footer-management-login'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('7. the controls follow sign-in and sign-out without a refresh', (tester) async {
    profileFor = () => _user('staff');
    await pumpSite(tester);
    expectSignedOut();

    auth.add(MockUser(uid: 'uid-staff')); // phone OTP sign-in
    await tester.pumpAndSettle();
    expectSignedIn();

    auth.add(null); // signed out elsewhere
    await tester.pumpAndSettle();
    expectSignedOut();

    container.read(currentUserProvider.notifier).state = _user('parent'); // dev login
    await tester.pumpAndSettle();
    expectSignedIn();

    container.read(currentUserProvider.notifier).state = null;
    await tester.pumpAndSettle();
    expectSignedOut();
  });

  group('8. loading and missing-profile states are safe', () {
    testWidgets('auth still loading: no Login, Dashboard or Logout', (tester) async {
      await pumpSite(tester, emitAuth: false, settle: false);
      expect(key('public-management-login'), findsNothing);
      expect(key('public-dashboard'), findsNothing);
      expect(key('public-logout'), findsNothing);
      expect(key('public-account-loading'), findsWidgets);
      initialAuthSent = true;
      auth.add(null);
      await tester.pumpAndSettle();
      expectSignedOut();
    });

    testWidgets('profile still loading: nothing; then Dashboard once it loads', (tester) async {
      profile = Completer<AppUser?>();
      await pumpSite(tester, firebaseUser: MockUser(uid: 'uid-x'));
      expect(key('public-management-login'), findsNothing, reason: 'not "signed out" while the profile loads');
      expect(key('public-dashboard'), findsNothing);
      expect(key('public-logout'), findsNothing);
      profile!.complete(_user('parent'));
      await tester.pumpAndSettle();
      expectSignedIn();
    });

    for (final (name, setup) in <(String, void Function())>[
      ('no profile', () => profileFor = () => null),
      ('profile failed to load', () => profileFor = () => throw StateError('lookup failed')),
      ('unknown role', () => profileFor = () => _user('teacher')),
      ('inactive account', () => profileFor = () => _user('admin', active: false)),
    ]) {
      testWidgets('$name: Logout only, never a dashboard', (tester) async {
        setup();
        await pumpSite(tester, firebaseUser: MockUser(uid: 'uid-y'));
        expectSignedIn(dashboard: false);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('session user with an unknown role: Logout only', (tester) async {
      container.read(currentUserProvider.notifier).state = _user('');
      await pumpSite(tester);
      expectSignedIn(dashboard: false);
    });
  });

  testWidgets('visiting the public site never clears a dev-login session (no Firebase account)', (tester) async {
    container.read(currentUserProvider.notifier).state = _user('staff');
    await pumpSite(tester);
    await tester.pumpAndSettle();
    expect(container.read(currentUserProvider)?.role, 'staff');
    expectSignedIn();
  });

  testWidgets('Tamil labels', (tester) async {
    container.read(currentUserProvider.notifier).state = _user('admin');
    await pumpSite(tester);
    await tapAndSettle(tester, find.text('தமிழ்'));
    expect(find.descendant(of: key('public-dashboard'), matching: find.text('டாஷ்போர்டு')), findsOneWidget);
    expect(find.descendant(of: key('public-logout'), matching: find.text('வெளியேறு')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
