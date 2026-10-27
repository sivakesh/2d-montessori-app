// Regression tests for three publication safeguards:
// 1. Publishing over a page visitors already see asks first (built-in
//    visual editor, additional-page editor, old form editor); Cancel
//    writes nothing, Confirm publishes what is in the editor. A first
//    publication isn't asked about.
// 2. A page built with blocks can't be published when nothing on it would
//    be shown (no blocks, or only hidden ones); its draft can still be
//    saved, and pages made of sections are unchanged.
// 3. When the draft saves but the live write fails, the editors say
//    "Draft saved, but publication failed." and show the saved state; a
//    layout published before its draft cleanup failed is reported as
//    published.
//
// Failures are injected with fake_cloud_firestore's security rules, or,
// where only one call must fail, with the mock_exceptions hook
// fake_cloud_firestore checks before every write. They prove the app's
// handling, not real Firestore semantics.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// The failure hook fake_cloud_firestore itself depends on (not a direct
// dependency of the app).
// ignore: depend_on_referenced_packages
import 'package:mock_exceptions/mock_exceptions.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/website_built_in_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_editors.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_site_layout_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/content/website_site_layout.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

StructuredBlock _text(String heading, {bool hidden = false}) {
  final b = BlockRegistry.create(BlockRegistry.text);
  return b.copyWith(values: {...b.values, 'heading': LocalizedText(en: heading, ta: 'தமிழ் $heading')}, hidden: hidden);
}

StructuredBlock _section(List<WebsiteBlock> children, {bool hidden = false}) {
  final s = BlockRegistry.create(BlockRegistry.section);
  return s.copyWith(values: {...s.values, 'columns': [s.columns('columns').first.copyWith(blocks: children)]}, hidden: hidden);
}

