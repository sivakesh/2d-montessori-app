// Multilingual foundation (L0 + L1):
// - LocalizedText keeps every language key it reads (Hindi, French, codes
//   added later), so saving English/Tamil — through the service's
//   whole-document writes and through every editor — never drops another
//   language; the stored English/Tamil format is unchanged.
// - Validators check every language against the English source; Tamil
//   messages are unchanged.
// - The language registry (`site_languages`, draft/live like site_layout):
//   seven languages, English and Tamil on; codes validated (no route
//   words); admin-only draft/publish/unpublish; visitors get the enabled
//   and public languages, or English and Tamil with nothing usable
//   published; turning a language off deletes nothing.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_editors.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_languages_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_site_layout_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/content/website_languages.dart';
import 'package:montessori_app/modules/public_website/content/website_site_layout.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';

class _FakeProcessor implements WebsiteImageProcessor {
  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async => ProcessedWebsiteImage(
        width: 1600,
        height: 1200,
        display: Uint8List.fromList([1, 2, 3]),
        displayContentType: 'image/jpeg',
        thumb: Uint8List.fromList([4]),
        thumbContentType: 'image/jpeg',
      );
}

AppUser _user(String role) => AppUser(id: '9000000002', phone: '9000000002', role: role, isActive: true, name: 'Test $role');
final _admin = _user('admin');

/// English and Tamil plus Hindi, French and a code this app doesn't know.
Map<String, String> _multi(String en) => {'en': en, 'ta': 'த $en', 'hi': 'हि $en', 'fr': 'fr $en', 'xx-YY': 'future $en'};

const _hindi = PublicLanguage('hi', nativeName: 'हिन्दी', englishName: 'Hindi');

SiteLanguageRegistry _registry({Set<String> visible = const {'en', 'ta'}, Set<String> enabled = const {}, String fallback = 'en'}) =>
    SiteLanguageRegistry(
      fallbackCode: fallback,
      languages: [
        for (final l in SiteLanguageRegistry.defaults.languages)
          l.copyWith(enabled: visible.contains(l.code) || enabled.contains(l.code), isPublic: visible.contains(l.code)),
      ],
    );

