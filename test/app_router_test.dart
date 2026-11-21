// The app's Router (lib/core/navigation/app_router.dart): every address
// parsed; the public website's pages as browser history entries (Back goes
// through them in reverse, Forward restores them); sections (same page: the
// address only; another page: a new entry, restored by Back and Forward);
// direct addresses, refresh and unknown routes; and the management app
// unchanged inside it (its named routes and arguments, the address following
// its routes, and the browser's Back closing dialogs and screens first,
// through their PopScope).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/navigation/app_router.dart';
import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/ui/auth_gate.dart';
import 'package:montessori_app/modules/auth/ui/login_screen.dart';
import 'package:montessori_app/modules/auth/ui/otp_screen.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/ui/public_custom_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_event_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_section_page.dart';

/// The browser's history as the web engine keeps it for a Router (one entry
/// per reported route; `replace` changes the current one), and its Back and
/// Forward buttons (the engine sends the entry's address and state back).
class _Browser {
  final entries = <({String uri, Object? state})>[];
  var index = -1;
  final reports = <({String uri, bool replace})>[];

  void report(MethodCall call) {
    if (call.method != 'routeInformationUpdated') return;
    final args = call.arguments as Map;
    final uri = (args['uri'] ?? args['location']).toString();
    final replace = args['replace'] == true;
    reports.add((uri: uri, replace: replace));
    if (replace && index >= 0) {
      entries[index] = (uri: uri, state: args['state']);
    } else {
      entries.removeRange(index + 1, entries.length);
      entries.add((uri: uri, state: args['state']));
      index = entries.length - 1;
    }
  }

  String get url => entries[index].uri;
  List<String> get urls => [for (final e in entries) e.uri];

