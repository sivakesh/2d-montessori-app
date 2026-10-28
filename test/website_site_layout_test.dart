// Site layout (Settings -> Website -> Site layout): the public header and
// footer — site name, tagline, main and footer navigation, footer text and
// copyright — stored as `site_layout` in the page drafts / live pages
// collections and read with the live pages the site already loads.
// - Round-trips; a malformed or unknown-version layout is ignored (the
//   built-in layout is used); a malformed link is dropped.
// - The first draft reproduces the current navigation exactly.
// - Saving a draft never changes the live site; publishing does;
//   unpublishing returns to the built-in layout (no page is unpublished).
// - Links to additional pages resolve only to published pages; reserved
//   app routes and non-https links are refused; hidden links disappear
//   without touching their page; footer links stay out of the header.
// - English/Tamil labels; the editor's desktop/mobile preview shows the
//   draft without publishing it; admin only.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_site_layout_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/content/website_site_layout.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/ui/public_custom_page.dart';

AppUser _user(String role) => AppUser(id: '9000000002', phone: '9000000002', role: role, isActive: true, name: 'Test $role');
final _admin = _user('admin');

const _desktop = Size(1400, 1000);
const _mobile = Size(390, 844);

CustomPage _page(String id, {String slug = 'open-day', bool inNav = false, bool archived = false}) =>
    CustomPage(id: id, slug: slug, title: LocalizedText(en: 'Page $id', ta: 'பக்கம் $id'), showInNavigation: inNav, archived: archived);

List<String> _routes(List<PublicNavEntry> entries) => [for (final e in entries) e.route];

final _builtInRoutes = PublicRoutes.sections;

