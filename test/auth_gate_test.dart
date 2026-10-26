// AuthGate / session-user state:
// - AuthGate never writes a provider while building ("Tried to modify a
//   provider while the widget tree was building" when opened from the
//   public site's Login at /app). It derives its view from authStateProvider
//   and userLoaderProvider via resolveAuthGateView.
// - authSessionSyncProvider keeps currentUserProvider in step with the
//   signed-in account outside any build: loaded user on sign-in, the new
//   account's user on an account change (no stale user), null on sign-out,
//   on a missing app user and on a load error; nothing while loading.
// - userLoaderProvider follows authStateProvider (reloads per account).
// - Dev-style explicit sign-in (currentUserProvider set without a Firebase
//   account) is not overridden; logout's own clearing still works.
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
import 'package:montessori_app/modules/auth/ui/splash_screen.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';

AppUser _user(String id, String role) => AppUser(id: id, phone: '90000$id', role: role, isActive: true, name: 'User $id');
User _firebaseUser(String uid) => MockUser(uid: uid, phoneNumber: '+9190000$uid');

void main() {
  group('resolveAuthGateView (AuthGate routing)', () {
    AsyncValue<AppUser?> never() => throw StateError('the user loader must not be read');
    final signedIn = AsyncValue<User?>.data(_firebaseUser('1'));

    test('signed out -> login, without reading the user loader', () {
      expect(resolveAuthGateView(const AsyncValue.data(null), never), AuthGateView.login);
    });

    test('auth loading -> splash; auth error -> login (loader not read)', () {
      expect(resolveAuthGateView(const AsyncValue.loading(), never), AuthGateView.splash);
      expect(resolveAuthGateView(AsyncValue.error(Exception('x'), StackTrace.empty), never), AuthGateView.login);
    });

    test('signed in: loading -> splash, no app user -> login, load error -> login', () {
      expect(resolveAuthGateView(signedIn, () => const AsyncValue.loading()), AuthGateView.splash);
      expect(resolveAuthGateView(signedIn, () => const AsyncValue.data(null)), AuthGateView.login);
      expect(resolveAuthGateView(signedIn, () => AsyncValue.error(Exception('x'), StackTrace.empty)), AuthGateView.login);
    });

    test('admin and staff -> DashboardScreen; every other role -> ParentDashboard', () {
      AuthGateView forRole(String role) => resolveAuthGateView(signedIn, () => AsyncValue.data(_user('1', role)));
      expect(forRole('admin'), AuthGateView.staffDashboard);
      expect(forRole('staff'), AuthGateView.staffDashboard);
      expect(forRole('parent'), AuthGateView.parentDashboard);
      expect(forRole('user'), AuthGateView.parentDashboard);
      expect(forRole('teacher'), AuthGateView.parentDashboard, reason: 'unchanged: only admin/staff get the staff dashboard');
    });
  });

  group('authSessionSyncProvider', () {
    late StreamController<User?> auth;
    late Map<String, AppUser?> profiles;
    late Set<String> failing;
    late ProviderContainer container;

    setUp(() {
      auth = StreamController<User?>.broadcast();
      profiles = {'a1': _user('a1', 'admin'), 'p1': _user('p1', 'parent')};
      failing = {};
      container = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => auth.stream),
        // Same dependency as the real loader (watches authStateProvider), with
        // profiles instead of Firestore.
        userLoaderProvider.overrideWith((ref) async {
          final user = await ref.watch(authStateProvider.future);
          if (user == null) return null;
          if (failing.contains(user.uid)) throw StateError('lookup failed');
          return profiles[user.uid];
        }),
      ]);
      container.read(authSessionSyncProvider);
      addTearDown(container.dispose);
      addTearDown(auth.close);
    });

    Future<void> emit(User? user) async {
      auth.add(user);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    AppUser? current() => container.read(currentUserProvider);

    test('nothing is written on creation; the loaded user is applied on sign-in', () async {
      expect(current(), isNull);
      await emit(_firebaseUser('a1'));
      expect(current()?.id, 'a1');
      expect(current()?.role, 'admin');
    });

    test('an account change replaces the user (no stale profile); sign-out clears it', () async {
      await emit(_firebaseUser('a1'));
      expect(current()?.id, 'a1');
      await emit(_firebaseUser('p1'));
      expect(current()?.id, 'p1');
      expect(current()?.role, 'parent');
      await emit(null);
      expect(current(), isNull);
    });

    test('no app user or a failed load clears a previous user', () async {
      await emit(_firebaseUser('a1'));
      await emit(_firebaseUser('unknown'));
      expect(current(), isNull, reason: 'no profile');
      await emit(_firebaseUser('a1'));
      failing.add('p1');
      await emit(_firebaseUser('p1'));
      expect(current(), isNull, reason: 'load error');
    });

    test('an explicit sign-in (dev login) is kept until the Firebase account changes', () async {
      await emit(null);
      container.read(currentUserProvider.notifier).state = _user('dev', 'staff');
      await Future<void>.delayed(Duration.zero);
      expect(current()?.id, 'dev');
      await emit(_firebaseUser('p1'));
      expect(current()?.id, 'p1');
    });

    test('logout: its own clearing and invalidation still leave no user', () async {
      await emit(_firebaseUser('a1'));
      container.read(currentUserProvider.notifier).state = null; // as AuthService.logout does
      container.invalidate(currentUserProvider);
      await emit(null); // FirebaseAuth.signOut
      expect(current(), isNull);
    });
  });

  test('the real userLoaderProvider follows authStateProvider', () async {
    final auth = StreamController<User?>.broadcast();
    final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => auth.stream)]);
    addTearDown(container.dispose);
    addTearDown(auth.close);
    final states = <AsyncValue<AppUser?>>[];
    container.listen(userLoaderProvider, (_, next) => states.add(next), fireImmediately: true);

    auth.add(null);
    await container.read(userLoaderProvider.future);
    expect(container.read(userLoaderProvider).value, isNull, reason: 'signed out: no lookup');

    // Signing in re-runs the loader (before this change it read
    // FirebaseAuth.currentUser once and kept the first result).
    final settledSignedOut = states.length;
    auth.add(_firebaseUser('a1'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final after = states.sublist(settledSignedOut);
    expect(after.first.isLoading, isTrue, reason: 'reloading for the new account');
    expect(after.last.isLoading, isFalse, reason: 'settled again for the new account');
  });

  group('AuthGate widget', () {
    testWidgets('signed out, with a previous user that something watches: login, no build-time mutation, user cleared', (tester) async {
      final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream.value(null))]);
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).state = _user('a1', 'admin');
      final seen = <AppUser?>[];
      container.listen(currentUserProvider, (_, next) => seen.add(next));

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: AuthGate())));
      expect(tester.takeException(), isNull, reason: 'first build writes no provider');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(container.read(currentUserProvider), isNull, reason: 'cleared by the sync, after the build');
      expect(seen, [null]);
    });

    testWidgets('auth still loading -> SplashScreen; then signed out -> LoginScreen', (tester) async {
      final auth = StreamController<User?>();
      addTearDown(auth.close);
      await tester.pumpWidget(ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => auth.stream)],
        child: const MaterialApp(home: AuthGate()),
      ));
      expect(find.byType(SplashScreen), findsOneWidget);
      auth.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed in while the profile loads -> SplashScreen; no app user -> LoginScreen', (tester) async {
      final profile = Completer<AppUser?>();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream.value(_firebaseUser('x'))),
          userLoaderProvider.overrideWith((ref) => profile.future),
        ],
        child: const MaterialApp(home: AuthGate()),
      ));
      await tester.pump();
      expect(find.byType(SplashScreen), findsOneWidget);
      profile.complete(null);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // A session user with no Firebase account now makes the public header
  // show Dashboard/Logout instead of Login (test/public_account_controls_test
  // .dart), so this opens /app directly, as Login does.
  testWidgets('public website -> /app with a previous session user: no exception, login shown', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream.value(null))]);
    addTearDown(container.dispose);
    container.read(currentUserProvider.notifier).state = _user('p1', 'parent');
    container.listen(currentUserProvider, (_, _) {});

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MontessoriApp()));
    await tester.pumpAndSettle();
    expect(find.byType(PublicHomePage), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/app');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AuthGate), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(container.read(currentUserProvider), isNull);
  });
}