/// Nothing a visitor would see: hidden blocks, a visible section holding
/// only hidden blocks, a hidden section, an unsupported block.
List<WebsiteBlock> _allHidden() => [
      _text('Hidden top', hidden: true),
      _section([_text('Hidden child', hidden: true)]),
      _section([_text('In a hidden section')], hidden: true),
      UnsupportedBlock({'id': 'future-1', 'type': 'future'}),
    ];

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    for (final (id, published) in [('m1', true), ('m2', false)]) {
      await firestore.collection(WebsiteCollections.media).doc(id).set({
        'url': 'https://example.test/$id.jpg',
        'storagePath': 'website_media/$id/d.jpg',
        'status': published ? 'published' : 'draft',
        'consentConfirmed': published,
        'alt': {'en': 'Alt $id', 'ta': ''},
        'caption': {'en': '', 'ta': ''},
      });
    }
  });

  /// Refuses every write to [collection] from now on (reads still work).
  void refuseWrites(String collection) {
    String match(String c) => c == collection ? 'match /$c/{id} { allow read: if true; }' : 'match /$c/{id} { allow read, write: if true; }';
    firestore.securityRules = FakeFirebaseFirestore(
      securityRules: '''
service cloud.firestore {
  match /databases/{database}/documents {
    ${match(WebsiteCollections.media)}
    ${match(WebsiteCollections.pageDrafts)}
    ${match(WebsiteCollections.livePages)}
  }
}''',
    ).securityRules;
  }

  /// Every page draft and live page, as stored: unchanged means nothing
  /// was written.
  Future<String> stored() async => jsonEncode({
        for (final c in [WebsiteCollections.pageDrafts, WebsiteCollections.livePages])
          c: {for (final d in (await firestore.collection(c).get()).docs) d.id: d.data()},
      }, toEncodable: (o) => o.toString());

  Future<Map<String, dynamic>?> doc(String collection, String id) async => (await firestore.collection(collection).doc(id).get()).data();

  Finder key(String k) => find.byKey(Key(k));

  Future<void> pumpAdmin(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1400, 2600);
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

  /// Taps [f] with any earlier message dismissed first, so a message found
  /// afterwards is this action's.
  Future<void> tap(WidgetTester tester, Finder f) async {
    for (final messenger in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
      messenger.removeCurrentSnackBar();
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Finder field(String prefix) => find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true);

  /// Selects block [id] on the canvas and types [text] as its English heading.
  Future<void> editHeading(WidgetTester tester, String id, String text) async {
    await tap(tester, key('website-canvas-block-$id'));
    final f = field('website-block-$id-heading-en');
    await tester.ensureVisible(f);
    await tester.enterText(f, text);
    await tester.pumpAndSettle();
  }

  // ----------------------------------------------- 1. confirmation

  group('confirm before replacing a published page', () {
    final admissions = BuiltInPageAdapter.blocksFor(BuiltInPage.admissions, null);

    testWidgets('built-in page: a first publication isn’t asked about; over published blocks, Cancel writes nothing and Confirm publishes the edit', (tester) async {
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      await tap(tester, key('website-builtin-convert'));
      await tap(tester, key('website-builtin-publish'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'first publication');
      expect(find.text('Published at /admissions.'), findsOneWidget);

      await editHeading(tester, 'admissions__header', 'Second version');
      final before = await stored();
      await tap(tester, key('website-builtin-publish'));
      expect(find.text('Replace the published page?'), findsOneWidget);
      expect(find.textContaining('Visitors will see this new version straight away'), findsOneWidget);
      await tap(tester, key('website-publish-cancel'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(await stored(), before, reason: 'Cancel writes nothing');
      expect(key('website-builtin-unsaved'), findsOneWidget, reason: 'the edit is kept in the editor');

      await tap(tester, key('website-builtin-publish'));
      await tap(tester, key('website-builtin-publish-confirm'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'asked once');
      expect(find.text('Published at /admissions.'), findsOneWidget);
      expect(jsonEncode((await doc(WebsiteCollections.livePages, 'admissions'))!['blocks']), contains('Second version'));
    });

    testWidgets('additional page: the same', (tester) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day', ta: 'திறந்த நாள்'), slug: 'open-day');
      final block = _text('First version');
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => [block]));
      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: created.id));
      await tap(tester, key('website-custom-publish'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'first publication');
      expect(find.text('Published at /pages/open-day.'), findsOneWidget);

      await editHeading(tester, block.id, 'Second version');
      final before = await stored();
      await tap(tester, key('website-custom-publish'));
      expect(find.text('Replace the published page?'), findsOneWidget);
      await tap(tester, key('website-publish-cancel'));
      expect(await stored(), before, reason: 'Cancel writes nothing');
      expect(key('website-custom-unsaved'), findsOneWidget);

      await tap(tester, key('website-custom-publish'));
      await tap(tester, key('website-custom-publish-confirm'));
      expect(find.byType(AlertDialog), findsNothing);
      final live = (await doc(WebsiteCollections.livePages, created.id))!;
      expect(jsonEncode(live['blocks']), contains('Second version'));
      expect(live['title'], {'en': 'Open day', 'ta': 'திறந்த நாள்'}, reason: 'Tamil kept');
    });

    testWidgets('old form editor: the same', (tester) async {
      await pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.programs));
      await tester.enterText(key('website-page-headline-en'), 'Our programmes');
      await tester.pumpAndSettle();
      await tap(tester, key('website-page-publish'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'first publication');
      expect(((await doc(WebsiteCollections.livePages, 'programs'))!['headline'] as Map)['en'], 'Our programmes');

      await tester.enterText(key('website-page-headline-en'), 'Programmes for 2027');
      await tester.pumpAndSettle();
      final before = await stored();
      await tap(tester, key('website-page-publish'));
      expect(find.text('Replace the published page?'), findsOneWidget);
      await tap(tester, key('website-publish-cancel'));
      expect(await stored(), before, reason: 'Cancel writes nothing');

      await tap(tester, key('website-page-publish'));
      await tap(tester, key('website-page-publish-confirm'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Published.'), findsOneWidget);
      expect(((await doc(WebsiteCollections.livePages, 'programs'))!['headline'] as Map)['en'], 'Programmes for 2027');
    });

    test('service: Confirm publishes exactly the blocks given (no other content changes)', () async {
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: admissions);
      final edited = [...admissions, _text('Added later')];
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: edited);
      expect((await doc(WebsiteCollections.livePages, 'admissions'))!['blocks'], BlockRegistry.toMapList(edited));
    });
  });

  group('first block publication over content published with the form editor', () {
    const legacy = WebsitePageContent(
      slot: WebsitePageSlot.admissions,
      imageMediaId: 'm1',
      headline: LocalizedText(en: 'Join us', ta: 'சேருங்கள்'),
      intro: LocalizedText(en: 'Places for 2027', ta: '2027 இடங்கள்'),
    );

    Future<void> openAndConvert(WidgetTester tester, BuiltInPage page) async {
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: page));
      await tap(tester, key('website-builtin-convert'));
    }

    final unpublished = <String, Future<void> Function()>{
      'nothing published': () async {},
      'published with the site’s own wording (stored blank)': () => service.publishPage(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.admissions)),
      'published with only an image visitors can’t see (not published)': () => firestore.collection(WebsiteCollections.livePages).doc('admissions').set({
            'slot': 'admissions',
            'imageMediaId': 'm2',
            'mediaIds': ['m2'],
            'headline': {'en': '', 'ta': ''},
            'intro': {'en': '', 'ta': ''},
          }),
    };
    for (final MapEntry(key: name, value: seed) in unpublished.entries) {
      testWidgets('no published version ($name): no confirmation', (tester) async {
        await seed();
        await openAndConvert(tester, BuiltInPage.admissions);
        await tap(tester, key('website-builtin-publish'));
        expect(find.byType(AlertDialog), findsNothing);
        if (name.contains('image')) {
          // The conversion keeps the page's image, so the usual image check
          // refuses publishing until it is published.
          expect(find.textContaining('Publish every image'), findsOneWidget);
          expect((await doc(WebsiteCollections.livePages, 'admissions'))!.containsKey('blocks'), isFalse);
        } else {
          expect(find.text('Published at /admissions.'), findsOneWidget);
          expect((await doc(WebsiteCollections.livePages, 'admissions'))!['blocks'], isNotNull);
        }
      });
    }

    testWidgets('published heading, introduction and image: confirmation; Cancel writes nothing; Confirm publishes once and keeps the published content', (tester) async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: legacy);
      final legacyLive = (await doc(WebsiteCollections.livePages, 'admissions'))!;
      await openAndConvert(tester, BuiltInPage.admissions);

      final before = await stored();
      await tap(tester, key('website-builtin-publish'));
      expect(find.text('Replace the published page?'), findsOneWidget);
      await tap(tester, key('website-publish-cancel'));
      expect(await stored(), before, reason: 'Cancel: no draft or live document changes');
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!.containsKey('blocks'), isFalse);

      await tap(tester, key('website-builtin-publish'));
      await tap(tester, key('website-builtin-publish-confirm'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'asked once');
      expect(find.text('Published at /admissions.'), findsOneWidget);
      final live = (await doc(WebsiteCollections.livePages, 'admissions'))!;
      final draft = (await doc(WebsiteCollections.pageDrafts, 'admissions'))!;
      expect(live['blocks'], draft['blocks'], reason: 'the editor’s blocks, published as saved');
      expect(jsonEncode(live['blocks']), allOf(contains('Join us'), contains('சேருங்கள்'), contains('Places for 2027')), reason: 'converted from the published content, English and Tamil');
      for (final field in ['headline', 'intro', 'imageMediaId', 'slot']) {
        expect(live[field], legacyLive[field], reason: '$field kept for older versions and for returning to the built-in page');
      }

      // Unpublishing the blocks shows the form's content again; publishing
      // blocks over it asks again.
      await tap(tester, key('website-builtin-unpublish'));
      await tap(tester, key('website-builtin-unpublish-confirm'));
      await tap(tester, key('website-builtin-publish'));
      expect(find.text('Replace the published page?'), findsOneWidget);
      await tap(tester, key('website-publish-cancel'));
      expect((await doc(WebsiteCollections.livePages, 'admissions'))!.containsKey('blocks'), isFalse);
    });

    testWidgets('a failed publication leaves the published version exactly as it was and says so', (tester) async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: legacy);
      final legacyLive = jsonEncode((await doc(WebsiteCollections.livePages, 'admissions'))!, toEncodable: (o) => o.toString());
      await openAndConvert(tester, BuiltInPage.admissions);
      refuseWrites(WebsiteCollections.livePages);
      await tap(tester, key('website-builtin-publish'));
      await tap(tester, key('website-builtin-publish-confirm'));
      expect(find.text(WebsiteContentAdminService.publishFailedMessage), findsOneWidget);
      expect(find.text('Published at /admissions.'), findsNothing);
      expect(jsonEncode((await doc(WebsiteCollections.livePages, 'admissions'))!, toEncodable: (o) => o.toString()), legacyLive);
      expect(find.text('Visitors see the built-in page'), findsOneWidget);
      expect(key('website-builtin-unsaved'), findsNothing, reason: 'the draft was saved and read back');
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['blocks'], isNotNull);
    });

    testWidgets('Contact (no form content): a first publication isn’t asked about; over its published blocks it is', (tester) async {
      await openAndConvert(tester, BuiltInPage.contact);
      await tap(tester, key('website-builtin-publish'));
      expect(find.byType(AlertDialog), findsNothing);
      expect((await doc(WebsiteCollections.livePages, 'contact'))!['blocks'], isNotNull);
      await tap(tester, key('website-builtin-publish'));
      expect(find.text('Replace the published page?'), findsOneWidget);
      await tap(tester, key('website-publish-cancel'));
    });

    test('service: the live content is reported separately from the draft’s', () async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: legacy);
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: legacy.copyWith(headline: const LocalizedText(en: 'Draft heading')));
      final page = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.admissions);
      expect(page.content!.headline.en, 'Draft heading');
      expect(page.liveContent!.headline.en, 'Join us');
      expect(page.liveContent!.headline.ta, 'சேருங்கள்');
      expect((await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.contact)).liveContent, isNull);
    });
  });

  // ------------------------------------------------ 2. empty pages

  group('a page with nothing visible can’t be published', () {
    const message = WebsiteContentAdminService.nothingVisibleMessage;
    final refused = throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', message));

    test('built-in page, empty or all hidden: refused, nothing written; the draft can still be saved', () async {
      for (final blocks in [<WebsiteBlock>[], _allHidden()]) {
        await expectLater(service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: blocks), refused);
        expect(await doc(WebsiteCollections.livePages, 'admissions'), isNull);
        expect(await doc(WebsiteCollections.pageDrafts, 'admissions'), isNull, reason: 'refused before the draft is written');
      }
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: const []);
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['blocks'], isEmpty);
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: _allHidden());
      expect(jsonEncode((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['blocks']), allOf(contains('Hidden top'), contains('Hidden child'), contains('future-1')), reason: 'hidden blocks kept in the draft');
    });

    test('additional page built with blocks, empty or all hidden: refused; the draft can still be saved', () async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      await expectLater(service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: created), refused, reason: 'a new page has no blocks');
      final hidden = created.copyWith(blocks: _allHidden);
      await expectLater(service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: hidden), refused);
      expect(await doc(WebsiteCollections.livePages, created.id), isNull);
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: hidden);
      expect(jsonEncode((await doc(WebsiteCollections.pageDrafts, created.id))!['blocks']), contains('Hidden child'));
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: created);
      expect((await doc(WebsiteCollections.pageDrafts, created.id))!['blocks'], isEmpty);
    });

    test('a page with visible content is published (without its hidden blocks)', () async {
      final visible = [..._allHidden(), _section([_text('Shown in a section')])];
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: visible);
      final live = jsonEncode((await doc(WebsiteCollections.livePages, 'admissions'))!['blocks']);
      expect(live, contains('Shown in a section'));
      expect(live, isNot(contains('Hidden')));

      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => [_text('Welcome')]));
      expect(jsonEncode((await doc(WebsiteCollections.livePages, created.id))!['blocks']), contains('Welcome'));
    });

    test('image checks are unchanged: a visible unpublished image is refused for its image', () async {
      final image = BlockRegistry.create(BlockRegistry.image).withValue('mediaId', 'm2');
      await expectLater(
        service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: [_text('Hello'), image]),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('Publish every image'))),
      );
      await expectLater(
        service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: [image.copyWith(hidden: true)]),
        refused,
        reason: 'nothing visible is reported first',
      );
    });

    test('pages made of sections (the older format) are unchanged, even with no sections', () async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour'), slug: 'tour');
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => null));
      final live = (await doc(WebsiteCollections.livePages, created.id))!;
      expect(live.containsKey('blocks'), isFalse);
      expect(live['sections'], isEmpty);
    });

    testWidgets('built-in editor: publishing an all-hidden page shows the message and changes nothing', (tester) async {
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: _allHidden());
      final before = await stored();
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.contact));
      await tap(tester, key('website-builtin-publish'));
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('Published at'), findsNothing);
      expect(await stored(), before);
    });
  });

  // ----------------------------------------- 3. failure status

  group('draft saved, publication failed', () {
    const failed = WebsiteContentAdminService.publishFailedMessage;

    test('the message', () => expect(failed, startsWith('Draft saved, but publication failed.')));

    testWidgets('additional page: the message, the draft read back, never "Published"', (tester) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      final block = _text('First version');
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => [block]));
      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: created.id));
      await editHeading(tester, block.id, 'Edited before publishing');
      expect(key('website-custom-unsaved'), findsOneWidget);

      refuseWrites(WebsiteCollections.livePages);
      await tap(tester, key('website-custom-publish'));
      expect(find.text(failed), findsOneWidget);
      expect(find.textContaining('Published at'), findsNothing);
      expect(key('website-custom-unsaved'), findsNothing, reason: 'the saved draft was read back');
      expect(find.text('Published'), findsNothing);
      expect(jsonEncode((await doc(WebsiteCollections.pageDrafts, created.id))!['blocks']), contains('Edited before publishing'));
      expect(await doc(WebsiteCollections.livePages, created.id), isNull);
    });

    testWidgets('old form editor: the same', (tester) async {
      await pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.programs));
      await tester.enterText(key('website-page-headline-en'), 'Our programmes');
      await tester.pumpAndSettle();
      expect(key('website-page-unsaved'), findsOneWidget);

      refuseWrites(WebsiteCollections.livePages);
      await tap(tester, key('website-page-publish'));
      expect(find.text(failed), findsOneWidget);
      expect(find.text('Published.'), findsNothing);
      expect(key('website-page-unsaved'), findsNothing, reason: 'the saved draft was read back');
      expect(find.text('Not published'), findsOneWidget);
      expect(((await doc(WebsiteCollections.pageDrafts, 'programs'))!['headline'] as Map)['en'], 'Our programmes');
      expect(await doc(WebsiteCollections.livePages, 'programs'), isNull);
    });

    test('service: built-in, additional and old-form pages report it the same way; a refused draft isn’t reported as saved', () async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      refuseWrites(WebsiteCollections.livePages);
      final isFailed = throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', failed));
      await expectLater(service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.programs, blocks: [_text('Hello')]), isFailed);
      await expectLater(service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => [_text('Hello')])), isFailed);
      await expectLater(service.publishPage(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.gallery, headline: LocalizedText(en: 'Photos'))), isFailed);

      refuseWrites(WebsiteCollections.pageDrafts);
      await expectLater(
        service.publishPage(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.home, headline: LocalizedText(en: 'Hi'))),
        throwsA(isNot(isA<WebsiteContentException>().having((e) => e.message, 'message', failed))),
      );
    });
  });

  group('site layout: published, but the draft cleanup failed', () {
    /// A saved layout draft that stores the default design explicitly, so
    /// publishing it runs the cleanup that removes it.
    Future<void> seedDraftWithStoredDefaults() async {
      final layout = SiteLayout.fromCurrentNavigation(const []);
      await firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLayout.docId).set({...layout.toDraftMap(), 'design': SiteDesign.defaults.toMap()});
    }

    void failCleanup() => whenCalling(Invocation.method(#update, null))
        .on(firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLayout.docId))
        .thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));

    test('service: reported as published (not as a failed publication); the live layout is written', () async {
      await seedDraftWithStoredDefaults();
      failCleanup();
      final layout = SiteLayout.fromCurrentNavigation(const []);
      await expectLater(
        service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: layout),
        throwsA(isA<WebsiteLayoutCleanupException>().having((e) => e.message, 'message', startsWith('The layout was published and visitors see it, but'))),
      );
      final live = (await doc(WebsiteCollections.livePages, SiteLayout.docId))!;
      expect(live['kind'], 'layout');
      expect(live.containsKey('design'), isFalse);
      expect((await doc(WebsiteCollections.pageDrafts, SiteLayout.docId))!['lastPublishedByName'], 'Test admin', reason: 'the batch was written');

      await expectLater(
        service.saveSiteLayoutDraft(requesterRole: 'admin', actor: _admin, layout: layout),
        throwsA(isA<WebsiteLayoutCleanupException>().having((e) => e.message, 'message', startsWith('The draft was saved, but'))),
      );
    });

    test('service: without a failure nothing changes (the default design is removed from the draft)', () async {
      await seedDraftWithStoredDefaults();
      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: SiteLayout.fromCurrentNavigation(const []));
      expect((await doc(WebsiteCollections.pageDrafts, SiteLayout.docId))!.containsKey('design'), isFalse);
    });

    testWidgets('editor: one message saying it was published; the status shows it published', (tester) async {
      await seedDraftWithStoredDefaults();
      await pumpAdmin(tester, WebsiteSiteLayoutEditorScreen(service: service, user: _admin));
      expect(find.text('Not published'), findsOneWidget);
      failCleanup();
      await tap(tester, key('website-layout-publish'));
      await tap(tester, key('website-layout-publish-confirm'));
      expect(find.textContaining('The layout was published and visitors see it, but'), findsOneWidget);
      expect(find.text('Something went wrong. Please try again.'), findsNothing);
      expect(find.text('Published. Visitors now see this layout.'), findsNothing, reason: 'one message, not two');
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Published'), findsOneWidget, reason: 'the status was read back');
      expect(find.text('Not published'), findsNothing);
    });
  });
}