void main() {
  group('model', () {
    final layout = SiteLayout(
      siteName: const LocalizedText(en: 'Our School', ta: 'எங்கள் பள்ளி'),
      tagline: const LocalizedText(en: 'Learning together'),
      mainNav: [
        const SiteNavEntry(id: 'm1', target: SiteNavTarget.builtIn('admissions'), label: LocalizedText(en: 'Join us', ta: 'சேருங்கள்')),
        const SiteNavEntry(id: 'm2', target: SiteNavTarget.page('p1'), visible: false),
        const SiteNavEntry(id: 'm3', target: SiteNavTarget.external('https://example.org/a'), label: LocalizedText(en: 'Partner')),
      ],
      footerNav: const [SiteNavEntry(id: 'f1', target: SiteNavTarget.builtIn('contact'))],
      footerText: const LocalizedText(en: 'Visit us any weekday.'),
      copyright: const LocalizedText(en: '© 2026 Our School'),
    );

    test('1. serializes and parses back to the same layout', () {
      final map = layout.toMap();
      expect(map.keys.toSet(), {'kind', 'schemaVersion', 'siteName', 'tagline', 'mainNav', 'footerNav', 'footerText', 'copyright'});
      expect(map['schemaVersion'], 1);
      expect((map['mainNav'] as List)[1], {'id': 'm2', 'label': {'en': '', 'ta': ''}, 'target': {'kind': 'page', 'pageId': 'p1'}, 'visible': false});
      final parsed = SiteLayout.tryParse(map)!;
      expect(parsed.sameContentAs(layout), isTrue);
      expect(parsed.mainNav[0].label.ta, 'சேருங்கள்');
      expect(parsed.mainNav[2].target, const SiteNavTarget.external('https://example.org/a'));
      expect(parsed.validationErrors(), isEmpty);
    });

    test('12. malformed or unknown-version layouts are ignored; a malformed link is dropped', () {
      final good = layout.toMap();
      expect(SiteLayout.tryParse(null), isNull);
      expect(SiteLayout.tryParse('layout'), isNull);
      expect(SiteLayout.tryParse({...good, 'schemaVersion': 2}), isNull);
      expect(SiteLayout.tryParse({...good, 'kind': 'custom'}), isNull);
      expect(SiteLayout.tryParse({...good, 'mainNav': 'home'}), isNull);
      expect(SiteLayout.tryParse({...good, 'footerNav': null}), isNull);
      expect(SiteLayout.tryParse({...good, 'siteName': 'Plain string'}), isNull);
      final partly = SiteLayout.tryParse({
        ...good,
        'mainNav': [
          'not a map',
          {'id': '', 'target': {'kind': 'builtin', 'id': 'home'}},
          {'id': 'x', 'target': {'kind': 'javascript', 'url': 'javascript:alert(1)'}},
          {'id': 'ok', 'target': {'kind': 'builtin', 'id': 'programs'}},
        ],
      })!;
      expect([for (final e in partly.mainNav) e.id], ['ok']);
    });

    test('2. the first draft reproduces the current navigation (header and footer)', () {
      final pages = [_page('a', slug: 'aa', inNav: true), _page('b', slug: 'bb'), _page('c', slug: 'cc', inNav: true)];
      final first = SiteLayout.fromCurrentNavigation(pages);
      final expected = [..._builtInRoutes.take(5), '/pages/aa', '/pages/cc', PublicRoutes.contact];
      final resolved = PublicSiteChrome.resolve(first, pages);
      expect(_routes(resolved.mainNav), expected);
      expect(_routes(resolved.footerNav), expected);
      expect(_routes(PublicSiteChrome.builtIn(pages).mainNav), expected, reason: 'identical to the built-in layout');
      expect(first.siteName.isEmpty && first.tagline.isEmpty && first.footerText.isEmpty && first.copyright.isEmpty, isTrue);
      expect([for (final e in first.mainNav) e.label.isEmpty], everyElement(isTrue), reason: 'labels follow the pages’ own names');
      expect(first.validationErrors(), isEmpty);
    });

    test('6. page links resolve only to published, usable pages; titles come from the live page', () {
      final layout = SiteLayout(mainNav: const [
        SiteNavEntry(id: '1', target: SiteNavTarget.page('live')),
        SiteNavEntry(id: '2', target: SiteNavTarget.page('draft-only')),
        SiteNavEntry(id: '3', target: SiteNavTarget.page('deleted')),
        SiteNavEntry(id: '4', target: SiteNavTarget.page('archived')),
        SiteNavEntry(id: '5', target: SiteNavTarget.page('bad-slug')),
        SiteNavEntry(id: '6', target: SiteNavTarget.page('live'), label: LocalizedText(en: 'Again')),
      ]);
      final published = [_page('live', slug: 'live-page'), _page('archived', slug: 'old', archived: true), _page('bad-slug', slug: 'Bad Slug')];
      final chrome = PublicSiteChrome.resolve(layout, published);
      expect(_routes(chrome.mainNav), ['/pages/live-page'], reason: 'one link per destination; drafts, deleted, archived and malformed pages are hidden');
      expect(chrome.mainNav.single.title.en, 'Page live');
      expect(layout.unpublishedLinkErrors({'live'}), hasLength(4));
      expect(
        layout.copyWith(mainNav: [for (final e in layout.mainNav) e.copyWith(visible: e.target.value == 'live')]).unpublishedLinkErrors({'live'}),
        isEmpty,
        reason: 'hidden links may wait for their page',
      );
    });

    test('7. reserved app routes and anything but complete https links are refused', () {
      for (final bad in [
        '/app', '/login', '/otp', '/dashboard', '/admin_dashboard', '/pages/open-day', '#/app', '/admissions',
        'http://example.org', 'javascript:alert(1)', 'mailto:a@b.c', 'https://', 'https://user@example.org',
        'https://exa mple.org', 'example.org', '', 'https://example.org/${'a' * 500}',
      ]) {
        expect(SiteNavTarget.validateExternalUrl(bad), isNotNull, reason: bad);
      }
      expect(SiteNavTarget.validateExternalUrl('https://example.org/visit?x=1'), isNull);
      expect(SiteNavTarget.validateExternalUrl('/dashboard'), contains('protected'));
      for (final route in ['/app', '/login/', '/otp?x', '/dashboard', '/admin_profile_form', '/pages/x', '/pages']) {
        expect(PublicRoutes.isReserved(route), isTrue, reason: route);
      }
      for (final route in ['/', '/admissions', '/gallery', '/application']) {
        expect(PublicRoutes.isReserved(route), isFalse, reason: route);
      }
      // A stored builtin target can only be a built-in page id.
      const sneaky = SiteLayout(mainNav: [SiteNavEntry(id: 'x', target: SiteNavTarget.builtIn('app'))]);
      expect(sneaky.validationErrors(), isNotEmpty);
      expect(PublicSiteChrome.resolve(sneaky, const []).mainNav, isEmpty);
      final external = SiteLayout(mainNav: [SiteNavEntry(id: 'x', target: const SiteNavTarget.external('http://example.org'), label: const LocalizedText(en: 'X'))]);
      expect(PublicSiteChrome.resolve(external, const []).mainNav, isEmpty, reason: 'checked again when shown');
    });

    test('validation: limits, duplicates, labels', () {
      final many = SiteLayout(mainNav: [for (var i = 0; i < 11; i++) SiteNavEntry(id: '$i', target: SiteNavTarget.external('https://e.org/$i'), label: const LocalizedText(en: 'x'))]);
      expect(many.validationErrors(), contains('Main navigation can have at most 10 links.'));
      const dup = SiteLayout(footerNav: [
        SiteNavEntry(id: 'a', target: SiteNavTarget.builtIn('home')),
        SiteNavEntry(id: 'b', target: SiteNavTarget.builtIn('home')),
      ]);
      expect(dup.validationErrors().single, contains('already in Footer navigation'));
      const noLabel = SiteLayout(mainNav: [SiteNavEntry(id: 'a', target: SiteNavTarget.external('https://e.org'))]);
      expect(noLabel.validationErrors().single, contains('English label'));
      const tamilOnly = SiteLayout(tagline: LocalizedText(ta: 'தமிழ்'));
      expect(tamilOnly.validationErrors().single, contains('English text'));
      final long = SiteLayout(siteName: LocalizedText(en: 'x' * 61));
      expect(long.validationErrors().single, contains('60 characters'));
    });

    test('10. labels in English and Tamil; blank Tamil falls back to English; blank label uses the page name', () {
      const layout = SiteLayout(mainNav: [
        SiteNavEntry(id: 'a', target: SiteNavTarget.builtIn('admissions'), label: LocalizedText(en: 'Join us', ta: 'சேருங்கள்')),
        SiteNavEntry(id: 'b', target: SiteNavTarget.builtIn('programs'), label: LocalizedText(en: 'Courses')),
        SiteNavEntry(id: 'c', target: SiteNavTarget.builtIn('gallery')),
      ]);
      final chrome = PublicSiteChrome.resolve(layout, const []);
      final en = PublicStrings.of(PublicLanguage.english);
      final ta = PublicStrings.of(PublicLanguage.tamil);
      expect([for (final e in chrome.mainNav) e.label(en, PublicLanguage.english)], ['Join us', 'Courses', en.gallery]);
      expect([for (final e in chrome.mainNav) e.label(ta, PublicLanguage.tamil)], ['சேருங்கள்', 'Courses', ta.gallery]);
    });
  });

  group('service and public site', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    WebsiteContentRepository repository() => WebsiteContentRepository(firestore: firestore);

    Future<CustomPage> customPage(String slug, {bool publish = true, bool inNav = false}) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: LocalizedText(en: 'Page $slug', ta: 'பக்கம் $slug'), slug: slug);
      // One visible block: an empty page can't be published.
      final text = BlockRegistry.create(BlockRegistry.text);
      final page = created.copyWith(
        showInNavigation: inNav,
        blocks: () => [text.copyWith(values: {...text.values, 'heading': LocalizedText(en: 'About $slug')})],
      );
      if (publish) {
        await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      } else {
        await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page);
      }
      return page;
    }

    Future<void> pumpSite(WidgetTester tester, {Size size = _desktop}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          websiteContentRepositoryProvider.overrideWithValue(repository()),
        ],
        child: const MontessoriApp(),
      ));
      await tester.pumpAndSettle();
    }

    Finder key(String k) => find.byKey(Key(k));

    test('admin only', () async {
      for (final role in ['staff', 'parent', 'user']) {
        await expectLater(service.getSiteLayout(requesterRole: role), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(service.saveSiteLayoutDraft(requesterRole: role, actor: _user(role), layout: const SiteLayout()), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(service.publishSiteLayout(requesterRole: role, actor: _user(role), layout: const SiteLayout()), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(service.unpublishSiteLayout(requesterRole: role, actor: _user(role)), throwsA(isA<UnauthorizedWebsiteContentException>()));
      }
    });

    test('2. the service’s first draft uses the published pages in their order (not drafts or archived pages)', () async {
      final a = await customPage('aa', inNav: true);
      await customPage('bb', inNav: true, publish: false);
      final c = await customPage('cc', inNav: true);
      await customPage('dd');
      await service.archiveCustomPage(requesterRole: 'admin', actor: _admin, pageId: c.id);
      final first = await service.initialSiteLayout(requesterRole: 'admin');
      final pageTargets = [for (final e in first.mainNav) if (e.target.kind == SiteNavTargetKind.page) e.target.value];
      expect(pageTargets, [a.id]);
      expect(first.mainNav.last.target, const SiteNavTarget.builtIn('contact'));
      final saved = await service.getSiteLayout(requesterRole: 'admin');
      expect(saved.draft, isNull, reason: 'nothing is written until the admin saves');
      expect(saved.live, isNull);
    });

    test('3-5. a draft never reaches visitors; publish does; unpublish returns to the built-in layout', () async {
      const draft = SiteLayout(siteName: LocalizedText(en: 'Draft name'), mainNav: [SiteNavEntry(id: 'm', target: SiteNavTarget.builtIn('gallery'))]);
      await service.saveSiteLayoutDraft(requesterRole: 'admin', actor: _admin, layout: draft);
      expect((await repository().liveContent()).layout, isNull);
      expect((await firestore.collection(WebsiteCollections.livePages).doc(SiteLayout.docId).get()).exists, isFalse);

      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: draft);
      final live = (await repository().liveContent()).layout!;
      expect(live.siteName.en, 'Draft name');
      final raw = (await firestore.collection(WebsiteCollections.livePages).doc(SiteLayout.docId).get()).data()!;
      expect(raw.keys.toSet(), {'kind', 'schemaVersion', 'siteName', 'tagline', 'mainNav', 'footerNav', 'footerText', 'copyright', 'publishedAt'}, reason: 'no editor names on the public copy');
      final draftRaw = (await firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLayout.docId).get()).data()!;
      expect(draftRaw['updatedByName'], 'Test admin');
      expect(draftRaw['lastPublishedByName'], 'Test admin');

      await service.saveSiteLayoutDraft(requesterRole: 'admin', actor: _admin, layout: draft.copyWith(siteName: const LocalizedText(en: 'Newer draft')));
      expect((await repository().liveContent()).layout!.siteName.en, 'Draft name', reason: 'a later draft leaves the live layout alone');
      final both = await service.getSiteLayout(requesterRole: 'admin');
      expect(both.draft!.siteName.en, 'Newer draft');
      expect(both.live!.siteName.en, 'Draft name');

      await service.unpublishSiteLayout(requesterRole: 'admin', actor: _admin);
      expect((await repository().liveContent()).layout, isNull);
      expect((await service.getSiteLayout(requesterRole: 'admin')).draft!.siteName.en, 'Newer draft', reason: 'the draft is kept');
    });

    test('6-7. publishing refuses visible links to unpublished pages, and invalid links', () async {
      final draftPage = await customPage('later', publish: false);
      final layout = SiteLayout(mainNav: [SiteNavEntry(id: 'p', target: SiteNavTarget.page(draftPage.id))]);
      await service.saveSiteLayoutDraft(requesterRole: 'admin', actor: _admin, layout: layout);
      await expectLater(
        service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: layout),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('isn’t published'))),
      );
      expect((await repository().liveContent()).layout, isNull);
      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: layout.copyWith(mainNav: [layout.mainNav.single.copyWith(visible: false)]));
      expect((await repository().liveContent()).layout, isNotNull, reason: 'a hidden link may wait for its page');

      final bad = SiteLayout(mainNav: [SiteNavEntry(id: 'x', target: const SiteNavTarget.external('http://example.org'), label: const LocalizedText(en: 'X'))]);
      await expectLater(service.saveSiteLayoutDraft(requesterRole: 'admin', actor: _admin, layout: bad), throwsA(isA<WebsiteContentException>()));
      await expectLater(service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: bad), throwsA(isA<WebsiteContentException>()));
    });

    test('the layout document is not mistaken for a page; custom-page listings ignore it', () async {
      await customPage('aa');
      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: const SiteLayout());
      final content = await repository().liveContent();
      expect(content.pages, isEmpty);
      expect([for (final p in content.customPages) p.slug], ['aa']);
      expect((await service.listCustomPages(requesterRole: 'admin')), hasLength(1));
    });

    testWidgets('with nothing published the site keeps its built-in header and footer', (tester) async {
      await customPage('aa', inNav: true);
      await pumpSite(tester);
      // (Seven links don't fit inline at this width, so the header uses its
      // menu, as before; the footer lists them all.)
      expect(tester.widget<Text>(find.descendant(of: key('public-header'), matching: find.text('2D Montessori'))).data, '2D Montessori');
      for (final route in [..._builtInRoutes, '/pages/aa']) {
        expect(key('public-footer-$route'), findsOneWidget, reason: route);
      }
      expect(tester.widget<Text>(key('public-footer-site-name')).data, '2D Montessori');
      expect(key('public-footer-copyright'), findsNothing);
      expect(key('public-footer-text'), findsNothing);
    });

    testWidgets('4, 8, 9. the published layout: its links in order, hidden links gone (page still reachable), footer-only links', (tester) async {
      final page = await customPage('open-day');
      await service.publishSiteLayout(
        requesterRole: 'admin',
        actor: _admin,
        layout: SiteLayout(
          siteName: const LocalizedText(en: 'Our School', ta: 'எங்கள் பள்ளி'),
          tagline: const LocalizedText(en: 'Learning together'),
          mainNav: [
            const SiteNavEntry(id: 'm1', target: SiteNavTarget.builtIn('programs'), label: LocalizedText(en: 'Courses', ta: 'படிப்புகள்')),
            const SiteNavEntry(id: 'm2', target: SiteNavTarget.builtIn('home')),
            SiteNavEntry(id: 'm3', target: SiteNavTarget.page(page.id), visible: false),
          ],
          footerNav: [
            SiteNavEntry(id: 'f1', target: SiteNavTarget.page(page.id)),
            const SiteNavEntry(id: 'f2', target: SiteNavTarget.external('https://example.org/visit'), label: LocalizedText(en: 'Partner school')),
          ],
          footerText: const LocalizedText(en: 'Open on weekdays.'),
          copyright: const LocalizedText(en: '© 2026 Our School'),
        ),
      );
      await pumpSite(tester);
      final navLinks = tester.widgetList<TextButton>(find.byWidgetPredicate((w) => w is TextButton && (w.key as ValueKey?)?.value.toString().startsWith('public-nav-') == true));
      expect([for (final b in navLinks) (b.key! as ValueKey).value], ['public-nav-/programs', 'public-nav-/']);
      expect(find.text('Courses'), findsOneWidget);
      expect(key('public-nav-/pages/open-day'), findsNothing, reason: 'hidden from the header');
      expect(key('public-nav-/admissions'), findsNothing);
      expect(key('public-footer-/pages/open-day'), findsOneWidget, reason: 'footer-only link');
      expect(key('public-footer-https://example.org/visit'), findsOneWidget);
      expect(key('public-nav-https://example.org/visit'), findsNothing);
      expect(key('public-footer-/programs'), findsNothing, reason: 'the header list is not copied to the footer');
      expect(find.text('Our School'), findsNWidgets(2), reason: 'header and footer');
      expect(tester.widget<Text>(key('public-footer-tagline')).data, 'Learning together');
      expect(tester.widget<Text>(key('public-footer-text')).data, 'Open on weekdays.');
      expect(tester.widget<Text>(key('public-footer-copyright')).data, '© 2026 Our School');
      expect(key('public-management-login'), findsOneWidget, reason: 'account controls unchanged');

      // The hidden page is still published and reachable by its address.
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/pages/open-day');
      await tester.pumpAndSettle();
      expect(find.byType(PublicCustomPage), findsOneWidget);
      expect(find.text('Page open-day'), findsWidgets);
      expect(key('public-page-not-found'), findsNothing);

      // 10. Tamil.
      await tester.tap(key('public-language-tamil'));
      await tester.pumpAndSettle();
      expect(find.text('படிப்புகள்'), findsOneWidget);
      expect(find.text('எங்கள் பள்ளி'), findsNWidgets(2));
      expect(tester.widget<Text>(key('public-footer-tagline')).data, 'Learning together', reason: 'no Tamil entered: English');
    });

    testWidgets('mobile menu shows the main navigation, not footer-only links', (tester) async {
      await service.publishSiteLayout(
        requesterRole: 'admin',
        actor: _admin,
        layout: const SiteLayout(
          mainNav: [SiteNavEntry(id: 'm', target: SiteNavTarget.builtIn('gallery'))],
          footerNav: [SiteNavEntry(id: 'f', target: SiteNavTarget.builtIn('contact'))],
        ),
      );
      await pumpSite(tester, size: _mobile);
      await tester.tap(key('public-menu-button'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('public-menu'), matching: key('public-menu-/gallery')), findsOneWidget);
      expect(find.descendant(of: key('public-menu'), matching: key('public-menu-/contact')), findsNothing);
      expect(find.descendant(of: key('public-menu'), matching: key('public-management-login')), findsOneWidget);
      await tester.tap(key('public-menu-/gallery'));
      await tester.pumpAndSettle();
      expect(ModalRoute.of(tester.element(key('public-header')))?.settings.name, PublicRoutes.gallery);
    });

    testWidgets('5. after unpublishing, visitors get the built-in layout again', (tester) async {
      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: const SiteLayout(mainNav: [SiteNavEntry(id: 'm', target: SiteNavTarget.builtIn('gallery'))]));
      await service.unpublishSiteLayout(requesterRole: 'admin', actor: _admin);
      await pumpSite(tester);
      for (final route in _builtInRoutes) {
        expect(key('public-nav-$route'), findsOneWidget, reason: route);
      }
    });

    testWidgets('12. a malformed published layout falls back to the built-in layout', (tester) async {
      await firestore.collection(WebsiteCollections.livePages).doc(SiteLayout.docId).set({'kind': 'layout', 'schemaVersion': 1, 'mainNav': 'oops', 'footerNav': []});
      await pumpSite(tester);
      expect(tester.takeException(), isNull);
      for (final route in _builtInRoutes) {
        expect(key('public-nav-$route'), findsOneWidget, reason: route);
      }
      expect((await service.getSiteLayout(requesterRole: 'admin')).liveUnreadable, isTrue);
    });
  });

  group('editor', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    Finder key(String k) => find.byKey(Key(k));
    Finder inPreview(Finder f) => find.descendant(of: key('website-layout-preview'), matching: f);

    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: WebsiteSiteLayoutEditorScreen(service: service, user: _admin)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('11. opens on the current navigation; the desktop/mobile preview follows the draft without publishing; English only', (tester) async {
      await pumpEditor(tester);
      expect(tester.widget<Text>(key('website-edit-source-text')).data, contains('reproduces the website’s current header and footer'));
      expect(key('website-layout-main-entry-main-home'), findsOneWidget);
      expect(key('website-layout-footer-entry-footer-contact'), findsOneWidget);

      await tester.enterText(key('website-layout-site-name-en'), 'Preview School');
      expect(key('website-layout-site-name-ta'), findsNothing, reason: 'English only');
      await tester.enterText(key('website-layout-copyright-en'), '© Preview');
      await tester.pumpAndSettle();
      expect(key('website-layout-preview-frame-desktop'), findsOneWidget);
      expect(inPreview(find.text('Preview School')), findsNWidgets(2), reason: 'real header and footer');
      expect(inPreview(find.text('© Preview')), findsOneWidget);

      await tap(tester, key('website-layout-preview-mobile'));
      expect(key('website-layout-preview-frame-mobile'), findsOneWidget);
      expect(key('website-layout-preview-frame-menu'), findsOneWidget);
      expect(inPreview(key('public-menu-/gallery')), findsOneWidget);
      expect(inPreview(key('public-menu-button')), findsOneWidget, reason: 'the mobile header uses the menu');

      expect(key('website-layout-preview-ta'), findsNothing, reason: 'no preview-language switch');

      expect((await firestore.collection(WebsiteCollections.livePages).doc(SiteLayout.docId).get()).exists, isFalse);
      expect((await firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLayout.docId).get()).exists, isFalse);
      expect(key('website-layout-unsaved'), findsOneWidget);
    });

    testWidgets('add, hide, reorder and remove links; external links must be https; publish and unpublish ask first', (tester) async {
      await pumpEditor(tester);
      // Add an external footer link: http is refused, https accepted.
      await tap(tester, key('website-layout-footer-add'));
      await tap(tester, key('website-link-kind-external'));
      await tester.enterText(key('website-link-url'), 'http://example.org');
      expect(key('website-link-label-ta'), findsNothing, reason: 'English only');
      await tester.enterText(key('website-link-label-en'), 'Partner');
      await tap(tester, key('website-link-save'));
      expect(key('website-link-error'), findsOneWidget);
      await tester.enterText(key('website-link-url'), '/dashboard');
      await tap(tester, key('website-link-save'));
      expect(tester.widget<Text>(key('website-link-error')).data, contains('protected'));
      await tester.enterText(key('website-link-url'), 'https://example.org');
      await tap(tester, key('website-link-save'));
      expect(key('website-link-error'), findsNothing);
      expect(find.text('Partner'), findsWidgets);

      // Hide Gallery in the main navigation; move Admissions first.
      await tap(tester, key('website-layout-main-visible-main-gallery'));
      expect(key('website-layout-main-status-main-gallery'), findsOneWidget);
      expect(inPreview(key('public-nav-/gallery')), findsNothing);
      await tap(tester, key('website-layout-main-up-main-admissions'));

      // Remove Contact from the footer (confirmed).
      await tap(tester, key('website-layout-footer-remove-footer-contact'));
      await tap(tester, key('website-layout-footer-remove-confirm'));
      expect(key('website-layout-footer-entry-footer-contact'), findsNothing);

      // Publish asks first; cancelling publishes nothing.
      await tap(tester, key('website-layout-publish'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await firestore.collection(WebsiteCollections.livePages).doc(SiteLayout.docId).get()).exists, isFalse);
      await tap(tester, key('website-layout-publish'));
      await tap(tester, key('website-layout-publish-confirm'));
      final live = (await service.getSiteLayout(requesterRole: 'admin')).live!;
      expect([for (final e in live.mainNav) e.target.value].take(2), ['admissions', 'home']);
      expect(live.mainNav.firstWhere((e) => e.target.value == 'gallery').visible, isFalse);
      expect(live.footerNav.last.target, const SiteNavTarget.external('https://example.org'));
      expect(live.footerNav.any((e) => e.target.value == 'contact'), isFalse);

      await tap(tester, key('website-layout-unpublish'));
      await tap(tester, key('website-layout-unpublish-confirm'));
      expect((await service.getSiteLayout(requesterRole: 'admin')).live, isNull);
      expect((await service.getSiteLayout(requesterRole: 'admin')).draft, isNotNull);
    });

    testWidgets('the legacy "Show in navigation" setting explains that a published Site layout controls navigation', (tester) async {
      final page = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      Future<String> helpText() async {
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
          child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: page.id)),
        ));
        await tester.pumpAndSettle();
        return tester.widget<Text>(key('website-custom-nav-help')).data!;
      }

      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      expect(await helpText(), contains('Once a site layout is published, Site layout controls the navigation'));
      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: const SiteLayout());
      expect(await helpText(), contains('Not used while a site layout is published'));

      final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))]);
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).state = _admin;
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: WebsiteContentScreen(service: service))));
      await tester.pumpAndSettle();
      await tap(tester, key('website-tab-pages'));
      expect(key('website-pages-layout-note'), findsOneWidget);
    });

    testWidgets('Settings -> Website shows the Site layout tab and opens the editor', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))]);
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).state = _admin;
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: WebsiteContentScreen(service: service))));
      await tester.pumpAndSettle();
      await tap(tester, key('website-tab-layout'));
      expect(find.text('Built-in layout'), findsOneWidget);
      await tap(tester, key('website-layout-card'));
      expect(find.byType(WebsiteSiteLayoutEditorScreen), findsOneWidget);
    });
  });
}
