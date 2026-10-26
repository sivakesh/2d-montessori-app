// Generic visual page editor (P2b), in the additional-page editor:
// - Pages made of sections open and save exactly as before; opening never
//   converts. Conversion is explicit: a preview, Cancel or Convert, then
//   Save draft (Discard changes undoes it). Converted pages keep their
//   sections copy exactly (round trip) and every language.
// - Blocks: add, edit, move, duplicate (fresh ids, nested too), hide/show,
//   delete (confirmed); unsupported blocks are locked and kept; unknown
//   fields and other languages survive editing.
// - Validation stops unsafe links; unpublished images are warned about and
//   publishing is refused; Discard changes drops unsaved edits.
// - Save and reload; the preview is the public renderer (published images
//   only), at desktop or mobile width; translation readiness is shown and
//   nothing is created for it.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/legacy_sections.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_custom_page.dart';
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

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

Object? _plain(Object? v) => jsonDecode(jsonEncode(v, toEncodable: (o) => o.toString()));

/// The stored content of a page document (bookkeeping fields left out).
Map<String, dynamic> _content(Map<String, dynamic> doc) =>
    {for (final e in doc.entries) if (!{'updatedAt', 'createdAt', 'updatedById', 'updatedByName', 'publishedAt'}.contains(e.key)) e.key: e.value};