void main() {
  group('L0: LocalizedText keeps every language', () {
    test('round-trips Hindi, French and unknown codes; English/Tamil format unchanged', () {
      final text = LocalizedText.fromMap({..._multi('Hello'), 'n': 3, 'nested': {'a': 'b'}});
      expect(text.en, 'Hello');
      expect(text.ta, 'த Hello');
      expect(text.textFor('hi'), 'हि Hello');
      expect(text.textFor('xx-YY'), 'future Hello');
      expect(text.toMap(), {'en': 'Hello', 'ta': 'த Hello', 'fr': 'fr Hello', 'hi': 'हि Hello', 'xx-YY': 'future Hello'}, reason: 'non-text values are not language text');
      expect(LocalizedText.fromMap(text.toMap()), text);
      expect(const LocalizedText(en: 'a', ta: 'b').toMap(), {'en': 'a', 'ta': 'b'}, reason: 'existing records keep their exact shape');
      expect(LocalizedText.fromMap('plain').toMap(), {'en': 'plain', 'ta': ''});
    });

    test('editing English or Tamil keeps the other languages', () {
      final text = LocalizedText.fromMap(_multi('Hello'));
      final edited = text.copyWith(en: 'Hi', ta: 'வணக்கம்');
      expect(edited.textFor('hi'), 'हि Hello');
      expect(edited.withText('fr', 'Salut').textFor('hi'), 'हि Hello');
      expect(edited.trimmed().others, text.others);
      expect(text.sameTextAs(text.copyWith()), isTrue);
      expect(text.sameTextAs(text.withText('hi', 'other')), isFalse, reason: 'every language counts');
      expect(const LocalizedText(en: 'a').sameTextAs(const LocalizedText(en: 'a', others: {'hi': ''})), isTrue, reason: 'missing = empty');
      expect(const LocalizedText(others: {'hi': 'x'}).isEmpty, isFalse);
    });

    test('resolve: own text, then the fallback language, then English (English/Tamil unchanged)', () {
      final text = LocalizedText.fromMap({'en': 'Hello', 'ta': 'வணக்கம்', 'hi': 'नमस्ते'});
      expect(text.resolve(PublicLanguage.english), 'Hello');
      expect(text.resolve(PublicLanguage.tamil), 'வணக்கம்');
      expect(text.resolve(_hindi), 'नमस्ते');
      expect(const LocalizedText(en: 'Hello', ta: 'வணக்கம்').resolve(_hindi), 'Hello');
      expect(const LocalizedText(en: 'Hello', ta: 'வணக்கம்').resolve(_hindi.withFallback('ta')), 'வணக்கம்');
      expect(const LocalizedText(en: 'Hello').resolve(_hindi.withFallback('ta')), 'Hello');
      expect(const LocalizedText(en: 'Hello').resolve(PublicLanguage.tamil), 'Hello', reason: 'as before');
    });

    test('validators check every language against English; Tamil messages unchanged', () {
      const hindiOnly = SiteLayout(tagline: LocalizedText(others: {'hi': 'हिन्दी'}));
      expect(hindiOnly.validationErrors().single, 'The tagline: enter the English text as well as the Hindi text.');
      const tamilOnly = SiteLayout(tagline: LocalizedText(ta: 'தமிழ்'));
      expect(tamilOnly.validationErrors().single, 'The tagline: enter the English text as well as the Tamil text.');
      final longHindi = SiteLayout(siteName: LocalizedText(en: 'ok', others: {'hi': 'x' * 61}));
      expect(longHindi.validationErrors().single, contains('60 characters'));
      final page = CustomPage(id: 'p', slug: 'aa', title: const LocalizedText(en: 'T'), intro: const LocalizedText(others: {'fr': 'Bonjour'}));
      expect(page.validationErrors().single, 'Introduction: enter the English text as well as the French text.');
      expect(PublicLanguage.english, const PublicLanguage('en', nativeName: 'x', englishName: 'y'), reason: 'equal by code');
      expect(PublicLanguage.tamil.name, 'tamil', reason: 'widget keys unchanged');
    });
  });

  group('L0: saving keeps other languages (service whole-document writes)', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<Map<String, dynamic>> raw(String collection, String id) async => (await firestore.collection(collection).doc(id).get()).data()!;

    test('built-in page draft and publish', () async {
      await firestore.collection(WebsiteCollections.pageDrafts).doc('admissions').set({'slot': 'admissions', 'imageMediaId': '', 'mediaIds': [], 'headline': _multi('Join'), 'intro': _multi('Welcome')});
      final draft = await service.getDraft(requesterRole: 'admin', slot: WebsitePageSlot.admissions);
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: draft.copyWith(headline: draft.headline.copyWith(en: 'Join us')));
      final saved = await raw(WebsiteCollections.pageDrafts, 'admissions');
      expect(saved['headline'], {..._multi('Join'), 'en': 'Join us'});
      expect(saved['intro'], _multi('Welcome'));
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: draft);
      expect((await raw(WebsiteCollections.livePages, 'admissions'))['intro'], _multi('Welcome'));
    });

    test('additional page draft and publish (title, intro and section text)', () async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
        'title': _multi('Open day'),
        // A page made of sections, as pages were before the page builder.
        'schemaVersion': FieldValue.delete(),
        'blocks': FieldValue.delete(),
        'sections': [
          {'id': 's1', 'type': 'text', 'heading': _multi('About'), 'body': _multi('Body')},
        ],
      });
      final page = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!.draft;
      final section = page.sections.single;
      final edited = page.copyWith(title: page.title.copyWith(en: 'Open Day 2026'), sections: [section.copyWith(body: section.body.copyWith(ta: 'புதியது'))]);
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: edited);
      final saved = await raw(WebsiteCollections.pageDrafts, created.id);
      expect(saved['title'], {..._multi('Open day'), 'en': 'Open Day 2026'});
      expect((saved['sections'] as List).single['heading'], _multi('About'));
      expect((saved['sections'] as List).single['body'], {..._multi('Body'), 'ta': 'புதியது'});
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: edited);
      expect((await raw(WebsiteCollections.livePages, created.id))['title']['hi'], 'हि Open day');
    });

    test('media alt text and captions', () async {
      final media = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: PickedWebsiteImage(name: 'a.jpg', bytes: Uint8List.fromList([1])));
      await firestore.collection(WebsiteCollections.media).doc(media.id).update({'alt': _multi('Children reading'), 'caption': _multi('Library')});
      final fresh = (await service.getMedia(requesterRole: 'admin', mediaId: media.id))!;
      await service.updateMediaDetails(
        requesterRole: 'admin',
        actor: _admin,
        mediaId: media.id,
        alt: fresh.alt.copyWith(en: 'Children reading together'),
        caption: fresh.caption,
        category: fresh.category,
        inGallery: fresh.inGallery,
        focalX: 0.5,
        focalY: 0.5,
        consentConfirmed: true,
      );
      final saved = await raw(WebsiteCollections.media, media.id);
      expect(saved['alt'], {..._multi('Children reading'), 'en': 'Children reading together'});
      expect(saved['caption'], _multi('Library'));
    });

    test('site layout text and link labels', () async {
      await firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLayout.docId).set({
        ...SiteLayout(mainNav: const [SiteNavEntry(id: 'm', target: SiteNavTarget.builtIn('home'))]).toMap(),
        'siteName': _multi('School'),
        'mainNav': [
          {'id': 'm', 'label': _multi('Home'), 'target': {'kind': 'builtin', 'id': 'home'}, 'visible': true},
        ],
      });
      final draft = (await service.getSiteLayout(requesterRole: 'admin')).draft!;
      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: draft.copyWith(siteName: draft.siteName.copyWith(en: 'Our School')));
      final live = await raw(WebsiteCollections.livePages, SiteLayout.docId);
      expect(live['siteName'], {..._multi('School'), 'en': 'Our School'});
      expect((live['mainNav'] as List).single['label'], _multi('Home'));
    });
  });

  group('L0: editors keep other languages', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Finder key(String k) => find.byKey(Key(k));

    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: screen),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      // A snackbar from the last action can cover what is tapped next.
      for (final messenger in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
        messenger.removeCurrentSnackBar();
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    Future<Map<String, dynamic>> raw(String collection, String id) async => (await firestore.collection(collection).doc(id).get()).data()!;

    testWidgets('built-in page editor: edit English, save; reset to built-in keeps Hindi too', (tester) async {
      await firestore.collection(WebsiteCollections.pageDrafts).doc('programs').set({'slot': 'programs', 'imageMediaId': '', 'mediaIds': [], 'headline': _multi('Programs'), 'intro': _multi('Our programs')});
      await pump(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.programs));
      await tester.enterText(key('website-page-headline-en'), 'Our programmes');
      await tap(tester, key('website-page-save-draft'));
      final saved = await raw(WebsiteCollections.pageDrafts, 'programs');
      expect(saved['headline'], {..._multi('Programs'), 'en': 'Our programmes'});
      expect(saved['intro'], _multi('Our programs'));

      await tap(tester, key('website-page-reset'));
      await tap(tester, key('website-page-reset-confirm'));
      await tap(tester, key('website-page-save-draft'));
      final reset = await raw(WebsiteCollections.pageDrafts, 'programs');
      expect(reset['headline']['hi'], 'हि Programs');
      expect(reset['headline']['en'], WebsitePageSlot.programs.builtInHeadline.en);
    });

    testWidgets('additional page editor: title and section text', (tester) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
        'title': _multi('Open day'),
        // A page made of sections, as pages were before the page builder.
        'schemaVersion': FieldValue.delete(),
        'blocks': FieldValue.delete(),
        'sections': [
          {'id': 's1', 'type': 'text', 'heading': _multi('About'), 'body': _multi('Body')},
        ],
      });
      await pump(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: created.id));
      await tester.enterText(key('website-custom-title-en'), 'Open Day 2026');
      final bodyEn = find.byKey(const Key('website-section-s1-body-en'));
      await tester.ensureVisible(bodyEn);
      await tester.enterText(bodyEn, 'New body');
      await tester.pumpAndSettle();
      await tap(tester, key('website-custom-save-draft'));
      final saved = await raw(WebsiteCollections.pageDrafts, created.id);
      expect(saved['title'], {..._multi('Open day'), 'en': 'Open Day 2026'});
      final section = (saved['sections'] as List).single as Map;
      expect(section['body'], {..._multi('Body'), 'en': 'New body'});
      expect(section['heading'], _multi('About'));
    });

    testWidgets('site layout editor: identity text and an edited link label', (tester) async {
      await firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLayout.docId).set({
        ...const SiteLayout().toMap(),
        'siteName': _multi('School'),
        'mainNav': [
          {'id': 'm', 'label': _multi('Home'), 'target': {'kind': 'builtin', 'id': 'home'}, 'visible': true},
        ],
      });
      await pump(tester, WebsiteSiteLayoutEditorScreen(service: service, user: _admin));
      await tester.enterText(key('website-layout-site-name-en'), 'Our School');
      await tap(tester, key('website-layout-main-edit-m'));
      await tester.enterText(key('website-link-label-en'), 'Start');
      await tap(tester, key('website-link-save'));
      await tap(tester, key('website-layout-save-draft'));
      final saved = await raw(WebsiteCollections.pageDrafts, SiteLayout.docId);
      expect(saved['siteName'], {..._multi('School'), 'en': 'Our School'});
      expect((saved['mainNav'] as List).single['label'], {..._multi('Home'), 'en': 'Start'});

      // "Start again" is the one explicit reset: its confirmation says it
      // returns the text to the built-in wording in every language.
      await tap(tester, key('website-layout-reset'));
      expect(find.textContaining('in every language'), findsOneWidget);
      await tap(tester, key('website-layout-reset-confirm'));
      await tap(tester, key('website-layout-save-draft'));
      final reset = await raw(WebsiteCollections.pageDrafts, SiteLayout.docId);
      expect(reset['siteName'], {'en': '', 'ta': ''});
    });

    testWidgets('media editor: alt text and caption', (tester) async {
      final media = await service.uploadMedia(requesterRole: 'admin', actor: _admin, image: PickedWebsiteImage(name: 'a.jpg', bytes: Uint8List.fromList([1])));
      await firestore.collection(WebsiteCollections.media).doc(media.id).update({'alt': _multi('Children reading'), 'caption': _multi('Library')});
      final fresh = (await service.getMedia(requesterRole: 'admin', mediaId: media.id))!;
      await pump(tester, WebsiteMediaEditorScreen(service: service, user: _admin, media: fresh));
      await tester.enterText(key('website-media-alt-en'), 'Children reading together');
      await tap(tester, key('website-media-save'));
      final saved = await raw(WebsiteCollections.media, media.id);
      expect(saved['alt'], {..._multi('Children reading'), 'en': 'Children reading together'});
      expect(saved['caption'], _multi('Library'));
    });

    testWidgets('previews offer the enabled languages from the registry', (tester) async {
      await service.saveLanguageRegistryDraft(requesterRole: 'admin', actor: _admin, registry: _registry(enabled: {'hi'}));
      await pump(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.programs));
      expect(key('website-preview-en'), findsOneWidget);
      expect(key('website-preview-ta'), findsOneWidget);
      expect(key('website-preview-hi'), findsOneWidget);
      expect(key('website-preview-fr'), findsNothing);
      await tap(tester, key('website-preview-hi'));
      expect(tester.widget<Text>(key('website-preview-title')).data, WebsitePageSlot.programs.builtInHeadline.en, reason: 'no Hindi yet: English');
    });
  });

  group('L1: language registry', () {
    test('initial registry: seven languages, English and Tamil enabled and public, English fallback', () {
      const r = SiteLanguageRegistry.defaults;
      expect([for (final l in r.languages) l.code], ['en', 'ta', 'hi', 'ml', 'te', 'kn', 'fr']);
      expect([for (final l in r.languages) if (l.isVisible) l.code], ['en', 'ta']);
      expect(r.enabled.map((l) => l.code), ['en', 'ta']);
      expect(r.fallbackCode, 'en');
      expect(r.publicLanguages, PublicLanguage.builtIn);
      expect(r.validationErrors(), isEmpty);
      expect(SiteLanguageRegistry.tryParse(r.toMap())!.sameContentAs(r), isTrue);
      expect(r.toMap().keys.toSet(), {'kind', 'schemaVersion', 'source', 'fallback', 'languages'});
    });

    test('codes are validated; route words and duplicates are refused', () {
      for (final bad in ['app', 'otp', 'pages', 'EN', 'e', 'english', 'pt-br', 'hi_IN', '', 'h1']) {
        expect(SiteLanguageRegistry.validateCode(bad), isNotNull, reason: bad);
      }
      for (final ok in ['hi', 'bn', 'pt-BR', 'kok']) {
        expect(SiteLanguageRegistry.validateCode(ok), isNull, reason: ok);
      }
      final dup = SiteLanguageRegistry(languages: [...SiteLanguageRegistry.defaults.languages, const SiteLanguage(code: 'hi', nativeName: 'x', englishName: 'x')]);
      expect(dup.validationErrors(), contains('The language code “hi” is listed twice.'));
      final noEnglish = _registry(visible: {'ta'}, fallback: 'ta');
      expect(noEnglish.validationErrors(), contains('English is the source language and must stay enabled and public.'));
      final hiddenFallback = _registry(enabled: {'hi'}, fallback: 'hi');
      expect(hiddenFallback.validationErrors(), contains('The fallback language must be enabled and public.'));
      final route = SiteLanguageRegistry(languages: [...SiteLanguageRegistry.defaults.languages, const SiteLanguage(code: 'app', nativeName: 'App', englishName: 'App')]);
      expect(route.validationErrors().single, contains('website’s own addresses'));
    });

    test('unusable published registries are ignored', () {
      final good = SiteLanguageRegistry.defaults.toMap();
      for (final bad in [
        null,
        'x',
        {...good, 'schemaVersion': 2},
        {...good, 'kind': 'layout'},
        {...good, 'source': 'ta'},
        {...good, 'languages': 'en'},
        {...good, 'fallback': 'hi'},
        {...good, 'languages': [for (final l in good['languages'] as List) if ((l as Map)['code'] != 'en') l]},
      ]) {
        expect(SiteLanguageRegistry.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('public languages: enabled and public only, in order, with the fallback attached', () {
      final r = _registry(visible: {'en', 'ta', 'fr'}, enabled: {'hi'}, fallback: 'ta');
      expect([for (final l in r.publicLanguages) l.code], ['en', 'ta', 'fr']);
      expect(r.publicLanguages.last.fallbackCode, 'ta');
      expect(r.editorLanguages.map((l) => l.code), ['en', 'ta', 'hi', 'fr']);
      final reordered = r.copyWith(languages: [r.languages[6], ...r.languages.take(6)]);
      expect([for (final l in reordered.publicLanguages) l.code], ['fr', 'en', 'ta']);
      expect(const SiteLanguage(code: 'hi', nativeName: 'हिन्दी', englishName: 'Hindi', isPublic: true).isVisible, isFalse, reason: 'public needs enabled');
    });
  });

  group('L1: service, public site and editor', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    Finder key(String k) => find.byKey(Key(k));
    WebsiteContentRepository repository() => WebsiteContentRepository(firestore: firestore);

    Future<void> tap(WidgetTester tester, Finder f) async {
      // A snackbar from the last action can cover what is tapped next.
      for (final messenger in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
        messenger.removeCurrentSnackBar();
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    test('admin only', () async {
      for (final role in ['staff', 'parent', 'user']) {
        await expectLater(service.getLanguageRegistry(requesterRole: role), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(service.saveLanguageRegistryDraft(requesterRole: role, actor: _user(role), registry: SiteLanguageRegistry.defaults), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(service.publishLanguageRegistry(requesterRole: role, actor: _user(role), registry: SiteLanguageRegistry.defaults), throwsA(isA<UnauthorizedWebsiteContentException>()));
        await expectLater(service.unpublishLanguageRegistry(requesterRole: role, actor: _user(role)), throwsA(isA<UnauthorizedWebsiteContentException>()));
      }
    });

    test('draft never reaches visitors; publish does; unpublish returns to English and Tamil; invalid registries are refused', () async {
      final withHindi = _registry(visible: {'en', 'ta', 'hi'});
      await service.saveLanguageRegistryDraft(requesterRole: 'admin', actor: _admin, registry: withHindi);
      expect((await repository().liveContent()).languages, isNull);
      await service.publishLanguageRegistry(requesterRole: 'admin', actor: _admin, registry: withHindi);
      expect([for (final l in (await repository().liveContent()).languages!.publicLanguages) l.code], ['en', 'ta', 'hi']);
      final live = (await firestore.collection(WebsiteCollections.livePages).doc(SiteLanguageRegistry.docId).get()).data()!;
      expect(live.keys.toSet(), {'kind', 'schemaVersion', 'source', 'fallback', 'languages', 'publishedAt'}, reason: 'no editor names in public');
      final draft = (await firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLanguageRegistry.docId).get()).data()!;
      expect(draft['updatedByName'], 'Test admin');
      expect(draft['lastPublishedByName'], 'Test admin');
      await service.unpublishLanguageRegistry(requesterRole: 'admin', actor: _admin);
      expect((await repository().liveContent()).languages, isNull);
      expect((await service.getLanguageRegistry(requesterRole: 'admin')).draft, isNotNull, reason: 'draft kept');
      await expectLater(
        service.publishLanguageRegistry(requesterRole: 'admin', actor: _admin, registry: _registry(visible: {'ta'}, fallback: 'ta')),
        throwsA(isA<WebsiteContentException>()),
      );
    });

    test('turning a language off touches no content in any language', () async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'title': _multi('Open day')});
      final before = (await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).get()).data();
      await service.publishLanguageRegistry(requesterRole: 'admin', actor: _admin, registry: _registry(visible: {'en', 'ta', 'hi'}));
      await service.publishLanguageRegistry(requesterRole: 'admin', actor: _admin, registry: _registry());
      await service.unpublishLanguageRegistry(requesterRole: 'admin', actor: _admin);
      expect((await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).get()).data(), before);
    });

    Future<ProviderContainer> pumpSite(WidgetTester tester, {Size size = const Size(1400, 1000)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        websiteContentRepositoryProvider.overrideWithValue(repository()),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MontessoriApp()));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('no registry, or an unusable one: English and Tamil, as before', (tester) async {
      await firestore.collection(WebsiteCollections.livePages).doc(SiteLanguageRegistry.docId).set({'kind': 'languages', 'schemaVersion': 1, 'source': 'en', 'fallback': 'en', 'languages': 'oops'});
      await pumpSite(tester);
      expect(tester.takeException(), isNull);
      expect(key('public-language-english'), findsOneWidget);
      expect(key('public-language-tamil'), findsOneWidget);
      expect(key('public-language-hi'), findsNothing);
      expect((await service.getLanguageRegistry(requesterRole: 'admin')).liveUnreadable, isTrue);
    });

    testWidgets('a published registry sets the switch; Hindi shows Hindi text where it exists, otherwise English; then back to English when Hindi is withdrawn', (tester) async {
      await firestore.collection(WebsiteCollections.livePages).doc('home').set({'slot': 'home', 'imageMediaId': '', 'mediaIds': [], 'headline': {'en': 'Welcome', 'ta': 'வரவேற்பு', 'hi': 'स्वागत है'}, 'intro': {'en': 'English intro', 'ta': ''}});
      await service.publishLanguageRegistry(requesterRole: 'admin', actor: _admin, registry: _registry(visible: {'en', 'ta', 'hi'}));
      final container = await pumpSite(tester);
      expect(find.descendant(of: key('public-language-switch'), matching: find.text('हिन्दी')), findsOneWidget);
      await tester.tap(key('public-language-hi'));
      await tester.pumpAndSettle();
      expect(find.text('स्वागत है'), findsWidgets);
      expect(find.text('English intro'), findsWidgets, reason: 'no Hindi: fallback English');
      expect(find.text('Login'), findsWidgets, reason: 'interface strings stay English for Hindi in this phase');

      await service.unpublishLanguageRegistry(requesterRole: 'admin', actor: _admin);
      container.invalidate(liveWebsiteContentProvider);
      await tester.pumpAndSettle();
      expect(key('public-language-hi'), findsNothing);
      expect(container.read(publicLanguageProvider), PublicLanguage.english, reason: 'a withdrawn language returns the site to English');
      expect(find.text('Welcome'), findsWidgets);
    });

    testWidgets('more than three public languages: a menu', (tester) async {
      await service.publishLanguageRegistry(requesterRole: 'admin', actor: _admin, registry: _registry(visible: {'en', 'ta', 'hi', 'fr'}));
      await pumpSite(tester);
      expect(key('public-language-menu'), findsOneWidget);
      await tester.tap(key('public-language-menu'));
      await tester.pumpAndSettle();
      expect(find.text('Français'), findsOneWidget);
      await tester.tap(key('public-language-fr'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('public-language-switch'), matching: find.text('Français')), findsOneWidget);
    });

    testWidgets('Languages screen: enable and show Hindi, preview, publish (confirmed), add a language, unpublish', (tester) async {
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))]);
      addTearDown(container.dispose);
      container.read(currentUserProvider.notifier).state = _admin;
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp(home: WebsiteContentScreen(service: service))));
      await tester.pumpAndSettle();
      await tap(tester, key('website-tab-languages'));
      expect(find.text('English and Tamil (built-in)'), findsOneWidget);
      await tap(tester, key('website-languages-card'));
      expect(find.byType(WebsiteLanguagesEditorScreen), findsOneWidget);
      for (final code in ['en', 'ta', 'hi', 'ml', 'te', 'kn', 'fr']) {
        expect(key('website-languages-entry-$code'), findsOneWidget);
      }
      expect(tester.widget<Switch>(key('website-languages-enabled-en')).onChanged, isNull, reason: 'English is locked on');
      expect(tester.widget<Switch>(key('website-languages-public-hi')).onChanged, isNull, reason: 'public needs enabled');

      await tap(tester, key('website-languages-enabled-hi'));
      await tap(tester, key('website-languages-public-hi'));
      expect(find.descendant(of: key('website-languages-preview'), matching: find.text('हिन्दी')), findsOneWidget);
      await tap(tester, key('website-languages-up-hi'));
      expect((await firestore.collection(WebsiteCollections.livePages).doc(SiteLanguageRegistry.docId).get()).exists, isFalse);

      // A route word can't be added; a real code can (it starts off).
      await tap(tester, key('website-languages-add'));
      await tester.enterText(key('website-languages-new-code'), 'otp');
      await tester.enterText(key('website-languages-new-native'), 'X');
      await tap(tester, key('website-languages-new-save'));
      expect(tester.widget<Text>(key('website-languages-new-error')).data, contains('website’s own addresses'));
      await tester.enterText(key('website-languages-new-code'), 'bn');
      await tester.enterText(key('website-languages-new-native'), 'বাংলা');
      await tester.enterText(key('website-languages-new-english'), 'Bengali');
      await tap(tester, key('website-languages-new-save'));
      expect(key('website-languages-entry-bn'), findsOneWidget);

      await tap(tester, key('website-languages-publish'));
      await tap(tester, key('website-languages-publish-confirm'));
      final live = (await service.getLanguageRegistry(requesterRole: 'admin')).live!;
      expect([for (final l in live.languages) l.code], ['en', 'hi', 'ta', 'ml', 'te', 'kn', 'fr', 'bn']);
      expect([for (final l in live.publicLanguages) l.code], ['en', 'hi', 'ta']);
      expect(live.byCode('bn')!.enabled, isFalse);

      await tap(tester, key('website-languages-unpublish'));
      await tap(tester, key('website-languages-unpublish-confirm'));
      expect((await service.getLanguageRegistry(requesterRole: 'admin')).live, isNull);
    });
  });
}
