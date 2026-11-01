// /dashboard (DashboardRoute):
// - A session user already in currentUserProvider (login/OTP, dev login)
//   goes through RoleBasedHome's existing role routing, unchanged.
// - With no session user — a browser refresh on /#/dashboard, where the
//   public homepage is the root route so nothing has created AuthGate's
//   session sync yet, or a signed-out visitor typing the address — it shows
//   AuthGate (splash while loading, login when signed out), never the Parent
//   dashboard. Once the restored user is synced it switches to RoleBasedHome.
//
// DashboardScreen and ParentDashboard reach for real Firebase singletons
// when mounted (see test/prod03_role_navigation_test.dart), so the
// signed-in cases assert on the type each route decides to show rather than
// mounting it; the signed-out and loading cases mount the real app.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_session_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/providers/user_loader_provider.dart';
import 'package:montessori_app/modules/auth/ui/auth_gate.dart';
import 'package:montessori_app/modules/auth/ui/login_screen.dart';
import 'package:montessori_app/modules/auth/ui/role_based_home.dart';
import 'package:montessori_app/modules/auth/ui/splash_screen.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';

AppUser _user(String id, String role) => AppUser(id: id, phone: '90000$id', role: role, isActive: true, name: 'User $id');
User _firebaseUser(String uid) => MockUser(uid: uid, phoneNumber: '+9190000$uid');

/// What /dashboard decides to show, and what RoleBasedHome would then show.
String _decision(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('decision'))).data!;

Widget _decisionProbe(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          final route = const DashboardRoute().build(context, ref);
          final shown = route is RoleBasedHome ? '${route.runtimeType} -> ${route.build(context, ref).runtimeType}' : '${route.runtimeType}';
          return Text(shown, key: const Key('decision'));
        }),
      ),
    );

void main() {
  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openDashboard(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MontessoriApp()));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/dashboard');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('session user present: RoleBasedHome routing unchanged', () {
    for (final (role, expected) in [('admin', 'DashboardScreen'), ('staff', 'DashboardScreen'), ('parent', 'ParentDashboard')]) {
      testWidgets('$role -> RoleBasedHome -> $expected', (tester) async {
        final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))]);
        addTearDown(container.dispose);
        container.read(currentUserProvider.notifier).state = _user('1', role);
        await tester.pumpWidget(_decisionProbe(container));
        expect(_decision(tester), 'RoleBasedHome -> $expected');
      });
    }

    testWidgets('dev login (session user, no Firebase account) is not replaced by AuthGate', (tester) async {
      final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))]);
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).state = _user('dev', 'staff');
      await tester.pumpWidget(_decisionProbe(container));
      await tester.pumpAndSettle();
      expect(_decision(tester), 'RoleBasedHome -> DashboardScreen');
      expect(container.read(currentUserProvider)?.id, 'dev');
    });
  });

  testWidgets('no session user -> AuthGate, not the Parent dashboard', (tester) async {
    final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))]);
    addTearDown(container.dispose);
    await tester.pumpWidget(_decisionProbe(container));
    expect(_decision(tester), 'AuthGate');
  });

  testWidgets('signed-out visitor at /dashboard: login, never the Parent dashboard', (tester) async {
    desktop(tester);
    final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))]);
    addTearDown(container.dispose);
    await openDashboard(tester, container);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ParentDashboard), findsNothing);
    expect(find.byType(AuthGate), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(container.read(currentUserProvider), isNull);
  });

  testWidgets('refresh while auth is restoring: splash, then login once signed out', (tester) async {
    desktop(tester);
    final auth = StreamController<User?>();
    addTearDown(auth.close);
    final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => auth.stream)]);
    addTearDown(container.dispose);
    await openDashboard(tester, container);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(ParentDashboard), findsNothing);
    auth.add(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('refresh with a Firebase session whose profile is loading: splash; no app user -> login', (tester) async {
    desktop(tester);
    final profile = Completer<AppUser?>();
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream.value(_firebaseUser('x'))),
      userLoaderProvider.overrideWith((ref) => profile.future),
    ]);
    addTearDown(container.dispose);
    await openDashboard(tester, container);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(ParentDashboard), findsNothing);
    profile.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  group('restored session (refresh while signed in)', () {
    for (final (role, expected) in [('admin', 'DashboardScreen'), ('staff', 'DashboardScreen'), ('parent', 'ParentDashboard')]) {
      testWidgets('$role: AuthGate until the profile syncs, then RoleBasedHome -> $expected, with one session write', (tester) async {
        final profile = Completer<AppUser?>();
        final container = ProviderContainer(overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_firebaseUser('r1'))),
          userLoaderProvider.overrideWith((ref) => profile.future),
        ]);
        addTearDown(container.dispose);
        final writes = <AppUser?>[];
        container.listen(currentUserProvider, (_, next) => writes.add(next));
        // While the decision is AuthGate, the real AuthGate would be mounted
        // and create its session sync; this probe doesn't mount it, so it
        // creates the same (single) sync provider itself.
        container.read(authSessionSyncProvider);
        await tester.pumpWidget(_decisionProbe(container));
        await tester.pump();
        expect(_decision(tester), 'AuthGate');

        profile.complete(_user('r1', role));
        await tester.pumpAndSettle();
        expect(_decision(tester), 'RoleBasedHome -> $expected');
        expect(writes.map((u) => u?.id), ['r1'], reason: 'one sync write, no duplicate');
      });
    }
  });
}