const _sections = [
  {'id': 'lq3x9aaa', 'type': 'text', 'heading': {'en': 'Welcome', 'ta': 'வரவேற்பு', 'hi': 'स्वागत'}, 'body': {'en': 'We are a Montessori school.', 'ta': ''}},
  {'id': 'lq3x9bbb', 'type': 'image_text', 'heading': {'en': 'Garden', 'ta': ''}, 'body': {'en': 'Outdoor learning.', 'ta': ''}, 'mediaId': 'm1', 'imageOnRight': true},
  {'id': 'lq3x9ddd', 'type': 'cta', 'heading': {'en': 'Visit', 'ta': ''}, 'body': {'en': 'Come and see.', 'ta': ''}, 'buttonLabel': {'en': 'Book', 'ta': 'பதிவு'}, 'target': '/contact'},
];

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

  /// A page built with [blocks], or (without them) a page made of
  /// [sections] as pages were before the page builder.
  Future<String> page({List<Map<String, dynamic>> sections = const [], List<Object?>? blocks}) async {
    final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour'), slug: 'tour');
    await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
      'sections': sections,
      if (blocks != null) ...{'schemaVersion': 2, 'blocks': blocks} else ...{'schemaVersion': FieldValue.delete(), 'blocks': FieldValue.delete()},
    });
    return created.id;
  }

  Future<Map<String, dynamic>> draft(String id) async => (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!;

  Future<void> open(WidgetTester tester, String id, {Size size = const Size(1200, 4200)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
      child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: id)),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(Key(k));

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  /// The text field whose key starts with [prefix] (keys end with the
  /// editor's refill generation).
  Finder field(String prefix) => find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true);

  Future<void> type(WidgetTester tester, String prefix, String text) async {
    await tester.ensureVisible(field(prefix));
    await tester.pumpAndSettle();
    await tester.enterText(field(prefix), text);
    await tester.pumpAndSettle();
  }

  List<WebsiteBlock> editorBlocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;

  Future<void> addBlock(WidgetTester tester, String type, {String menu = 'website-blocks-add'}) async {
    await tap(tester, key(menu));
    await tester.tap(key('$menu-$type'));
    await tester.pumpAndSettle();
  }

  group('new pages', () {
    test('are created built with blocks (none yet) and an empty sections copy; existing pages are untouched', () async {
      final legacyId = await page(sections: _sections);
      final legacyBefore = await draft(legacyId);
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day', ta: 'திறந்த நாள்'), slug: 'open-day');
      expect(created.usesBlocks, isTrue);
      expect(created.blocks, isEmpty);
      final stored = await draft(created.id);
      expect(stored['schemaVersion'], 2);
      expect(stored['blocks'], isEmpty);
      expect(stored['sections'], isEmpty);
      expect(stored['title'], {'en': 'Open day', 'ta': 'திறந்த நாள்'});
      expect(stored['archived'], isFalse);
      expect((await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!.draft.usesBlocks, isTrue, reason: 'read back as a page built with blocks');

      final legacyAfter = await draft(legacyId);
      expect(_plain(legacyAfter), _plain(legacyBefore), reason: 'a page made of sections is not converted');
      expect(legacyAfter.containsKey('blocks'), isFalse);
      expect(legacyAfter.containsKey('schemaVersion'), isFalse);
    });

    testWidgets('open in the block editor with an empty state; adding a Text block and saving keeps it and its sections copy', (tester) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Open day'), slug: 'open-day');
      await open(tester, created.id);
      expect(key('website-custom-uses-blocks'), findsOneWidget);
      expect(key('website-custom-blocks'), findsOneWidget);
      expect(key('website-custom-add-section'), findsNothing, reason: 'not the sections editor');
      expect(key('website-custom-convert-offer'), findsNothing);
      expect(key('website-blocks-add-empty'), findsOneWidget);
      for (final type in ['text', 'image', 'columns', 'cta']) {
        expect(key('website-blocks-add-quick-$type'), findsOneWidget);
      }
      expect(key('website-blocks-add'), findsOneWidget, reason: 'every type is still in the Add block menu');
      expect(key('website-custom-unsaved'), findsNothing, reason: 'opening changes nothing');

      await tap(tester, key('website-blocks-add-quick-text'));
      expect(key('website-blocks-add-empty'), findsNothing);
      final textId = editorBlocks(tester).single.id;
      expect(textId, matches(RegExp(r'^b_[a-z0-9]{10}$')));
      await type(tester, 'website-block-$textId-heading-en', 'Welcome');
      await type(tester, 'website-block-$textId-body-ta', 'வரவேற்பு');
      await type(tester, 'website-block-$textId-body-en', 'Come and visit.');
      expect(find.descendant(of: key('website-custom-preview'), matching: find.text('Welcome')), findsOneWidget);

      await tap(tester, key('website-custom-save-draft'));
      final saved = await draft(created.id);
      expect(saved['schemaVersion'], 2);
      expect(_plain(saved['blocks']), [
        {'id': textId, 'type': 'text', 'v': 1, 'heading': {'en': 'Welcome', 'ta': ''}, 'body': {'en': 'Come and visit.', 'ta': 'வரவேற்பு'}},
      ]);
      expect(_plain(saved['sections']), [
        {'id': textId, 'type': 'text', 'heading': {'en': 'Welcome', 'ta': ''}, 'body': {'en': 'Come and visit.', 'ta': 'வரவேற்பு'}},
      ], reason: 'the sections copy for older versions, derived from the blocks');
      await open(tester, created.id);
      expect([for (final b in editorBlocks(tester)) b.id], [textId], reason: 'reloads');
    });
  });

  group('pages made of sections', () {
    testWidgets('open and save exactly as before; opening never converts', (tester) async {
      final id = await page(sections: _sections);
      final before = _content(await draft(id));
      await open(tester, id);
      expect(_content(await draft(id)), before, reason: 'opening writes nothing');
      expect(key('website-custom-blocks'), findsNothing);
      expect(key('website-custom-add-section'), findsOneWidget);
      expect(key('website-custom-convert'), findsOneWidget);
      await tap(tester, key('website-custom-save-draft'));
      final after = _content(await draft(id));
      expect(after.containsKey('blocks') || after.containsKey('schemaVersion'), isFalse);
      expect(_plain(after['sections']), _plain(_sections));
    });

    testWidgets('conversion: preview, cancel, convert, discard, convert again and save — sections copy unchanged, languages kept', (tester) async {
      final id = await page(sections: _sections);
      await open(tester, id);
      await tap(tester, key('website-custom-convert'));
      expect(key('website-custom-convert-preview'), findsOneWidget);
      expect(find.descendant(of: key('website-custom-convert-preview'), matching: find.text('Welcome')), findsOneWidget);
      expect(find.descendant(of: key('website-custom-convert-preview'), matching: find.byType(WebsiteBlocksView)), findsOneWidget);
      await tap(tester, key('website-custom-convert-cancel'));
      expect(key('website-custom-blocks'), findsNothing, reason: 'cancelled');

      await tap(tester, key('website-custom-convert'));
      await tap(tester, key('website-custom-convert-confirm'));
      expect(key('website-custom-blocks'), findsOneWidget);
      expect([for (final b in editorBlocks(tester)) b.id], ['lq3x9aaa', 'lq3x9bbb', 'lq3x9ddd'], reason: 'section ids kept');
      expect(key('website-custom-unsaved'), findsOneWidget);
      expect((await draft(id)).containsKey('blocks'), isFalse, reason: 'nothing saved yet');

      await tap(tester, key('website-custom-discard'));
      await tap(tester, key('website-custom-discard-confirm'));
      expect(key('website-custom-blocks'), findsNothing, reason: 'discarded');
      expect(key('website-custom-add-section'), findsOneWidget);

      await tap(tester, key('website-custom-convert'));
      await tap(tester, key('website-custom-convert-confirm'));
      await tap(tester, key('website-custom-save-draft'));
      final saved = await draft(id);
      expect(saved['schemaVersion'], 2);
      expect(_plain(saved['sections']), _plain(_sections), reason: 'the sections copy is exactly the original sections');
      expect((saved['blocks'] as List).first['heading'], {'en': 'Welcome', 'ta': 'வரவேற்பு', 'hi': 'स्वागत'});

      await open(tester, id);
      expect([for (final b in editorBlocks(tester)) b.id], ['lq3x9aaa', 'lq3x9bbb', 'lq3x9ddd'], reason: 'reloads as blocks');
      expect(key('website-custom-convert'), findsNothing);
    });

    test('round trips: sections → blocks → sections, and convertible blocks → sections → blocks', () {
      final legacy = CustomPage.fromMap('p', {'kind': 'custom', 'slug': 'tour', 'title': {'en': 'Tour'}, 'sections': _sections});
      final converted = legacy.convertedToBlocks();
      expect(_plain(converted.toContentMap()['sections']), _plain(legacy.toContentMap()['sections']));
      final again = LegacySections.toBlocks(LegacySections.mirror(converted.blocks!));
      expect(_plain(BlockRegistry.toMapList(again)), _plain(BlockRegistry.toMapList(converted.blocks!)));
      final withOthers = converted.copyWith(blocks: () => [
            ...converted.blocks!,
            BlockRegistry.create(BlockRegistry.divider),
            (BlockRegistry.create(BlockRegistry.text).withValue('heading', const LocalizedText(en: 'Hidden'))).copyWith(hidden: true),
          ]);
      expect((withOthers.toContentMap()['sections'] as List), hasLength(3), reason: 'blocks without a section form, and hidden ones, are left out of the copy');
    });
  });

  group('blocks', () {
    testWidgets('add, edit, move, hide/show, delete (confirmed), save and reload', (tester) async {
      final id = await page(blocks: const []);
      await open(tester, id);
      await addBlock(tester, 'text');
      await addBlock(tester, 'divider');
      final textId = editorBlocks(tester)[0].id;
      final dividerId = editorBlocks(tester)[1].id;
      expect(textId, matches(RegExp(r'^b_[a-z0-9]{10}$')));
      await tap(tester, key('website-block-$textId-edit'));
      await type(tester, 'website-block-$textId-heading-en', 'Our day');
      await type(tester, 'website-block-$textId-body-en', 'Our routine');
      await type(tester, 'website-block-$textId-body-ta', 'எங்கள் நாள்');
      expect((editorBlocks(tester)[0] as StructuredBlock).text('heading').en, 'Our day');

      await tap(tester, key('website-block-$dividerId-up'));
      expect([for (final b in editorBlocks(tester)) b.id], [dividerId, textId]);
      await tap(tester, key('website-block-$textId-up'));
      expect([for (final b in editorBlocks(tester)) b.id], [textId, dividerId]);

      await tap(tester, key('website-block-$textId-visibility'));
      expect(key('website-block-$textId-hidden'), findsOneWidget);
      expect(find.descendant(of: key('website-custom-preview'), matching: key('public-block-$textId')), findsNothing, reason: 'hidden from the preview, as from visitors');
      await tap(tester, key('website-block-$textId-visibility'));
      expect(find.descendant(of: key('website-custom-preview'), matching: find.text('Our day')), findsOneWidget);

      await tap(tester, key('website-block-$dividerId-delete'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editorBlocks(tester), hasLength(2), reason: 'cancelled');
      await tap(tester, key('website-block-$dividerId-delete'));
      await tap(tester, key('website-block-delete-confirm'));
      expect(editorBlocks(tester), hasLength(1));

      await tap(tester, key('website-custom-save-draft'));
      final saved = await draft(id);
      expect((saved['blocks'] as List).single['heading'], {'en': 'Our day', 'ta': ''});
      expect((saved['blocks'] as List).single['body'], {'en': 'Our routine', 'ta': 'எங்கள் நாள்'});
      expect(_plain(saved['sections']), [
        {'id': textId, 'type': 'text', 'heading': {'en': 'Our day', 'ta': ''}, 'body': {'en': 'Our routine', 'ta': 'எங்கள் நாள்'}},
      ], reason: 'the sections copy, derived from the blocks');
      await open(tester, id);
      expect([for (final b in editorBlocks(tester)) b.id], [textId], reason: 'reloads');
    });

    testWidgets('duplicate gives fresh ids to the block, its items, its columns and nested blocks', (tester) async {
      final id = await page(blocks: [
        {
          'id': 'b_cols000001', 'type': 'columns', 'v': 1, 'layout': '1:1',
          'columns': [
            {'id': 'c_one0000001', 'blocks': [{'id': 'b_inner00001', 'type': 'buttons', 'v': 1, 'buttons': [{'id': 'i_btn0000001', 'label': {'en': 'Visit', 'ta': ''}, 'target': '/contact'}]}]},
            {'id': 'c_two0000001', 'blocks': [{'id': 'b_inner00002', 'type': 'text', 'v': 1, 'heading': {'en': 'Right', 'ta': ''}}]},
          ],
        },
      ]);
      await open(tester, id);
      await tap(tester, key('website-block-b_cols000001-duplicate'));
      final blocks = editorBlocks(tester);
      expect(blocks, hasLength(2));
      final copy = blocks[1] as StructuredBlock;
      final cols = copy.columns('columns');
      final inner = cols[0].blocks.single as StructuredBlock;
      final ids = {copy.id, for (final c in cols) c.id, for (final c in cols) for (final b in c.blocks) b.id, inner.items('buttons').single.id};
      expect(ids.intersection({'b_cols000001', 'c_one0000001', 'c_two0000001', 'b_inner00001', 'b_inner00002', 'i_btn0000001'}), isEmpty);
      expect(inner.items('buttons').single.text('label').en, 'Visit');
      expect(BlockRegistry.validate(blocks), isEmpty);

      // Nested editing: add a divider to the copy's first column.
      await addBlock(tester, 'divider', menu: 'website-column-${cols[0].id}-add');
      expect(((editorBlocks(tester)[1] as StructuredBlock).columns('columns')[0].blocks), hasLength(2));
      await tap(tester, key('website-custom-save-draft'));
      await open(tester, id);
      expect(editorBlocks(tester), hasLength(2), reason: 'saved and reloaded');
    });

    testWidgets('unsupported blocks are locked and kept; unknown fields and other languages survive edits', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': 'பற்றி', 'hi': 'परिचय'}, 'body': {'en': '', 'ta': ''}, 'futureKey': {'a': 1}},
        {'id': 'b_future0001', 'type': 'carousel', 'v': 3, 'slides': [{'id': 's1', 'title': {'en': 'One'}}]},
      ]);
      await open(tester, id);
      expect(key('website-block-b_future0001-locked'), findsOneWidget);
      expect(key('website-block-b_future0001-edit'), findsNothing);
      expect(key('website-block-b_future0001-duplicate'), findsNothing);
      await tap(tester, key('website-block-b_text000001-edit'));
      await type(tester, 'website-block-b_text000001-heading-en', 'About us');
      await tap(tester, key('website-custom-save-draft'));
      final blocks = (await draft(id))['blocks'] as List;
      expect(blocks[0]['heading'], {'en': 'About us', 'ta': 'பற்றி', 'hi': 'परिचय'});
      expect(blocks[0]['futureKey'], {'a': 1});
      expect(_plain(blocks[1]), {'id': 'b_future0001', 'type': 'carousel', 'v': 3, 'slides': [{'id': 's1', 'title': {'en': 'One'}}]});
      expect(key('website-custom-warnings'), findsOneWidget);
      expect(find.textContaining('1 unsupported block(s)'), findsOneWidget);
    });

    testWidgets('unsafe links stop saving; unpublished images are warned about and stop publishing; Discard drops edits', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Hello', 'ta': ''}},
      ]);
      final before = _content(await draft(id));
      await open(tester, id);
      await addBlock(tester, 'buttons');
      final buttonsId = editorBlocks(tester).last.id;
      final itemId = (editorBlocks(tester).last as StructuredBlock).items('buttons').single.id;
      await type(tester, 'website-block-$buttonsId-buttons-item-$itemId-label-en', 'Click');
      await type(tester, 'website-block-$buttonsId-buttons-item-$itemId-target', 'javascript:alert(1)');
      expect(key('website-custom-errors'), findsOneWidget);
      expect(find.descendant(of: key('website-custom-preview'), matching: find.text('Click')), findsNothing, reason: 'an unsafe link is never shown');
      await tap(tester, key('website-custom-save-draft'));
      expect(_content(await draft(id)), before, reason: 'refused');
      await type(tester, 'website-block-$buttonsId-buttons-item-$itemId-target', 'https://2dmontessori.com/#/app');
      expect(find.textContaining('protected part of the app'), findsWidgets);

      await type(tester, 'website-block-$buttonsId-buttons-item-$itemId-target', '/admissions');
      expect(key('website-custom-errors'), findsNothing);
      await addBlock(tester, 'image');
      final imageId = editorBlocks(tester).last.id;
      await tap(tester, key('website-block-$imageId-mediaId-choose'));
      await tester.tap(key('website-choose-m2'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('website-block-$imageId-mediaId-status')).data, contains('Not published'));
      expect(find.textContaining('aren’t published'), findsOneWidget);
      expect(find.descendant(of: key('website-custom-preview'), matching: key('public-block-$imageId')), findsNothing, reason: 'visitors wouldn’t see it');
      await tap(tester, key('website-custom-publish'));
      expect((await firestore.collection(WebsiteCollections.livePages).doc(id).get()).exists, isFalse, reason: 'publishing refused');

      await tap(tester, key('website-custom-discard'));
      await tap(tester, key('website-custom-discard-confirm'));
      expect(editorBlocks(tester), hasLength(1));
    });

    testWidgets('the preview is the public renderer with published images, at desktop or mobile width; readiness shown, nothing created', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': 'பற்றி'}, 'body': {'en': 'Body', 'ta': ''}},
        {'id': 'b_image00001', 'type': 'image', 'v': 1, 'mediaId': 'm1'},
        {'id': 'b_image00002', 'type': 'image', 'v': 1, 'mediaId': 'm2'},
      ]);
      await open(tester, id);
      // The canvas draws each block with the public renderer, with the
      // published images only, as visitors see them.
      final views = tester.widgetList<WebsiteBlocksView>(find.descendant(of: key('website-custom-preview'), matching: find.byType(WebsiteBlocksView))).toList();
      expect([for (final v in views) for (final b in v.blocks) b.id], ['b_text000001', 'b_image00001']);
      expect({for (final v in views) ...v.media.keys}, {'m1'}, reason: 'published images only, as visitors');
      expect(find.descendant(of: key('website-custom-preview'), matching: key('public-block-b_image00001')), findsOneWidget);
      expect(find.descendant(of: key('website-custom-preview'), matching: key('public-block-b_image00002')), findsNothing);
      expect(key('website-canvas-placeholder-b_image00002'), findsOneWidget, reason: 'shown to the admin as a placeholder, not left out');

      // Preview: the page exactly as visitors see it (the public page body).
      await tap(tester, key('website-custom-preview-toggle'));
      final body = tester.widget<PublicCustomPageBody>(find.descendant(of: key('website-custom-preview'), matching: find.byType(PublicCustomPageBody)));
      expect(_plain(BlockRegistry.toMapList(body.page.blocks!)), _plain(BlockRegistry.toMapList(editorBlocks(tester))));
      expect(key('website-canvas-placeholder-b_image00002'), findsNothing);
      expect(key('website-editor-structure'), findsNothing, reason: 'no editing panels in the preview');
      await tap(tester, key('website-custom-preview-toggle'));

      await tap(tester, key('website-custom-preview-mobile'));
      expect(tester.getSize(key('website-custom-preview-mobile-frame')).width, 390);

      expect(tester.widget<Text>(key('website-custom-readiness-ta')).data, startsWith('Tamil: 1 of 3 texts have Tamil text (required: 1 of 2)'));
      expect((await firestore.collection('website_translation_drafts').get()).docs, isEmpty);
      expect((await firestore.collection('website_translations').get()).docs, isEmpty);
    });

    testWidgets('responsive: the editor works at phone width', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': ''}},
      ]);
      await open(tester, id, size: const Size(390, 6000));
      expect(tester.takeException(), isNull);
      await tap(tester, find.byKey(const Key('website-editor-tab-structure')));
      await tap(tester, key('website-block-b_text000001-edit'));
      await type(tester, 'website-block-b_text000001-heading-en', 'About us');
      expect(tester.takeException(), isNull);
      expect((editorBlocks(tester).single as StructuredBlock).text('heading').en, 'About us');
    });
  });
}
