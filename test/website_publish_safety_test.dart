// Regression tests for the visual site editor's safety fixes:
// - "Return to the built-in page" clears the editor only once it has
//   worked, and a failure leaves the editor showing what is saved;
// - the old built-in form editor can't publish or unpublish over a page
//   whose blocks are published, and says when a page is converted;
// - hidden blocks and sections stay in drafts but never reach a live
//   (publicly readable) document;
// - a publish whose live write fails says the draft was saved, and the
//   editor shows the saved state.
//
// Failures are injected with fake_cloud_firestore's security rules, so a
// refused write throws as it would in production. These tests prove the
// app's behaviour, not real Firestore semantics (see
// test/firebase_rules/ for the emulator checks).

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/website_built_in_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_editors.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

StructuredBlock _text(String heading, {bool hidden = false}) {
  final b = BlockRegistry.create(BlockRegistry.text);
  return b.copyWith(values: {...b.values, 'heading': LocalizedText(en: heading)}, hidden: hidden);
}

StructuredBlock _section(List<WebsiteBlock> children, {bool hidden = false}) {
  final s = BlockRegistry.create(BlockRegistry.section);
  return s.copyWith(values: {...s.values, 'columns': [s.columns('columns').first.copyWith(blocks: children)]}, hidden: hidden);
}