  Future<void> _go(WidgetTester tester, int to) async {
    index = to;
    final message = const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': entries[to].uri, 'state': entries[to].state}));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) => _go(tester, index - 1);
  Future<void> forward(WidgetTester tester) => _go(tester, index + 1);
}

void main() {
  late _Browser browser;

  Future<void> start(WidgetTester tester, {String at = '/'}) async {
    browser = _Browser();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.defaultRouteNameTestValue = at;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
      browser.report(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, null));
    await tester.pumpWidget(ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  String? title(WidgetTester tester) {
    final t = find.byKey(const Key('public-section-title'));
    return t.evaluate().isEmpty ? null : tester.widget<Text>(t).data;
  }

  /// The current page's route name (the Router's top page).
  String? page(WidgetTester tester) => ModalRoute.of(tester.element(find.byType(Scaffold).last))?.settings.name;

  BuildContext pageContext(WidgetTester tester) => tester.element(find.byType(Scaffold).last);

  group('addresses', () {
    test('every supported address', () {
      AppLocation p(String s) => AppLocation.parse(s);
      expect(p('/').name, '/');
      expect(p('').name, '/');
      for (final r in PublicRoutes.sections) {
        expect(p(r).name, r);
        expect(p(r).management, isFalse);
      }
      expect(p('/pages/Open-Day').name, '/pages/open-day');
      expect(p('/pages/open-day#faq').name, '/pages/open-day#faq');
      expect(p('/pages/').name, '/pages/', reason: 'the page itself says “page not found”');
      expect(p('/events/Ev1abc').name, '/events/Ev1abc', reason: 'event ids keep their case');
      expect(p('/announcements/n1').name, '/announcements/n1');
      for (final r in ['/app', '/login', '/otp', '/dashboard', '/admin_dashboard', '/admin_session_logs', '/admin_profile_form']) {
        expect(p(r).management, isTrue, reason: r);
        expect(p(r).name, r);
      }
      expect(p('/teacher-training#enquire').anchor, 'enquire');
      expect(p('/teacher-training#/app').anchor, isNull, reason: 'a route is not a section');
      final unknown = p('/no-such-page');
      expect(unknown.name, '/', reason: 'Home, as before');
      expect(unknown.reported, '/no-such-page', reason: 'the address opened is kept');
      expect(p('/pages/Open-Day').reported, '/pages/Open-Day', reason: 'never rewritten');
      expect(PublicRoutes.legacyHashRoute('/', '#/pages/about'), '/pages/about', reason: 'legacy #/ links (URL strategy)');
    });

    test('the parser keeps each history entry’s id', () async {
      const parser = AppRouteParser();
      final location = await parser.parseRouteInformation(RouteInformation(uri: Uri.parse('/admissions#enquire'), state: {AppRouteParser.stateKey: 'abc-1'}));
      expect(location.entry, 'abc-1');
      final restored = parser.restoreRouteInformation(location);
      expect(restored.uri.toString(), '/admissions#enquire');
      expect(restored.state, {AppRouteParser.stateKey: 'abc-1'});
    });
  });

  group('public website history', () {
    testWidgets('menu navigation: each page an entry; Back in reverse; Forward restores', (tester) async {
      await start(tester);
      expect(browser.urls, ['/']);
      for (final r in [PublicRoutes.admissions, PublicRoutes.teacherTraining, PublicRoutes.programs]) {
        await tap(tester, 'public-nav-$r');
      }
      expect(browser.urls, ['/', '/admissions', '/teacher-training', '/programs']);
      expect(browser.reports.where((r) => !r.replace).length, 3, reason: 'a new entry per page');

      await browser.back(tester);
      expect(title(tester), 'Teacher Training');
      await browser.back(tester);
      expect(title(tester), 'Admissions');
      await browser.back(tester);
      expect(find.byType(PublicHomePage), findsOneWidget);
      expect(browser.urls, ['/', '/admissions', '/teacher-training', '/programs'], reason: 'Back adds no entry');

      await browser.forward(tester);
      expect(title(tester), 'Admissions');
      await browser.forward(tester);
      await browser.forward(tester);
      expect(title(tester), 'Programs');
      expect(page(tester), '/programs');
    });

    testWidgets('footer, buttons and card links are entries too; a new link after Back replaces the forward entries', (tester) async {
      await start(tester);
      await tap(tester, 'public-footer-/contact');
      await tap(tester, 'public-back-home');
      await tap(tester, 'public-pathway-educators');
      expect(title(tester), 'Teacher Training');
      expect(browser.urls, ['/', '/contact', '/', '/teacher-training']);
      await browser.back(tester);
      await browser.back(tester);
      expect(title(tester), 'Contact');
      PublicRoutes.open(pageContext(tester), PublicRoutes.programs);
      await tester.pumpAndSettle();
      expect(browser.urls, ['/', '/contact', '/programs'], reason: 'as a browser does');
    });

    testWidgets('events and announcements open as entries; their Back works', (tester) async {
      await start(tester);
      PublicRoutes.open(pageContext(tester), PublicRoutes.event('Ev1abc'), stack: true);
      await tester.pumpAndSettle();
      expect(find.byType(PublicEventPage), findsOneWidget);
      expect(page(tester), '/events/Ev1abc');
      expect(browser.url, '/events/Ev1abc');
      await browser.back(tester);
      expect(find.byType(PublicHomePage), findsOneWidget);
      PublicRoutes.open(pageContext(tester), PublicRoutes.announcement('n1'), stack: true);
      await tester.pumpAndSettle();
      expect(browser.url, '/announcements/n1');
      await browser.back(tester);
      await browser.forward(tester);
      expect(page(tester), '/announcements/n1');
    });

    testWidgets('a section on this page: the address shows it, no new entry; on another page: a new entry, restored by Back and Forward', (tester) async {
      await start(tester);
      await tap(tester, 'public-nav-/admissions');
      final entries = browser.entries.length;
      PublicRoutes.open(pageContext(tester), '#enquire');
      await tester.pumpAndSettle();
      expect(browser.url, '/admissions#enquire');
      expect(browser.entries.length, entries, reason: 'the same entry');
      expect(browser.reports.last.replace, isTrue);
      expect(page(tester), '/admissions#enquire');

      PublicRoutes.open(pageContext(tester), '/teacher-training#fees');
      await tester.pumpAndSettle();
      expect(browser.url, '/teacher-training#fees');
      expect(browser.entries.length, entries + 1);
      expect(page(tester), '/teacher-training#fees');

      await browser.back(tester);
      expect(page(tester), '/admissions#enquire', reason: 'the page and its section');
      await browser.forward(tester);
      expect(page(tester), '/teacher-training#fees');
    });

    testWidgets('a dialog is closed by Back first, the page stays', (tester) async {
      await start(tester);
      await tap(tester, 'public-nav-/programs');
      showDialog<void>(context: pageContext(tester), builder: (_) => const AlertDialog(key: Key('probe-dialog'), content: Text('Hello')));
      await tester.pumpAndSettle();
      await browser.back(tester);
      expect(find.byKey(const Key('probe-dialog')), findsNothing);
      expect(title(tester), 'Programs');
      expect(browser.url, '/programs', reason: 'the address returns to the page');
    });
  });

  group('direct addresses and refresh', () {
    testWidgets('opened directly (or refreshed): that page and section, Home beneath for the app’s own back', (tester) async {
      await start(tester, at: '/teacher-training#enquire');
      expect(title(tester), 'Teacher Training');
      expect(page(tester), '/teacher-training#enquire');
      expect(browser.urls, ['/teacher-training#enquire'], reason: 'no entry added on opening');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PublicHomePage), findsOneWidget);
    });

    testWidgets('a custom page and an unknown address', (tester) async {
      await start(tester, at: '/pages/Open-Day');
      expect(find.byType(PublicCustomPage), findsOneWidget);
      expect(page(tester), '/pages/open-day');
      expect(browser.url, '/pages/Open-Day', reason: 'the address is never rewritten');
      await tester.pumpWidget(const SizedBox());
      await start(tester, at: '/no-such-page');
      expect(find.byType(PublicHomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(browser.urls, ['/no-such-page'], reason: 'no redirect entry');
    });

    testWidgets('Back to an entry from before a refresh opens it', (tester) async {
      await start(tester, at: '/programs');
      browser.entries.insert(0, (uri: '/contact', state: {AppRouteParser.stateKey: 'old-session-3'}));
      browser.index = 1;
      await browser.back(tester);
      expect(title(tester), 'Contact');
    });
  });

  group('management, unchanged inside the Router', () {
    testWidgets('Login opens /app (an entry); its routes keep their names and arguments; the address follows them', (tester) async {
      await start(tester);
      await tap(tester, 'public-management-login');
      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(browser.url, '/app');
      final shell = tester.state<NavigatorState>(find.byType(Navigator).last);
      shell.pushNamed('/otp', arguments: {'phone': '9876543210'});
      await tester.pumpAndSettle();
      expect(tester.widget<OtpScreen>(find.byType(OtpScreen)).phoneNumber, '9876543210');
      expect(browser.url, '/app', reason: '/otp was never shown as the address');
      shell.pushNamedAndRemoveUntil('/login', (route) => false);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(OtpScreen), findsNothing);
      expect(browser.url, '/login', reason: 'replaced, as before');
      expect(browser.reports.last.replace, isTrue);
      shell.pushReplacementNamed('/app');
      await tester.pumpAndSettle();
      expect(find.byType(AuthGate), findsOneWidget);
      await browser.back(tester);
      expect(find.byType(PublicHomePage), findsOneWidget, reason: 'Back from the management app returns to the site');
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('Back closes a management screen first, through its PopScope (unsaved changes are kept)', (tester) async {
      await start(tester);
      await tap(tester, 'public-management-login');
      final shell = tester.state<NavigatorState>(find.byType(Navigator).last);
      var asked = 0;
      var allow = false;
      shell.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('a screen', key: Key('probe-plain')))));
      await tester.pumpAndSettle();
      shell.push(MaterialPageRoute<void>(
        builder: (context) => StatefulBuilder(
          builder: (context, setState) => PopScope(
            canPop: allow,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) asked++;
            },
            child: const Scaffold(body: Text('unsaved edits', key: Key('probe-guarded'))),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await browser.back(tester);
      expect(asked, 1, reason: 'the guard asked');
      expect(find.byKey(const Key('probe-guarded')), findsOneWidget, reason: 'nothing discarded');
      expect(browser.url, '/app', reason: 'the address stays on the management app');

      allow = true;
      shell.pop();
      await tester.pumpAndSettle();
      await browser.back(tester);
      expect(find.byKey(const Key('probe-plain')), findsNothing, reason: 'an ordinary screen just closes');
      expect(find.byType(LoginScreen), findsOneWidget);
      await browser.back(tester);
      expect(find.byType(PublicHomePage), findsOneWidget);
    });

    testWidgets('named routes pushed on the app’s Navigator still work (as tests and older code use them)', (tester) async {
      await start(tester);
      final root = tester.state<NavigatorState>(find.byType(Navigator).first);
      root.pushNamed('/login');
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      root.pop();
      await tester.pumpAndSettle();
      root.pushNamed('/otp', arguments: {'phone': '9000000001'});
      await tester.pumpAndSettle();
      expect(tester.widget<OtpScreen>(find.byType(OtpScreen)).phoneNumber, '9000000001');
      root.pop();
      await tester.pumpAndSettle();
      root.pushNamed(PublicRoutes.admissions);
      await tester.pumpAndSettle();
      expect(find.byType(PublicSectionPage), findsOneWidget);
    });

    testWidgets('/otp opened without its phone (an address typed in) starts at /app instead of failing', (tester) async {
      await start(tester, at: '/otp');
      expect(tester.takeException(), isNull);
      expect(find.byType(AuthGate), findsOneWidget);
    });
  });
}
