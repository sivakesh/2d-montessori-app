// The visual site editor: sections, built-in pages, the design system and
// the shared header and footer.
// - Sections: ready-made layouts, inserted at the start, between and at the
//   end; reordered, duplicated (fresh ids inside), hidden and deleted; a
//   section and a block inside it are selected separately; saved and
//   reloaded; drawn edge to edge, stacked on phones.
// - Built-in pages: converted only when asked, compared first; the
//   converted page shows exactly the same text (English and Tamil), images
//   and links through the real public page; saving and publishing write
//   only the blocks fields (the managed headline, introduction and image,
//   which older versions show, are kept); unpublishing and returning to
//   the built-in page undo it; the old form editor keeps the blocks.
// - Design: palette colours (tokens) and custom HEX colours; changing a
//   palette colour changes everything using it, a custom colour stays;
//   sections pass colours to their blocks, a block's own colour wins;
//   resetting returns to the inherited colour.
// - Header and footer: their look and contact details reach every page.
// - Admin only; unknown fields kept; responsive.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/block_list_ops.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_built_in_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_site_layout_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/legacy_sections.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/content/website_site_layout.dart';
import 'package:montessori_app/modules/public_website/content/website_site_style.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/ui/public_gallery_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_section_page.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_feature_widgets.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

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