/// A page with hidden content at every depth: a hidden top-level block, a
/// hidden block and a hidden image inside a visible section, a hidden
/// section, and a hidden unsupported block.
List<WebsiteBlock> _pageWithHidden() => [
      _text('Visible first'),
      _text('Secret top', hidden: true),
      _section([
        _text('Visible in section'),
        _text('Secret child', hidden: true),
        BlockRegistry.create(BlockRegistry.image).withValue('mediaId', 'm1').copyWith(hidden: true),
      ]),
      _section([_text('Secret section child')], hidden: true),
      UnsupportedBlock({'id': 'future-hidden', 'type': 'future', 'hidden': true, 'note': 'Secret future'}),
      UnsupportedBlock({'id': 'future-shown', 'type': 'future'}),
      _text('Visible last'),
    ];

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    await firestore.collection(WebsiteCollections.media).doc('m1').set({
      'url': 'https://example.test/m1.jpg',
      'storagePath': 'website_media/m1/d.jpg',
      'status': 'published',
      'consentConfirmed': true,
      'alt': {'en': 'Alt m1', 'ta': ''},
      'caption': {'en': '', 'ta': ''},
    });
  });

  /// Refuses every write to [collection] from now on (reads still work),
  /// as security rules or a lost connection would.
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

  void allowWrites() => firestore.securityRules = FakeFirebaseFirestore().securityRules;

  Finder key(String k) => find.byKey(Key(k));

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpAdmin(WidgetTester tester, Widget screen) async {
    await size(tester, const Size(1400, 2400));
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSite(WidgetTester tester, String route) async {
    await size(tester, const Size(1400, 2600));
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
      ],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
    await tester.pumpAndSettle();
  }

  /// Taps [f] with any message from an earlier action dismissed first, so
  /// a message found afterwards is this action's.
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

  Future<void> editAdmissionsHeading(WidgetTester tester, String text) async {
    await tap(tester, key('website-canvas-block-admissions__header'));
    final f = field('website-block-admissions__header-heading-en');
    await tester.ensureVisible(f);
    await tester.enterText(f, text);
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>?> doc(String collection, String id) async => (await firestore.collection(collection).doc(id).get()).data();

  bool enabled(WidgetTester tester, String k) => tester.widget<ButtonStyleButton>(key(k)).onPressed != null;

  // ------------------------------------------------------------- revert

  group('return to the built-in page', () {
    final admissions = BuiltInPageAdapter.blocksFor(BuiltInPage.admissions, null);

    Future<void> publishAdmissions() async {
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.admissions, headline: LocalizedText(en: 'Join us')));
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: admissions);
    }

    testWidgets('success: the blocks leave the draft and the website; the editor returns to the comparison', (tester) async {
      await publishAdmissions();
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      await tap(tester, key('website-builtin-revert'));
      await tap(tester, key('website-builtin-revert-confirm'));
      expect(key('website-builtin-convert'), findsOneWidget);
      expect(find.text('The page is its built-in self again.'), findsOneWidget);
      expect(await doc(WebsiteCollections.livePages, 'admissions'), isNull, reason: 'the live page held blocks only');
      final draft = (await doc(WebsiteCollections.pageDrafts, 'admissions'))!;
      expect(draft.containsKey('blocks'), isFalse);
      expect((draft['headline'] as Map)['en'], 'Join us', reason: 'managed content kept');
    });

    testWidgets('failure part-way: the editor keeps the edits and shows what is actually saved', (tester) async {
      await publishAdmissions();
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      await editAdmissionsHeading(tester, 'Edited, not saved');
      expect(key('website-builtin-unsaved'), findsOneWidget);

      // The live page is reverted, then the draft write is refused.
      refuseWrites(WebsiteCollections.pageDrafts);
      await tap(tester, key('website-builtin-revert'));
      await tap(tester, key('website-builtin-revert-confirm'));

      expect(find.textContaining('could not be returned to its built-in content'), findsOneWidget);
      expect(find.text('The page is its built-in self again.'), findsNothing);
      expect(key('website-builtin-blocks'), findsOneWidget, reason: 'still in the visual editor');
      expect(key('website-builtin-convert'), findsNothing);
      expect(find.descendant(of: field('website-block-admissions__header-heading-en'), matching: find.text('Edited, not saved')), findsOneWidget, reason: 'unsaved edits kept');
      expect(key('website-builtin-unsaved'), findsOneWidget);
      expect(find.text('Visitors see the built-in page'), findsOneWidget, reason: 'the status follows what is saved: live reverted');
      expect(find.text('Published with blocks'), findsNothing);
      expect(key('website-builtin-revert'), findsOneWidget, reason: 'the draft still has blocks, so it can be tried again');
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['blocks'], isNotNull);
      expect(await doc(WebsiteCollections.livePages, 'admissions'), isNull);

      allowWrites();
      await tap(tester, key('website-builtin-revert'));
      await tap(tester, key('website-builtin-revert-confirm'));
      expect(key('website-builtin-convert'), findsOneWidget);
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!.containsKey('blocks'), isFalse);
    });

    testWidgets('failure before anything changes: nothing is cleared', (tester) async {
      await publishAdmissions();
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      refuseWrites(WebsiteCollections.livePages);
      await tap(tester, key('website-builtin-revert'));
      await tap(tester, key('website-builtin-revert-confirm'));
      expect(find.textContaining('could not be returned'), findsOneWidget);
      expect(key('website-builtin-blocks'), findsOneWidget);
      expect(find.text('Published with blocks'), findsOneWidget);
      expect((await doc(WebsiteCollections.livePages, 'admissions'))!['blocks'], isNotNull);
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['blocks'], isNotNull);
    });

    testWidgets('Contact: its documents (blocks only) are removed and the built-in Contact page is back', (tester) async {
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: BuiltInPageAdapter.blocksFor(BuiltInPage.contact, null));
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.contact));
      expect(key('website-builtin-blocks'), findsOneWidget);
      await tap(tester, key('website-builtin-revert'));
      await tap(tester, key('website-builtin-revert-confirm'));
      expect(key('website-builtin-convert'), findsOneWidget);
      expect(await doc(WebsiteCollections.pageDrafts, 'contact'), isNull);
      expect(await doc(WebsiteCollections.livePages, 'contact'), isNull);
      await pumpSite(tester, '/contact');
      expect(key('public-built-in-blocks-contact'), findsNothing);
    });

    testWidgets('Contact: a refused revert keeps the editor and the blocks', (tester) async {
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: BuiltInPageAdapter.blocksFor(BuiltInPage.contact, null));
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.contact));
      refuseWrites(WebsiteCollections.pageDrafts);
      await tap(tester, key('website-builtin-revert'));
      await tap(tester, key('website-builtin-revert-confirm'));
      expect(key('website-builtin-blocks'), findsOneWidget);
      expect(find.text('Visitors see the built-in page'), findsOneWidget);
      expect(await doc(WebsiteCollections.livePages, 'contact'), isNull);
      expect((await doc(WebsiteCollections.pageDrafts, 'contact'))!['blocks'], isNotNull);
    });
  });

  // ----------------------------------------------------- failed publish

  group('publish whose live write fails', () {
    testWidgets('first publish: the draft is saved, the message says so, no published status', (tester) async {
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      await tap(tester, key('website-builtin-convert'));
      await editAdmissionsHeading(tester, 'Ready for visitors');
      refuseWrites(WebsiteCollections.livePages);
      await tap(tester, key('website-builtin-publish'));

      expect(find.text(WebsiteContentAdminService.publishFailedMessage), findsOneWidget);
      expect(find.text('Published at /admissions.'), findsNothing);
      expect(key('website-builtin-unsaved'), findsNothing, reason: 'the draft was read back');
      expect(key('website-builtin-not-saved'), findsNothing);
      expect(find.text('Visitors see the built-in page'), findsOneWidget);
      expect(find.text('Published with blocks'), findsNothing);
      expect(jsonEncode((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['blocks']), contains('Ready for visitors'));
      expect(await doc(WebsiteCollections.livePages, 'admissions'), isNull);
    });

    testWidgets('a later publish: the previous version stays live and the draft shows as not published', (tester) async {
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      await tap(tester, key('website-builtin-convert'));
      await tap(tester, key('website-builtin-publish'));
      expect(find.text('Published at /admissions.'), findsOneWidget);
      expect(key('website-builtin-draft-unpublished'), findsNothing);

      await editAdmissionsHeading(tester, 'Second version');
      refuseWrites(WebsiteCollections.livePages);
      await tap(tester, key('website-builtin-publish'));
      await tap(tester, key('website-builtin-publish-confirm'));
      expect(find.text(WebsiteContentAdminService.publishFailedMessage), findsOneWidget);
      expect(key('website-builtin-unsaved'), findsNothing);
      expect(key('website-builtin-draft-unpublished'), findsOneWidget);
      expect(find.text('Published with blocks'), findsOneWidget, reason: 'the earlier version is still live');
      expect(jsonEncode((await doc(WebsiteCollections.livePages, 'admissions'))!['blocks']), isNot(contains('Second version')));
    });

    test('service: the error names the saved draft; a refused draft write is reported as it is', () async {
      final blocks = BuiltInPageAdapter.blocksFor(BuiltInPage.programs, null);
      refuseWrites(WebsiteCollections.livePages);
      await expectLater(
        service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.programs, blocks: blocks),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', WebsiteContentAdminService.publishFailedMessage)),
      );
      expect((await doc(WebsiteCollections.pageDrafts, 'programs'))!['blocks'], isNotNull);

      refuseWrites(WebsiteCollections.pageDrafts);
      await expectLater(
        service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.teacherTraining, blocks: BuiltInPageAdapter.blocksFor(BuiltInPage.teacherTraining, null)),
        throwsA(isNot(isA<WebsiteContentException>())),
        reason: 'nothing was saved, so the message must not claim the draft was',
      );
    });
  });

  // ------------------------------------------------- old form editor

  group('the old built-in form editor and converted pages', () {
    const joinUs = WebsitePageContent(slot: WebsitePageSlot.admissions, headline: LocalizedText(en: 'Join us', ta: 'சேருங்கள்'));
    final admissions = BuiltInPageAdapter.blocksFor(BuiltInPage.admissions, null);

    Future<void> pumpForm(WidgetTester tester) => pumpAdmin(tester, WebsitePageEditorScreen(service: service, user: _admin, slot: WebsitePageSlot.admissions));

    testWidgets('an ordinary page: no notice; publish and unpublish work as before', (tester) async {
      await pumpForm(tester);
      expect(key('website-page-blocks-notice'), findsNothing);
      expect(enabled(tester, 'website-page-publish'), isTrue);
      await tap(tester, key('website-page-publish'));
      expect(find.text('Published.'), findsOneWidget);
      expect(await doc(WebsiteCollections.livePages, 'admissions'), isNotNull);
      await tap(tester, key('website-page-unpublish'));
      expect(await doc(WebsiteCollections.livePages, 'admissions'), isNull);
    });

    testWidgets('a converted draft only: notice; the form still publishes the built-in page visitors see; the blocks are kept', (tester) async {
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: joinUs);
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: admissions);
      await pumpForm(tester);
      expect(key('website-page-blocks-notice'), findsOneWidget);
      expect(find.textContaining('This page has a visual editor draft'), findsOneWidget);
      expect(enabled(tester, 'website-page-publish'), isTrue);
      await tap(tester, key('website-page-publish'));
      final live = (await doc(WebsiteCollections.livePages, 'admissions'))!;
      expect((live['headline'] as Map)['en'], 'Join us');
      expect(live.containsKey('blocks'), isFalse);
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['blocks'], isNotNull);
    });

    testWidgets('published blocks: notice; publish disabled; no unpublish; saving says visitors don’t see it; the visual editor opens', (tester) async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: joinUs);
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: admissions);
      await pumpForm(tester);
      expect(key('website-page-blocks-notice'), findsOneWidget);
      expect(find.textContaining('Visitors see the visual editor’s version of this page'), findsOneWidget);
      expect(enabled(tester, 'website-page-publish'), isFalse);
      expect(key('website-page-unpublish'), findsNothing);

      await tester.enterText(key('website-page-headline-en'), 'Later heading');
      await tester.pumpAndSettle();
      await tap(tester, key('website-page-save-draft'));
      expect(find.textContaining('which doesn’t show this content'), findsOneWidget);
      final draft = (await doc(WebsiteCollections.pageDrafts, 'admissions'))!;
      expect((draft['headline'] as Map)['en'], 'Later heading');
      expect(draft['blocks'], isNotNull, reason: 'the form keeps the blocks');
      final live = (await doc(WebsiteCollections.livePages, 'admissions'))!;
      expect(live['blocks'], isNotNull);
      expect((live['headline'] as Map)['en'], 'Join us');

      await tap(tester, key('website-page-open-visual'));
      expect(find.byType(WebsiteBuiltInPageEditorScreen), findsOneWidget);
      expect(key('website-builtin-blocks'), findsOneWidget);
    });

    test('service: the form’s publish and unpublish are refused while blocks are live; the blocks stay', () async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: joinUs);
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: admissions);
      await expectLater(service.publishPage(requesterRole: 'admin', actor: _admin, content: joinUs.copyWith(intro: const LocalizedText(en: 'X'))), throwsA(isA<WebsiteContentException>()));
      await expectLater(service.unpublishPage(requesterRole: 'admin', actor: _admin, slot: WebsitePageSlot.admissions), throwsA(isA<WebsiteContentException>()));
      final live = (await doc(WebsiteCollections.livePages, 'admissions'))!;
      expect(live['blocks'], isNotNull);
      expect((live['intro'] as Map)['en'], '', reason: 'the refused publish wrote nothing');

      // Once the blocks are unpublished, the form works again.
      await service.unpublishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions);
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: joinUs.copyWith(intro: const LocalizedText(en: 'X')));
      expect(((await doc(WebsiteCollections.livePages, 'admissions'))!['intro'] as Map)['en'], 'X');
      await service.unpublishPage(requesterRole: 'admin', actor: _admin, slot: WebsitePageSlot.admissions);
      expect(await doc(WebsiteCollections.livePages, 'admissions'), isNull);
    });

    testWidgets('a draft holding only blocks doesn’t hide the published heading from the form', (tester) async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: joinUs);
      await firestore.collection(WebsiteCollections.pageDrafts).doc('admissions').delete();
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: admissions);
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!.containsKey('headline'), isFalse);

      expect(await service.getSavedDraft(requesterRole: 'admin', slot: WebsitePageSlot.admissions), isNull);
      expect((await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.admissions)).content!.headline.en, 'Join us');
      await pumpForm(tester);
      expect(tester.widget<TextField>(key('website-page-headline-en')).controller!.text, 'Join us');
      expect(key('website-page-headline-ta'), findsNothing, reason: 'English only');
      expect((await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.admissions)).content!.headline.ta, 'சேருங்கள்', reason: 'stored Tamil is kept');
    });
  });

  // ---------------------------------------------------- hidden content

  group('hidden blocks never reach a live document', () {
    test('withoutHidden: every depth, order kept, the input untouched', () {
      final blocks = _pageWithHidden();
      final before = jsonEncode(BlockRegistry.toMapList(blocks), toEncodable: (o) => o.toString());
      final shown = BlockRegistry.withoutHidden(blocks);
      expect([for (final b in shown) b.id], [blocks[0].id, blocks[2].id, 'future-shown', blocks[6].id]);
      final section = shown[1] as StructuredBlock;
      expect([for (final b in section.columns('columns').single.blocks) (b as StructuredBlock).text('heading').en], ['Visible in section']);
      final stored = jsonEncode(BlockRegistry.toMapList(shown), toEncodable: (o) => o.toString());
      expect(stored, isNot(contains('Secret')));
      expect(stored, isNot(contains('"hidden"')));
      expect(BlockRegistry.referencedMedia(shown), isEmpty);
      expect(jsonEncode(BlockRegistry.toMapList(blocks), toEncodable: (o) => o.toString()), before, reason: 'the draft list is not changed');
    });

    testWidgets('built-in page: the draft keeps hidden content; the live page and the public page don’t have it', (tester) async {
      final blocks = _pageWithHidden();
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: blocks);
      final draft = (await doc(WebsiteCollections.pageDrafts, 'admissions'))!;
      final live = (await doc(WebsiteCollections.livePages, 'admissions'))!;
      expect(jsonEncode(draft['blocks']), allOf(contains('Secret top'), contains('Secret child'), contains('Secret section child'), contains('Secret future')));
      expect(draft['mediaIds'], ['m1'], reason: 'the draft uses the hidden image');
      expect(jsonEncode(live['blocks']), isNot(contains('Secret')));
      expect(jsonEncode(live['blocks']), contains('future-shown'), reason: 'other unsupported blocks are kept for newer versions');
      expect(live['mediaIds'], isEmpty, reason: 'no reference to the hidden image');

      await pumpSite(tester, '/admissions');
      expect(key('public-built-in-blocks-admissions'), findsOneWidget);
      expect(find.textContaining('Secret'), findsNothing);
      final first = tester.getTopLeft(find.text('Visible first')).dy;
      final middle = tester.getTopLeft(find.text('Visible in section')).dy;
      final last = tester.getTopLeft(find.text('Visible last')).dy;
      expect(first < middle && middle < last, isTrue, reason: 'order kept');

      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      expect(key('website-builtin-draft-unpublished'), findsNothing, reason: 'hidden blocks don’t count as unpublished changes');
      expect(key('website-builtin-unsaved'), findsNothing);
    });

    testWidgets('additional page: the same; its status doesn’t report unpublished changes', (tester) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      final page = created.copyWith(blocks: _pageWithHidden);
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      final draft = (await doc(WebsiteCollections.pageDrafts, created.id))!;
      final live = (await doc(WebsiteCollections.livePages, created.id))!;
      expect(jsonEncode(draft['blocks']), contains('Secret child'));
      expect(draft['mediaIds'], ['m1']);
      expect(jsonEncode(live['blocks']), isNot(contains('Secret')));
      expect(jsonEncode(live['sections']), isNot(contains('Secret')));
      expect(live['mediaIds'], isEmpty);

      final saved = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(saved.draft.samePublishedContentAs(saved.live), isTrue);
      expect(saved.draft.sameContentAs(saved.live), isFalse, reason: 'the draft itself still holds the hidden blocks');

      await pumpSite(tester, '/pages/open-day');
      expect(find.text('Visible first'), findsOneWidget);
      expect(find.textContaining('Secret'), findsNothing);
    });

    test('a page without blocks (made of sections) is published unchanged', () async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour'), slug: 'tour');
      final legacy = created.copyWith(blocks: () => null, sections: [const CustomPageSection(id: 's1', type: CustomSectionType.text, heading: LocalizedText(en: 'Hello'))]);
      expect(legacy.forVisitors, same(legacy));
    });
  });
}
