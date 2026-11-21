// Dashboard from the public site for a session Firebase restored: the
// profile is already loaded (for the public header) when `/app` opens, so
// after AuthGate's existing session sync exists, the existing profile
// lookup runs once more and the sync sets the session user — the admin,
// staff or parent dashboard then loads without a refresh. A session user
// already set (this tab's login, the dev login) reloads nothing; two clicks
// reload once; signing out and in again is unaffected.
//
// DashboardScreen and ParentDashboard need real Firebase when mounted (see
// test/prod03_role_navigation_test.dart), so `/app` here is a probe that
// does exactly what AuthGate's build does — watches the existing
// authSessionSyncProvider and resolves the view with the existing
// resolveAuthGateView — and shows the decision and the session user.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_session_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/providers/user_loader_provider.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/widgets/public_account_controls.dart';

AppUser _user(String role) => AppUser(id: '9000000001', phone: '9000000001', role: role, isActive: true, name: 'User');

void main() {
  late StreamController<User?> auth;
  late ProviderContainer container;
  late int lookups;
  late String role;

  setUp(() {
    auth = StreamController<User?>.broadcast();
    lookups = 0;
    role = 'staff';
    RestoredSessionDashboard.reloads = 0;
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth.stream),
      // The existing lookup's shape (UserService needs real Firebase): one
      // read per run, counted.
      userLoaderProvider.overrideWith((ref) async {
        final firebaseUser = await ref.watch(authStateProvider.future);
        if (firebaseUser == null) return null;
        lookups++;
        await Future<void>.value();
        return _user(role);
      }),
    ]);
    addTearDown(container.dispose);
    addTearDown(auth.close);
  });

  Future<void> pumpSite(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: const Scaffold(body: PublicAccountControls(style: PublicAccountControlsStyle.utilityBar)),
        routes: {
          // What AuthGate's build does, showing its decision.
          PublicRoutes.management: (_) => Consumer(builder: (context, ref, _) {
                ref.watch(authSessionSyncProvider);
                final view = resolveAuthGateView(ref.watch(authStateProvider), () => ref.watch(userLoaderProvider));
                return Scaffold(body: Text('${view.name} user=${ref.watch(currentUserProvider)?.id ?? 'none'}', key: const Key('gate')));
              }),
          '/dashboard': (_) => Consumer(builder: (context, ref, _) => Scaffold(body: Text('dashboard user=${ref.watch(currentUserProvider)?.id}', key: const Key('dashboard-route')))),
        },
      ),
    ));
  }

  /// Returning to the site: Firebase restores the session; the header loads
  /// the profile and offers Dashboard (to /app).
  Future<void> restoredSession(WidgetTester tester) async {
    await pumpSite(tester);
    auth.add(MockUser(uid: 'u1', phoneNumber: '+919000000001'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('public-dashboard')), findsOneWidget);
    expect(container.read(publicAccountStateProvider).dashboardRoute, PublicRoutes.management);
    expect(container.read(currentUserProvider), isNull, reason: 'the profile is loaded, the session user not yet set');
    expect(lookups, 1);
  }

  String gate(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('gate'))).data!;

  for (final (r, view) in [('staff', 'staffDashboard'), ('admin', 'staffDashboard'), ('parent', 'parentDashboard')]) {
    testWidgets('$r: public site first, then Dashboard → /app: the session user is set and the dashboard loads, without a refresh', (tester) async {
      role = r;
      await restoredSession(tester);
      await tester.tap(find.byKey(const Key('public-dashboard')));
      await tester.pumpAndSettle();
      expect(gate(tester), '$view user=9000000001');
      expect(container.read(currentUserProvider)?.role, r);
      expect(RestoredSessionDashboard.reloads, 1, reason: 'once AuthGate’s session sync existed');
      expect(lookups, 2, reason: 'one more profile read, no more');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('control: opening /app as before (no reload) leaves the session user unset — the reported spinner', (tester) async {
    await restoredSession(tester);
    PublicRoutes.openManagement(tester.element(find.byKey(const Key('public-dashboard'))));
    await tester.pumpAndSettle();
    expect(gate(tester), 'staffDashboard user=none', reason: 'DashboardScreen waits for the session user');
    expect(lookups, 1);
  });

  testWidgets('the reload happens only after AuthGate’s sync exists (never before navigating)', (tester) async {
    await restoredSession(tester);
    openPublicDashboard(tester.element(find.byKey(const Key('public-dashboard'))), PublicRoutes.management);
    expect(lookups, 1, reason: 'nothing reloaded before /app is built');
    expect(container.exists(authSessionSyncProvider), isFalse);
    await tester.pump(); // /app builds: AuthGate's sync is created
    expect(container.exists(authSessionSyncProvider), isTrue);
    await tester.pumpAndSettle();
    expect(lookups, 2);
    expect(container.read(currentUserProvider), isNotNull);
  });

  testWidgets('two quick clicks: one reload, no loop', (tester) async {
    await restoredSession(tester);
    final context = tester.element(find.byKey(const Key('public-dashboard')));
    openPublicDashboard(context, PublicRoutes.management);
    openPublicDashboard(context, PublicRoutes.management);
    await tester.pumpAndSettle();
    expect(RestoredSessionDashboard.reloads, 1);
    expect(lookups, 2);
    // Settled: nothing more happens.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(lookups, 2);
  });

  testWidgets('a session user already set (this tab’s login, or the dev login): /dashboard, nothing reloaded', (tester) async {
    await pumpSite(tester);
    container.read(currentUserProvider.notifier).state = _user('staff');
    auth.add(null); // the dev login has no Firebase account
    await tester.pumpAndSettle();
    expect(container.read(publicAccountStateProvider).dashboardRoute, '/dashboard');
    await tester.tap(find.byKey(const Key('public-dashboard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-route')), findsOneWidget);
    expect(RestoredSessionDashboard.reloads, 0);
    expect(lookups, 0);
    expect(container.read(currentUserProvider)?.id, '9000000001', reason: 'the dev-login session is kept');
  });

  testWidgets('AuthGate never appears (e.g. straight back): no reload', (tester) async {
    await restoredSession(tester);
    RestoredSessionDashboard.reloadProfileOnceAuthGateIsReady(container);
    for (var i = 0; i < RestoredSessionDashboard.maxFrames + 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(RestoredSessionDashboard.reloads, 0);
    expect(lookups, 1);
  });

  testWidgets('signing out and in again afterwards is unaffected (the existing sync handles it)', (tester) async {
    await restoredSession(tester);
    await tester.tap(find.byKey(const Key('public-dashboard')));
    await tester.pumpAndSettle();
    expect(container.read(currentUserProvider), isNotNull);
    auth.add(null); // signed out
    await tester.pumpAndSettle();
    expect(container.read(currentUserProvider), isNull);
    expect(gate(tester), 'login user=none');
    auth.add(MockUser(uid: 'u1', phoneNumber: '+919000000001')); // signed in again
    await tester.pumpAndSettle();
    expect(gate(tester), 'staffDashboard user=9000000001');
    expect(RestoredSessionDashboard.reloads, 1, reason: 'no reload of ours after the first');
  });
}