const _m1 = WebsiteMedia(
  id: 'm1',
  url: 'https://example.test/m1.jpg',
  storagePath: 'website_media/m1/d.jpg',
  status: WebsiteMediaStatus.published,
  consentConfirmed: true,
  alt: LocalizedText(en: 'Children in the garden', ta: 'தோட்டத்தில் குழந்தைகள்'),
);

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
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

  Finder key(String k) => find.byKey(Key(k));

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpAdmin(WidgetTester tester, Widget screen, {Size s = const Size(1400, 2400)}) async {
    await size(tester, s);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
  }

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

  Future<void> pick(WidgetTester tester, String menu, String item) async {
    await tap(tester, key(menu));
    await tester.tap(key('$menu-$item'));
    await tester.pumpAndSettle();
  }

  Finder field(String prefix) => find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true);

  Future<void> type(WidgetTester tester, Finder f, String text) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.enterText(f, text);
    await tester.pumpAndSettle();
  }

  Future<Map<String, dynamic>?> doc(String collection, String id) async => (await firestore.collection(collection).doc(id).get()).data();

  /// The public website on [route], reading the fake Firestore.
  Future<void> pumpSite(WidgetTester tester, {String? route, Size s = const Size(1400, 2600)}) async {
    await size(tester, s);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
      ],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
    if (route != null) {
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
      await tester.pumpAndSettle();
    }
  }

  // ------------------------------------------------------------ sections

  group('sections', () {
    test('every ready-made section is valid as created, with fresh ids each time', () {
      for (final preset in SectionPreset.all) {
        final a = preset.create();
        final b = preset.create();
        expect(a.type, 'section', reason: preset.id);
        expect(BlockRegistry.validate([a]), isEmpty, reason: preset.id);
        final idsA = {for (final x in BlockRegistry.flatten([a])) x.id, for (final c in a.columns('columns')) c.id};
        final idsB = {for (final x in BlockRegistry.flatten([b])) x.id, for (final c in b.columns('columns')) c.id};
        expect(idsA.intersection(idsB), isEmpty, reason: '${preset.id}: new ids each time');
      }
      expect(SectionPreset.all.map((p) => p.id), containsAll(['blank', 'hero', 'about', 'programs', 'features', 'testimonials', 'gallery', 'faq', 'cta', 'contact']));
    });

    test('a section keeps unknown fields and other languages; no section or columns inside it; it has no legacy copy', () {
      final raw = {
        'id': 'b_sect000001', 'type': 'section', 'v': 1, 'layout': '1', 'futureKey': {'x': 1},
        'style': {'background': 'token:sageLight', 'futureStyle': 'kept'},
        'columns': [{'id': 'c_one0000001', 'futureColumnKey': true, 'blocks': [{'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Hi', 'ta': 'வணக்கம்', 'hi': 'नमस्ते'}}]}],
      };
      final block = BlockRegistry.parse(raw) as StructuredBlock;
      expect(BlockRegistry.validate([block]), isEmpty);
      final edited = BlockListOps.toggleHidden([block], const BlockPath.nested(0, 0, 0));
      final stored = edited.single.toMap();
      expect(stored['futureKey'], {'x': 1});
      expect(stored['style'], {'background': 'token:sageLight', 'futureStyle': 'kept'});
      final column = (stored['columns'] as List).single as Map;
      expect(column['futureColumnKey'], isTrue);
      expect(((column['blocks'] as List).single as Map)['heading'], {'en': 'Hi', 'ta': 'வணக்கம்', 'hi': 'नमस्ते'});
      expect(LegacySections.toSection(block), isNull, reason: 'older versions have no section form');

      final nested = block.withValue('columns', [BlockColumn(id: 'c_one0000001', blocks: [SectionPreset.all.first.create()])]);
      expect(BlockRegistry.blockProblems(nested), contains('section can’t contain section'));
    });

    Future<String> blockPage(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour'), slug: 'tour');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    List<WebsiteBlock> editorBlocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
    List<String?> names(WidgetTester tester) => [for (final b in editorBlocks(tester)) (b as StructuredBlock).text('name').en];

    testWidgets('insert at the start, between and at the end; reorder, duplicate, hide and delete; save and reload', (tester) async {
      final id = await blockPage(const []);
      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: id));
      expect(key('website-blocks-add-section-hero'), findsOneWidget, reason: 'the empty page offers sections');
      await tap(tester, key('website-blocks-add-section-hero'));
      expect(names(tester), ['Hero']);
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Section', reason: 'the new section is selected');

      await pick(tester, 'website-canvas-insert-0', 'section-faq');
      await pick(tester, 'website-canvas-insert-1', 'section-cta');
      await pick(tester, 'website-canvas-insert-3', 'section-contact');
      expect(names(tester), ['FAQ', 'Call to action', 'Hero', 'Contact']);
      await pick(tester, 'website-sections-add', 'blank');
      expect(names(tester), ['FAQ', 'Call to action', 'Hero', 'Contact', 'Section'], reason: 'after the selected section');

      final hero = editorBlocks(tester)[2];
      // Clicking inside the section selects the block there; clicking the
      // section's own padding selects the section.
      await tap(tester, key('website-canvas-block-${hero.id}'));
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Hero', reason: 'the hero block inside the section');
      await tester.tapAt(tester.getTopLeft(key('website-canvas-block-${hero.id}')) + const Offset(12, 12));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Section');
      await tap(tester, key('website-canvas-${hero.id}-up'));
      expect(names(tester), ['FAQ', 'Hero', 'Call to action', 'Contact', 'Section']);

      await tap(tester, key('website-canvas-${hero.id}-duplicate'));
      final copy = editorBlocks(tester)[2] as StructuredBlock;
      expect(copy.text('name').en, 'Hero');
      final original = {for (final b in BlockRegistry.flatten([hero])) b.id};
      expect({for (final b in BlockRegistry.flatten([copy])) b.id}.intersection(original), isEmpty, reason: 'the copy and everything inside it have new ids');

      await tap(tester, key('website-canvas-${copy.id}-visibility'));
      expect(key('website-canvas-placeholder-${copy.id}'), findsOneWidget);
      await tap(tester, key('website-canvas-${copy.id}-delete'));
      await tap(tester, key('website-block-delete-confirm'));
      expect(names(tester), ['FAQ', 'Hero', 'Call to action', 'Contact', 'Section']);

      await tap(tester, key('website-custom-save-draft'));
      final saved = ((await doc(WebsiteCollections.pageDrafts, id))!['blocks'] as List).cast<Map>();
      expect([for (final b in saved) (b['name'] as Map)['en']], ['FAQ', 'Hero', 'Call to action', 'Contact', 'Section']);
      expect(saved[1]['id'], hero.id);

      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: id));
      expect(names(tester), ['FAQ', 'Hero', 'Call to action', 'Contact', 'Section'], reason: 'reloads');
    });

    testWidgets('a section and a block inside it are selected separately; section settings and child edits are saved', (tester) async {
      final id = await blockPage([
        {
          'id': 'b_sect000001', 'type': 'section', 'v': 1, 'layout': '1:1', 'name': {'en': 'About', 'ta': ''},
          'columns': [
            {'id': 'c_one0000001', 'blocks': [{'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Left', 'ta': ''}}]},
            {'id': 'c_two0000001', 'blocks': [{'id': 'b_text000002', 'type': 'text', 'v': 1, 'heading': {'en': 'Right', 'ta': ''}}]},
          ],
        },
      ]);
      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: id));

      await tap(tester, key('website-canvas-block-b_text000002'));
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Text', reason: 'the block inside');
      expect(key('website-canvas-toolbar-b_text000002'), findsOneWidget);
      expect(key('website-canvas-child-selected-b_sect000001'), findsOneWidget, reason: 'the section keeps an outline');
      expect(key('website-canvas-toolbar-b_sect000001'), findsNothing, reason: 'but not its whole-section actions');
      await type(tester, field('website-block-b_text000002-heading-ta'), 'வலது');

      await tap(tester, key('website-inspector-parent'));
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Section');
      expect(key('website-canvas-toolbar-b_sect000001'), findsOneWidget);
      await tap(tester, key('website-block-b_sect000001-style-background-choose'));
      await tap(tester, key('website-block-b_sect000001-style-background-token-sageLight'));
      await tap(tester, key('website-block-b_sect000001-style-padding'));
      await tester.tap(find.byKey(const Key('website-block-b_sect000001-style-padding-72')).last);
      await tester.pumpAndSettle();

      // Add a block inside a column from the canvas.
      await pick(tester, 'website-canvas-column-c_one0000001-add', 'divider');
      expect(BlockListOps.columnsOf(editorBlocks(tester).single)[0].blocks.map((b) => b.type), ['text', 'divider']);

      await tap(tester, key('website-custom-save-draft'));
      final section = ((await doc(WebsiteCollections.pageDrafts, id))!['blocks'] as List).single as Map;
      expect(section['style'], {'background': 'token:sageLight', 'padding': '72'});
      final right = (((section['columns'] as List)[1] as Map)['blocks'] as List).single as Map;
      expect(right['heading'], {'en': 'Right', 'ta': 'வலது'});
    });

    testWidgets('a section runs edge to edge on the public page; its columns stack on phones', (tester) async {
      final block = BlockRegistry.parse({
        'id': 'b_sect000001', 'type': 'section', 'v': 1, 'layout': '1:1', 'style': {'background': 'token:goldLight'},
        'columns': [
          {'id': 'c_one0000001', 'blocks': [{'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Left', 'ta': ''}}]},
          {'id': 'c_two0000001', 'blocks': [{'id': 'b_text000002', 'type': 'text', 'v': 1, 'heading': {'en': 'Right', 'ta': ''}}]},
        ],
      });
      Future<void> render(double width) async {
        await size(tester, Size(width, 1200));
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: WebsiteBlocksView(blocks: [block], media: const {}, language: PublicLanguage.english, fullBleed: true))),
        ));
        await tester.pumpAndSettle();
      }

      await render(1400);
      expect(tester.getSize(key('public-section-b_sect000001')).width, 1400, reason: 'the background spans the page');
      final band = tester.widget<Container>(key('public-section-b_sect000001'));
      expect((band.decoration! as BoxDecoration).color, SiteDesign.defaults.colorOf('goldLight'));
      expect(tester.getTopLeft(key('public-block-column-c_two0000001')).dy, tester.getTopLeft(key('public-block-column-c_one0000001')).dy);

      await render(390);
      expect(tester.getTopLeft(key('public-block-column-c_two0000001')).dy, greaterThan(tester.getTopLeft(key('public-block-column-c_one0000001')).dy));
    });
  });

  // ------------------------------------------------------- built-in pages

  group('built-in pages', () {
    const managed = WebsitePageContent(slot: WebsitePageSlot.home, imageMediaId: 'm1', headline: LocalizedText(en: 'Welcome to our school', ta: 'எங்கள் பள்ளிக்கு வரவேற்பு', others: {'hi': 'स्वागत'}));

    Widget publicPage(BuiltInPage page) => switch (page) {
          BuiltInPage.home => const PublicHomePage(),
          BuiltInPage.gallery => const PublicGalleryPage(),
          _ => PublicSectionPage(route: page.route),
        };

    /// The visible text of [page] (header and footer included, the same on
    /// both sides) with [blocks] published or not.
    Future<List<String>> pageText(WidgetTester tester, BuiltInPage page, PublicLanguage language, {required bool converted}) async {
      final content = page.slot == WebsitePageSlot.home ? managed : null;
      final live = LiveWebsiteContent(
        pages: content == null ? const {} : {content.slot: content},
        builtInBlocks: {if (converted) page.id: BuiltInPageAdapter.blocksFor(page, content)},
      );
      await size(tester, const Size(1400, 3200));
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          liveWebsiteContentProvider.overrideWith((ref) async => live),
          publishedWebsiteMediaProvider.overrideWith((ref) async => [_m1]),
          publicLanguageProvider.overrideWith((ref) => language),
        ],
        child: MaterialApp(home: publicPage(page)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('public-built-in-blocks-${page.id}')), converted ? findsOneWidget : findsNothing);
      return [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if ((t.data ?? t.textSpan?.toPlainText() ?? '').trim() case final s when s.isNotEmpty) s,
      ];
    }

    for (final page in BuiltInPage.values) {
      for (final language in PublicLanguage.builtIn) {
        testWidgets('${page.id} (${language.code}): the converted page shows exactly the same text', (tester) async {
          final before = await pageText(tester, page, language, converted: false);
          final after = await pageText(tester, page, language, converted: true);
          expect(after, before);
        });
      }
    }

    testWidgets('home: the managed image and the pathway links are kept', (tester) async {
      await pageText(tester, BuiltInPage.home, PublicLanguage.english, converted: false);
      expect(key('public-hero-image'), findsOneWidget);
      final routes = [for (final c in tester.widgetList<PublicPathwayCard>(find.byType(PublicPathwayCard))) c.route];
      await pageText(tester, BuiltInPage.home, PublicLanguage.english, converted: true);
      expect(key('public-hero-image'), findsOneWidget);
      final blocks = BuiltInPageAdapter.blocksFor(BuiltInPage.home, managed);
      final cards = BlockRegistry.flatten(blocks).whereType<StructuredBlock>().firstWhere((b) => b.type == 'cards');
      expect([for (final c in cards.items('cards')) c.string('target')], routes);
      final hero = BlockRegistry.flatten(blocks).whereType<StructuredBlock>().firstWhere((b) => b.type == 'hero');
      expect(hero.text('heading').others['hi'], 'स्वागत', reason: 'every language of the managed text is kept');
      expect(BlockRegistry.validate(blocks), isEmpty);
    });

    test('only admins can read, save, publish, unpublish or revert built-in pages', () async {
      for (final role in ['staff', 'parent', 'user', '']) {
        final actor = _user(role);
        await expectLater(service.getBuiltInPage(requesterRole: role, page: BuiltInPage.home), throwsA(anything), reason: role);
        await expectLater(service.saveBuiltInPageDraft(requesterRole: role, actor: actor, page: BuiltInPage.home, blocks: const []), throwsA(anything));
        await expectLater(service.publishBuiltInPage(requesterRole: role, actor: actor, page: BuiltInPage.home, blocks: const []), throwsA(anything));
        await expectLater(service.unpublishBuiltInPage(requesterRole: role, actor: actor, page: BuiltInPage.home), throwsA(anything));
        await expectLater(service.revertBuiltInPage(requesterRole: role, actor: actor, page: BuiltInPage.home), throwsA(anything));
      }
      expect((await firestore.collection(WebsiteCollections.pageDrafts).get()).docs, isEmpty);
    });

    test('service: blocks fields only; managed content kept; unpublished images refused; the old form editor keeps the blocks; revert', () async {
      await service.publishPage(requesterRole: 'admin', actor: _admin, content: managed);
      final blocks = BuiltInPageAdapter.blocksFor(BuiltInPage.home, managed);
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.home, blocks: blocks);
      final draft = (await doc(WebsiteCollections.pageDrafts, 'home'))!;
      expect(draft['schemaVersion'], 2);
      expect(draft['headline'], {'en': 'Welcome to our school', 'ta': 'எங்கள் பள்ளிக்கு வரவேற்பு', 'hi': 'स्वागत'});
      expect(draft['imageMediaId'], 'm1');
      expect((await WebsiteContentRepository(firestore: firestore).liveContent()).builtInBlocks, isEmpty, reason: 'saved, not published');

      // The old form editor saves its fields only.
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: managed.copyWith(intro: const LocalizedText(en: 'New intro')));
      final afterOld = (await doc(WebsiteCollections.pageDrafts, 'home'))!;
      expect(afterOld['blocks'], draft['blocks'], reason: 'the blocks are kept');
      expect(afterOld['mediaIds'], ['m1']);

      final withDraftImage = BlockListOps.insert(blocks, const BlockPath(0), BlockRegistry.create(BlockRegistry.image).withValue('mediaId', 'm2'));
      await expectLater(service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.home, blocks: withDraftImage), throwsA(isA<WebsiteContentException>()));
      expect((await doc(WebsiteCollections.livePages, 'home'))!.containsKey('blocks'), isFalse, reason: 'refused');

      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.home, blocks: blocks);
      final live = (await doc(WebsiteCollections.livePages, 'home'))!;
      expect(live['schemaVersion'], 2);
      expect(live['headline'], draft['headline'], reason: 'what older versions show is kept');
      expect(live.keys.where((k) => k.startsWith('updatedBy')), isEmpty);
      expect((await WebsiteContentRepository(firestore: firestore).liveContent()).builtInBlocks['home'], hasLength(3));

      await service.unpublishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.home);
      final unpublished = (await doc(WebsiteCollections.livePages, 'home'))!;
      expect(unpublished.containsKey('blocks'), isFalse);
      expect(unpublished['headline'], draft['headline']);
      expect((await doc(WebsiteCollections.pageDrafts, 'home'))!['blocks'], isNotNull, reason: 'the draft keeps its blocks');

      await service.revertBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.home);
      final reverted = (await doc(WebsiteCollections.pageDrafts, 'home'))!;
      expect(reverted.containsKey('blocks') || reverted.containsKey('schemaVersion'), isFalse);
      expect(reverted['intro'], {'en': 'New intro', 'ta': ''});

      // Contact holds blocks only: reverting removes its documents.
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: BuiltInPageAdapter.blocksFor(BuiltInPage.contact, null));
      expect(await doc(WebsiteCollections.livePages, 'contact'), isNotNull);
      await service.revertBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact);
      expect(await doc(WebsiteCollections.livePages, 'contact'), isNull);
      expect(await doc(WebsiteCollections.pageDrafts, 'contact'), isNull);
    });

    testWidgets('editor: compare first, nothing written; convert, save, publish; the public page shows the blocks; return to built-in', (tester) async {
      await service.saveDraft(requesterRole: 'admin', actor: _admin, content: const WebsitePageContent(slot: WebsitePageSlot.admissions, headline: LocalizedText(en: 'Join us')));
      final before = await doc(WebsiteCollections.pageDrafts, 'admissions');
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      expect(key('website-builtin-compare-current'), findsOneWidget);
      expect(key('website-builtin-compare-blocks'), findsOneWidget);
      expect(find.descendant(of: key('website-builtin-compare-current'), matching: find.text('Join us')), findsOneWidget);
      expect(find.descendant(of: key('website-builtin-compare-blocks'), matching: find.text('Join us')), findsOneWidget);
      expect(await doc(WebsiteCollections.pageDrafts, 'admissions'), before, reason: 'opening writes nothing');

      await tap(tester, key('website-builtin-convert'));
      expect(key('website-builtin-blocks'), findsOneWidget);
      expect(key('website-builtin-not-saved'), findsOneWidget);
      expect(await doc(WebsiteCollections.pageDrafts, 'admissions'), before, reason: 'converted in the editor only');

      // Edit the converted title, then save and publish.
      await tap(tester, key('website-canvas-block-admissions__header'));
      await type(tester, field('website-block-admissions__header-heading-en'), 'Admissions are open');
      await tap(tester, key('website-builtin-save-draft'));
      expect(((await doc(WebsiteCollections.pageDrafts, 'admissions'))!['headline'] as Map)['en'], 'Join us', reason: 'managed headline kept');
      await tap(tester, key('website-builtin-publish'));
      expect((await doc(WebsiteCollections.livePages, 'admissions'))!['schemaVersion'], 2);

      await pumpSite(tester, route: '/admissions');
      expect(key('public-built-in-blocks-admissions'), findsOneWidget);
      expect(find.text('Admissions are open'), findsOneWidget);

      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions));
      expect(key('website-builtin-blocks'), findsOneWidget, reason: 'reopens in the visual editor');
      await tap(tester, key('website-builtin-revert'));
      await tap(tester, key('website-builtin-revert-confirm'));
      expect(key('website-builtin-convert'), findsOneWidget, reason: 'back to the comparison');
      await pumpSite(tester, route: '/admissions');
      expect(key('public-built-in-blocks-admissions'), findsNothing);
      expect(find.text('Join us'), findsNothing, reason: 'the draft headline was never published');
      expect(find.byKey(const Key('public-section-title')), findsOneWidget, reason: 'the built-in page again');
    });

    testWidgets('editor at phone width: comparison stacked, then Page / Structure / Edit tabs', (tester) async {
      await pumpAdmin(tester, WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.contact), s: const Size(390, 1600));
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(key('website-builtin-compare-blocks')).dy, greaterThan(tester.getTopLeft(key('website-builtin-compare-current')).dy));
      await tap(tester, key('website-builtin-convert'));
      expect(key('website-editor-tab-structure'), findsOneWidget);
      expect(key('website-builtin-more'), findsOneWidget, reason: 'less used actions in a menu');
      expect(tester.takeException(), isNull);
    });
  });

  // -------------------------------------------------------------- design

  group('design: palette colours, custom colours and overrides', () {
    test('palette: names and HEX values are validated; the site’s own colours stay; references resolve', () {
      final design = SiteDesign.defaults.copyWith(palette: [
        ...SiteDesign.defaults.palette,
        const DesignColor(id: 'c_brand', name: 'Brand teal', hex: '#0A7E8C'),
      ]);
      expect(design.validationErrors(), isEmpty);
      expect(design.resolve('token:c_brand'), const Color(0xFF0A7E8C));
      expect(design.resolve('#AABBCC'), const Color(0xFFAABBCC));
      expect(design.resolve('token:removed'), isNull);
      expect(design.describe('token:c_brand'), 'Brand teal');
      expect(SiteDesign.isColorValue('#12345'), isFalse);
      expect(BlockStyle.problem('textColor', 'red'), isNotNull);
      expect(BlockStyle.problem('textColor', '#123456'), isNull);
      expect(BlockStyle.problem('background', 'sage'), isNull, reason: 'the first background options stay valid');

      final bad = design.copyWith(palette: [for (final c in design.palette) if (c.id != 'forest') c.id == 'c_brand' ? c.copyWith(hex: 'teal') : c]);
      expect(bad.validationErrors().join(' '), allOf(contains('six hexadecimal digits'), contains('can’t be removed')));
      final round = SiteDesign.fromMap({...design.toMap(), 'futureToken': 'kept'});
      expect(round.toMap()['futureToken'], 'kept');
      expect(round.colorById('c_brand')!.hex, '#0A7E8C');
    });

    testWidgets('changing a palette colour changes everything using it; a custom colour stays; sections pass colours down', (tester) async {
      final blocks = BlockRegistry.parseList([
        {'id': 'b_token00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Token', 'ta': ''}, 'style': {'headingColor': 'token:forest'}},
        {'id': 'b_custom0001', 'type': 'text', 'v': 1, 'heading': {'en': 'Custom', 'ta': ''}, 'style': {'headingColor': '#AA0000'}},
        {'id': 'b_plain00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Plain', 'ta': ''}},
        {
          'id': 'b_sect000001', 'type': 'section', 'v': 1, 'layout': '1', 'style': {'headingColor': 'token:gold'},
          'columns': [{'id': 'c_one0000001', 'blocks': [
            {'id': 'b_inside0001', 'type': 'text', 'v': 1, 'heading': {'en': 'Inherits', 'ta': ''}},
            {'id': 'b_inside0002', 'type': 'text', 'v': 1, 'heading': {'en': 'Own', 'ta': ''}, 'style': {'headingColor': '#00AA00'}},
          ]}],
        },
      ]);
      Color? colorOf(String text) => tester.widget<Text>(find.text(text)).style?.color;
      Future<void> render(SiteDesign design) async {
        await size(tester, const Size(1400, 1600));
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WebsiteDesignScope(design: design, child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, fullBleed: true)),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }

      await render(SiteDesign.defaults);
      expect(colorOf('Token'), const Color(0xFF1F4D3A));
      expect(colorOf('Custom'), const Color(0xFFAA0000));
      expect(colorOf('Plain'), const Color(0xFF163829), reason: 'unset: the site’s heading colour');
      expect(colorOf('Inherits'), const Color(0xFFB8955A), reason: 'from the section');
      expect(colorOf('Own'), const Color(0xFF00AA00), reason: 'its own colour wins');

      final changed = SiteDesign.defaults.copyWith(palette: [
        for (final c in SiteDesign.defaults.palette)
          c.id == 'forest' ? c.copyWith(hex: '#3355FF') : c.id == 'gold' ? c.copyWith(hex: '#FF8800') : c.id == 'forestDark' ? c.copyWith(hex: '#111111') : c,
      ]);
      await render(changed);
      expect(colorOf('Token'), const Color(0xFF3355FF), reason: 'follows the palette');
      expect(colorOf('Custom'), const Color(0xFFAA0000), reason: 'a custom colour stays');
      expect(colorOf('Plain'), const Color(0xFF111111), reason: 'the site’s own heading colour is a palette colour too');
      expect(colorOf('Inherits'), const Color(0xFFFF8800));
      expect(colorOf('Own'), const Color(0xFF00AA00));
    });

    testWidgets('inspector: palette colour, custom HEX, reset to inherited', (tester) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour'), slug: 'tour');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
        'blocks': [{'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Hello', 'ta': 'வணக்கம்'}}],
      });
      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: created.id));
      StructuredBlock block() => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.single as StructuredBlock;
      await tap(tester, key('website-canvas-block-b_text000001'));
      const prefix = 'website-block-b_text000001-style-headingColor';
      expect(tester.widget<Text>(key('$prefix-value')).data, startsWith('Inherited'));

      await tap(tester, key('$prefix-choose'));
      await tap(tester, key('$prefix-token-gold'));
      expect(block().style['headingColor'], 'token:gold');
      expect(tester.widget<Text>(key('$prefix-value')).data, 'Gold');

      await tap(tester, key('$prefix-choose'));
      await type(tester, key('$prefix-hex'), '#12ab34');
      await tap(tester, key('$prefix-hex-apply'));
      expect(block().style['headingColor'], '#12AB34');
      expect(tester.widget<Text>(find.descendant(of: key('website-custom-preview'), matching: find.text('Hello'))).style?.color, const Color(0xFF12AB34));

      await tap(tester, key('$prefix-reset'));
      expect(block().style.containsKey('headingColor'), isFalse, reason: 'back to inherited');

      await tap(tester, key('$prefix-choose'));
      await type(tester, key('$prefix-hex'), '#12');
      expect(tester.widget<FilledButton>(key('$prefix-hex-apply')).onPressed, isNull, reason: 'an incomplete HEX can’t be used');
    });
  });

  // ---------------------------------------------------- header and footer

  group('header and footer', () {
    Future<void> publishLayout(SiteLayout Function(SiteLayout) change) async {
      final layout = change(SiteLayout.fromCurrentNavigation(const []));
      await service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: layout);
    }

    testWidgets('their look and contact details reach every page; a palette change reaches the footer', (tester) async {
      await publishLayout((l) => l.copyWith(
            // Two links: room for the button in the test font.
            mainNav: l.mainNav.take(2).toList(),
            design: SiteDesign.defaults.copyWith(palette: [for (final c in SiteDesign.defaults.palette) c.id == 'forestDark' ? c.copyWith(hex: '#222244') : c]),
            header: const SiteHeaderStyle(background: '#FFF7E0', ctaLabel: LocalizedText(en: 'Enquire', ta: 'விசாரிக்க'), ctaTarget: '/contact'),
            footer: const SiteFooterStyle(phone: '+91 44 1234 5678', email: 'office@example.org', address: LocalizedText(en: '1 School Road', ta: '1 பள்ளி சாலை')),
          ));
      for (final route in [null, '/admissions', '/gallery']) {
        await pumpSite(tester, route: route);
        final header = tester.widget<Container>(find.byKey(const Key('public-header')).last);
        expect((header.decoration! as BoxDecoration).color, const Color(0xFFFFF7E0), reason: route ?? '/');
        expect(find.text('Enquire'), findsOneWidget, reason: route ?? '/');
        expect(find.text('+91 44 1234 5678'), findsOneWidget);
        expect(find.text('1 School Road'), findsOneWidget);
        final footer = tester.widget<Container>(find.byKey(const Key('public-footer')).last);
        expect(footer.color, const Color(0xFF222244), reason: 'the footer uses the palette’s deep forest');
      }
      // On a phone the button is in the menu.
      await pumpSite(tester, route: '/programs', s: const Size(390, 2000));
      await tap(tester, key('public-menu-button'));
      expect(find.descendant(of: key('public-menu-header-button'), matching: find.text('Enquire')), findsOneWidget);
    });

    test('validation: colours, contact details and the header button link', () {
      final layout = SiteLayout.fromCurrentNavigation(const []);
      expect(layout.copyWith(header: const SiteHeaderStyle(background: 'blue')).validationErrors().join(), contains('Header background'));
      expect(layout.copyWith(header: const SiteHeaderStyle(ctaLabel: LocalizedText(en: 'Go'), ctaTarget: 'javascript:x')).validationErrors().join(), contains('Header button'));
      expect(layout.copyWith(header: const SiteHeaderStyle(ctaLabel: LocalizedText(en: 'Go'))).validationErrors().join(), contains('Choose where'));
      expect(layout.copyWith(footer: const SiteFooterStyle(email: 'nope')).validationErrors().join(), contains('email'));
      expect(layout.copyWith(footer: const SiteFooterStyle(phone: 'call us')).validationErrors().join(), contains('phone'));
      expect(layout.toMap().keys.toSet(), {'kind', 'schemaVersion', 'siteName', 'tagline', 'mainNav', 'footerNav', 'footerText', 'copyright'},
          reason: 'an unchanged design, header and footer are not stored');
    });

    testWidgets('layout editor: palette, header and footer saved and published; unknown keys kept in the draft', (tester) async {
      await firestore.collection(WebsiteCollections.pageDrafts).doc(SiteLayout.docId).set({
        ...SiteLayout.fromCurrentNavigation(const []).toMap(),
        'futureLayoutKey': {'kept': true},
      });
      await pumpAdmin(tester, WebsiteSiteLayoutEditorScreen(service: service, user: _admin));
      expect(key('website-layout-every-page'), findsOneWidget, reason: 'says the changes affect every page');

      await tap(tester, key('website-design-add-color'));
      final added = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.endsWith('-hex') && (w.key! as ValueKey<String>).value.startsWith('website-design-color-c'));
      await type(tester, added, '#0A7E8C');
      await tap(tester, key('website-header-background-choose'));
      await type(tester, key('website-header-background-hex'), '#FFF7E0');
      await tap(tester, key('website-header-background-hex-apply'));
      await type(tester, key('website-footer-phone'), '044 1234 5678');
      await type(tester, key('website-footer-address-ta'), 'பள்ளி சாலை');
      await type(tester, key('website-footer-address-en'), 'School Road');
      expect(find.descendant(of: key('website-layout-preview'), matching: find.text('044 1234 5678')), findsOneWidget, reason: 'previewed before publishing');

      await tap(tester, key('website-layout-save-draft'));
      final draft = (await doc(WebsiteCollections.pageDrafts, SiteLayout.docId))!;
      expect(draft['futureLayoutKey'], {'kept': true});
      expect((draft['header'] as Map)['background'], '#FFF7E0');
      expect((draft['footer'] as Map)['address'], {'en': 'School Road', 'ta': 'பள்ளி சாலை'});
      expect(((draft['design'] as Map)['palette'] as List).any((c) => (c as Map)['hex'] == '#0A7E8C'), isTrue);
      expect(await doc(WebsiteCollections.livePages, SiteLayout.docId), isNull, reason: 'nothing public yet');

      await tap(tester, key('website-layout-publish'));
      await tap(tester, key('website-layout-publish-confirm'));
      final live = (await doc(WebsiteCollections.livePages, SiteLayout.docId))!;
      expect(live.keys.toSet(), containsAll(['design', 'header', 'footer']));
      expect(live.containsKey('futureLayoutKey'), isFalse, reason: 'the live copy holds visitor-facing fields only');
      expect(live.keys.where((k) => k.startsWith('updatedBy')), isEmpty);
    });

    testWidgets('the page editor shows the real header and footer; clicking them explains they are shared', (tester) async {
      await publishLayout((l) => l.copyWith(footer: const SiteFooterStyle(email: 'office@example.org')));
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour'), slug: 'tour');
      await pumpAdmin(tester, WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: created.id));
      expect(find.descendant(of: key('website-canvas-site-footer'), matching: find.text('office@example.org')), findsOneWidget);
      await tap(tester, key('website-canvas-site-header'));
      expect(key('website-inspector-site-header'), findsOneWidget);
      expect(key('website-open-site-design'), findsOneWidget);
      expect(find.textContaining('shared by every page'), findsWidgets);
    });
  });
}
