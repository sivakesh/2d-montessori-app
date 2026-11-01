// Public website routes and links:
// - Reserved app routes (/app, /login, /otp, /dashboard, /admin_*) are
//   recognised however they are written (case, encoding, slashes, dot
//   segments), and https links to this website can't reach them through
//   the path or a #/ route — in the navigation and in page buttons.
//   Genuine external https links still work.
// - Clean path URLs: the app opens the page in the address when started
//   there (a refresh or a new tab), with Home underneath for Back;
//   protected routes keep their own guards; old /#/ links map to their
//   page.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/auth/ui/auth_gate.dart';
import 'package:montessori_app/modules/auth/ui/login_screen.dart';
import 'package:montessori_app/modules/parent/ui/parent_dashboard.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/content/website_site_layout.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/ui/public_custom_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_section_page.dart';

const _hosts = {'2dmontessori.com', 'montessori-app-95988.web.app'};

/// Same-site addresses that must never be accepted as links.
const _sameSiteProtected = [
  'https://2dmontessori.com/app',
  'https://2dmontessori.com/#/app',
  'https://2dmontessori.com/#!/login',
  'https://2dmontessori.com/index.html#/dashboard',
  'https://2DMontessori.COM/APP',
  'https://www.2dmontessori.com/otp',
  'https://2dmontessori.com./dashboard',
  'https://2dmontessori.com:8443/app',
  'https://2dmontessori.com//app',
  'https://2dmontessori.com/x/../app',
  'https://2dmontessori.com/./login/',
  'https://2dmontessori.com/%61pp',
  'https://2dmontessori.com/%2561pp',
  'https://2dmontessori.com/%2Fapp',
  'https://2dmontessori.com/admin_dashboard',
  'https://2dmontessori.com/#/admin_profile_form?x=1',
  'https://2dmontessori.com/#%2Fapp',
  'https://2dmontessori.com/app;jsessionid=1',
  'https://2dmontessori.com/app?next=/',
  'https://2dmontessori%2Ecom/app',
  'https://montessori-app-95988.web.app/#/dashboard',
];

/// Genuine external links that must keep working.
const _external = [
  'https://example.org/app',
  'https://example.org/#/login',
  'https://2dmontessori.com.example.org/app',
  'https://not2dmontessori.com/dashboard',
  'https://www.example.org/pages/open-day',
  'https://example.org/admissions?term=2026#apply',
];

void main() {
  group('reserved routes', () {
    test('are recognised however they are written', () {
      for (final route in ['/app', '/APP', '//app/', '/%61pp', '/x/../app', '/./login', r'\dashboard', '/otp?x', '/otp#y', '/admin_session_logs', '/pages/x', '/pages']) {
        expect(PublicRoutes.isReserved(route), isTrue, reason: route);
      }
      for (final route in ['/', '/admissions', '/teacher-training', '/gallery', '/application', '/apps', '/administration', '/pagesx']) {
        expect(PublicRoutes.isReserved(route), isFalse, reason: route);
      }
      expect(PublicRoutes.normalizeRoute('//Pages//Open-Day/'), '/pages/open-day');
      expect(PublicRoutes.isProtectedAppRoute('/%61pp'), isTrue);
      expect(PublicRoutes.isProtectedAppRoute('/admin_dashboard'), isTrue);
      expect(PublicRoutes.isProtectedAppRoute('/pages/open-day'), isFalse, reason: 'reserved for typing, but a public page');
      for (final bad in ['/%zz', '/pages/%zz', 'https://2dmontessori.com/%zz', 'https://2dmontessori.com/#/%zz', 'https://2dmontessori.com/%00app']) {
        expect(SiteNavTarget.validateExternalUrl(bad, siteHosts: _hosts), isNotNull, reason: 'malformed input is refused, never thrown: $bad');
        expect(SafeLinkTarget.validate(bad, siteHosts: _hosts), isNotNull, reason: bad);
      }
      expect(SiteNavTarget.validateExternalUrl('https://2dmontessori.com/pages/open-day', siteHosts: _hosts), contains('on this website'), reason: 'not called “protected”');
      expect(SiteNavTarget.validateExternalUrl('/pages/open-day'), contains('page list'));
      expect(PublicRoutes.routesInUrl(Uri.parse('https://s.com/#/app')), ['/', '/app']);
      expect(PublicRoutes.routesInUrl(Uri.parse('https://s.com/gallery#top')), ['/gallery'], reason: 'an ordinary anchor is not a route');
    });

    test('site hosts are matched exactly (case, trailing dot, www., port ignored)', () {
      for (final url in ['https://2dmontessori.com/', 'https://WWW.2dmontessori.com.', 'https://2dmontessori.com:444/x']) {
        expect(PublicSiteHosts.isSiteUrl(Uri.parse(url), hosts: _hosts), isTrue, reason: url);
      }
      for (final url in ['https://2dmontessori.com.example.org/', 'https://example.org/2dmontessori.com', 'https://x2dmontessori.com/']) {
        expect(PublicSiteHosts.isSiteUrl(Uri.parse(url), hosts: _hosts), isFalse, reason: url);
      }
      expect(PublicSiteHosts.current(), containsAll(['2dmontessori.com', 'twod-montessori-prod.web.app']));
    });
  });

  group('navigation links (site layout)', () {
    test('same-site https links to protected routes are refused', () {
      for (final url in _sameSiteProtected) {
        expect(SiteNavTarget.validateExternalUrl(url, siteHosts: _hosts), contains('protected'), reason: url);
      }
    });

    test('same-site links to public pages are refused (choose from the page list); external links are kept', () {
      expect(SiteNavTarget.validateExternalUrl('https://2dmontessori.com/admissions', siteHosts: _hosts), contains('on this website'));
      expect(SiteNavTarget.validateExternalUrl('https://2dmontessori.com/#/pages/open-day', siteHosts: _hosts), isNotNull);
      for (final url in _external) {
        expect(SiteNavTarget.validateExternalUrl(url, siteHosts: _hosts), isNull, reason: url);
      }
      // The built-in hosts apply without a test override too.
      expect(SiteNavTarget.validateExternalUrl('https://2dmontessori.com/#/app'), isNotNull);
      expect(SiteNavTarget.validateExternalUrl('https://twod-montessori-prod.web.app/dashboard'), isNotNull);
    });

    test('a published layout with a same-site protected link never shows it', () {
      const layout = SiteLayout(mainNav: [
        SiteNavEntry(id: 'a', target: SiteNavTarget.external('https://2dmontessori.com/#/app'), label: LocalizedText(en: 'Staff')),
        SiteNavEntry(id: 'b', target: SiteNavTarget.external('https://example.org/'), label: LocalizedText(en: 'Partner')),
      ]);
      expect(layout.validationErrors(), hasLength(1));
      expect([for (final e in PublicSiteChrome.resolve(layout, const []).mainNav) e.route], ['https://example.org/']);
    });
  });

  group('page buttons (custom pages)', () {
    test('same-site https buttons to protected routes are refused; public addresses are suggested instead', () {
      for (final url in _sameSiteProtected) {
        expect(SafeLinkTarget.validate(url, siteHosts: _hosts), contains('protected'), reason: url);
      }
      expect(SafeLinkTarget.validate('https://2dmontessori.com/pages/open-day', siteHosts: _hosts), contains('/admissions'));
      for (final url in _external) {
        expect(SafeLinkTarget.validate(url, siteHosts: _hosts), isNull, reason: url);
      }
      for (final ok in ['/admissions', '/pages/open-day', '/', 'mailto:office@example.org', 'tel:+911234567890']) {
        expect(SafeLinkTarget.validate(ok, siteHosts: _hosts), isNull, reason: ok);
      }
      expect(SafeLinkTarget.validate('https://user@example.org/', siteHosts: _hosts), isNotNull);
    });
  });

  group('clean URLs', () {
    test('page addresses are clean paths', () {
      expect(PublicRoutes.sections, ['/', '/admissions', '/teacher-training', '/programs', '/gallery', '/contact']);
      expect(PublicRoutes.customPage('open-day'), '/pages/open-day');
      final chrome = PublicSiteChrome.builtIn([const CustomPage(id: 'p', slug: 'open-day', title: LocalizedText(en: 'Open day'), showInNavigation: true)]);
      for (final e in chrome.mainNav) {
        expect(e.route, startsWith('/'));
        expect(e.route, isNot(contains('#')));
      }
    });

    test('old #/ links map to their page; anything else uses the path', () {
      expect(PublicRoutes.legacyHashRoute('/', '#/pages/about'), '/pages/about');
      expect(PublicRoutes.legacyHashRoute('/', '#/admissions'), '/admissions');
      expect(PublicRoutes.legacyHashRoute('', '#/app'), '/app', reason: 'protected routes keep their own guards, as with hash URLs');
      expect(PublicRoutes.legacyHashRoute('/', '#/'), '/');
      expect(PublicRoutes.legacyHashRoute('/', ''), isNull);
      expect(PublicRoutes.legacyHashRoute('/', '#top'), isNull, reason: 'an anchor, not a route');
      expect(PublicRoutes.legacyHashRoute('/programs', '#/gallery'), isNull, reason: 'a real path wins');
    });

    late FakeFirebaseFirestore firestore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      await firestore.collection(WebsiteCollections.livePages).doc('p1').set(
            const CustomPage(id: 'p1', slug: 'open-day', title: LocalizedText(en: 'Open day', ta: 'திறந்த நாள்')).toContentMap(),
          );
    });

    /// Starts the app at [route], as a browser does on a refresh or in a
    /// new tab with path URLs.
    Future<void> startAt(WidgetTester tester, String route) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.defaultRouteNameTestValue = route;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
        ],
        child: const MontessoriApp(),
      ));
      await tester.pumpAndSettle();
    }

    String? currentRoute(WidgetTester tester) => ModalRoute.of(tester.element(find.byType(Scaffold).last))?.settings.name;

    for (final route in ['/admissions', '/teacher-training', '/programs', '/contact']) {
      testWidgets('refresh on $route opens that page; Back returns Home', (tester) async {
        await startAt(tester, route);
        expect(tester.takeException(), isNull);
        expect(find.byType(PublicSectionPage), findsOneWidget);
        expect(currentRoute(tester), route);
        await tester.binding.handlePopRoute(); // browser Back
        await tester.pumpAndSettle();
        expect(find.byType(PublicHomePage), findsOneWidget);
      });
    }

    testWidgets('refresh on /pages/<slug> opens the published page, in English and Tamil', (tester) async {
      await startAt(tester, '/pages/open-day');
      expect(find.byType(PublicCustomPage), findsOneWidget);
      expect(find.text('Open day'), findsWidgets);
      await tester.tap(find.byKey(const Key('public-language-tamil')));
      await tester.pumpAndSettle();
      expect(find.text('திறந்த நாள்'), findsWidgets);
      expect(currentRoute(tester), '/pages/open-day', reason: 'switching language keeps the address');
    });

    testWidgets('an unknown page address shows "page not found"; an unknown route opens Home', (tester) async {
      await startAt(tester, '/pages/not-published');
      expect(find.byKey(const Key('public-page-not-found')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await startAt(tester, '/no-such-page');
      // Flutter reports the unknown start route (in debug) and opens Home —
      // as it did for /#/no-such-page with hash URLs.
      expect(tester.takeException(), contains('Could not navigate to initial route'));
      expect(find.byType(PublicHomePage), findsOneWidget);
    });

    testWidgets('navigation links change the route (and so the clean address); Back works', (tester) async {
      Future<void> tapLink(String key) async {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }

      await startAt(tester, '/');
      await tapLink('public-footer-/programs');
      expect(currentRoute(tester), '/programs');
      await tapLink('public-footer-/gallery');
      expect(currentRoute(tester), '/gallery');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PublicHomePage), findsOneWidget, reason: 'public pages replace each other above Home');
    });

    testWidgets('protected routes keep their guards when opened directly: /app and /dashboard ask signed-out visitors to log in', (tester) async {
      await startAt(tester, '/app');
      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await startAt(tester, '/dashboard');
      expect(tester.takeException(), isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ParentDashboard), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await startAt(tester, '/login');
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
