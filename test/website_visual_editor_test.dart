// The page builder's visual editor (structure, canvas, properties):
// - BlockListOps: insert, move, duplicate, hide and remove at the top level
//   and inside columns; untouched blocks (unknown fields, other languages,
//   unsupported blocks) are kept as they are; limits are respected.
// - Selecting a block on the canvas or in the structure shows its
//   properties; the page header (or "Page settings") shows the page's.
// - The canvas toolbar and keyboard move, duplicate, hide and delete
//   (confirmed); `+` points insert where they are.
// - Blocks visitors wouldn't see are placeholders on the canvas.
// - Blocks inside columns are added in the structure and selected there or
//   from the columns block's properties.
// - English and Tamil are edited; the canvas follows the chosen language;
//   other languages are kept.
// - Desktop: three panels; medium: side panels shown and hidden; narrow:
//   Page, Structure and Edit tabs.
// - Pages made of sections keep the form editor.
// - Desktop draws the page at a desktop width, scaled to fit; blocks inside
//   columns that visitors wouldn't see are explained; a selected child
//   hides its columns block's whole-block actions; on a phone, the less
//   used toolbar actions are in a More menu.
// - The sections copy for older versions leaves out columns blocks with a
//   hidden block inside, and ignores styles that only spell out defaults.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/block_list_ops.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_limits.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/legacy_sections.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/public_website_theme.dart';

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

const _columns = {
  'id': 'b_cols000001', 'type': 'columns', 'v': 1, 'layout': '1:1',
  'columns': [
    {'id': 'c_one0000001', 'blocks': [{'id': 'b_inner00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Left', 'ta': ''}}]},
    {'id': 'c_two0000001', 'blocks': []},
  ],
};

void main() {
  group('BlockListOps', () {
    List<WebsiteBlock> blocks() => BlockRegistry.parseList([
          {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'One', 'ta': 'ஒன்று', 'hi': 'एक'}, 'futureKey': 1},
          _columns,
          {'id': 'b_future0001', 'type': 'carousel', 'v': 9, 'slides': []},
        ]);

    test('at, walk and siblings reach blocks inside columns', () {
      final list = blocks();
      expect(BlockListOps.at(list, const BlockPath.nested(1, 0, 0))!.id, 'b_inner00001');
      expect(BlockListOps.at(list, const BlockPath.nested(1, 1, 0)), isNull);
      expect(BlockListOps.at(list, const BlockPath(5)), isNull);
      expect([for (final (p, b) in BlockListOps.walk(list)) '${b.id}@$p'],
          ['b_text000001@BlockPath(0)', 'b_cols000001@BlockPath(1)', 'b_inner00001@BlockPath(1, 0, 0)', 'b_future0001@BlockPath(2)']);
    });

    test('move, duplicate, hide and remove keep every other block exactly', () {
      final list = blocks();
      final before = _plain(BlockRegistry.toMapList(list));
      final (moved, to) = BlockListOps.move(list, const BlockPath(2), -2);
      expect(to, const BlockPath(0));
      expect([for (final b in moved) b.id], ['b_future0001', 'b_text000001', 'b_cols000001']);
      expect(identical(moved[1], list[0]), isTrue, reason: 'untouched blocks are the same objects');
      expect(BlockListOps.move(list, const BlockPath(0), -1).$1, same(list), reason: 'can’t move past the start');

      final (copied, copyAt) = BlockListOps.duplicate(list, const BlockPath.nested(1, 0, 0));
      expect(copyAt, const BlockPath.nested(1, 0, 1));
      final column = BlockListOps.columnsOf(copied[1])[0].blocks;
      expect(column, hasLength(2));
      expect(column[1].id, isNot('b_inner00001'));
      expect((column[1] as StructuredBlock).text('heading').en, 'Left');

      final hidden = BlockListOps.toggleHidden(list, const BlockPath(0));
      expect((hidden[0] as StructuredBlock).hidden, isTrue);
      expect((hidden[0] as StructuredBlock).text('heading').values['hi'], 'एक');
      expect(hidden[0].toMap()['futureKey'], 1, reason: 'unknown fields kept');
      expect(BlockListOps.toggleHidden(list, const BlockPath(2)), same(list), reason: 'unsupported blocks unchanged');

      final removed = BlockListOps.remove(list, const BlockPath.nested(1, 0, 0));
      expect(BlockListOps.columnsOf(removed[1])[0].blocks, isEmpty);
      expect(_plain(BlockRegistry.toMapList(list)), before, reason: 'the original list is never changed');
      expect(_plain(removed[2].toMap()), {'id': 'b_future0001', 'type': 'carousel', 'v': 9, 'slides': []});
    });

    test('limits: page and column room; no duplicate past the limit; unsupported blocks are not duplicated', () {
      final list = blocks();
      expect(BlockListOps.pageHasRoom(list), isTrue);
      expect(BlockListOps.pageHasRoom(list, limits: const BlockLimits(maxBlocks: 4)), isFalse);
      expect(BlockListOps.columnHasRoom(list, 1, 0, limits: const BlockLimits(maxColumnBlocks: 1)), isFalse);
      expect(BlockListOps.columnHasRoom(list, 1, 1, limits: const BlockLimits(maxColumnBlocks: 1)), isTrue);
      expect(BlockListOps.canDuplicate(list, const BlockPath(1), limits: const BlockLimits(maxBlocks: 5)), isFalse, reason: 'a copy counts its nested blocks');
      expect(BlockListOps.canDuplicate(list, const BlockPath(2)), isFalse);
    });
  });

  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    await firestore.collection(WebsiteCollections.media).doc('m1').set({
      'url': 'https://example.test/m1.jpg',
      'storagePath': 'website_media/m1/d.jpg',
      'status': 'published',
      'consentConfirmed': true,
      'alt': {'en': 'Alt m1', 'ta': ''},
      'caption': {'en': '', 'ta': ''},
    });
  });

  /// A page built with [blocks], or (without them) a page made of
  /// [sections].
  Future<String> page({List<Object?>? blocks, List<Map<String, dynamic>> sections = const []}) async {
    final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour', ta: 'சுற்றுலா'), slug: 'tour');
    await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
      'sections': sections,
      if (blocks != null) ...{'schemaVersion': 2, 'blocks': blocks} else ...{'schemaVersion': FieldValue.delete(), 'blocks': FieldValue.delete()},
    });
    return created.id;
  }

  Future<Map<String, dynamic>> draft(String id) async => (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!;

  Future<void> open(WidgetTester tester, String id, {Size size = const Size(1400, 2400)}) async {
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
  Finder onCanvas(Finder f) => find.descendant(of: key('website-custom-preview'), matching: f);

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Finder field(String prefix) => find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true);

  Future<void> type(WidgetTester tester, String prefix, String text) async {
    await tester.ensureVisible(field(prefix));
    await tester.pumpAndSettle();
    await tester.enterText(field(prefix), text);
    await tester.pumpAndSettle();
  }

  List<WebsiteBlock> editorBlocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
  List<String> ids(WidgetTester tester) => [for (final b in editorBlocks(tester)) b.id];

  Future<void> pick(WidgetTester tester, String menu, String type) async {
    await tap(tester, key(menu));
    await tester.tap(key('$menu-$type'));
    await tester.pumpAndSettle();
  }

  group('selection and properties', () {
    testWidgets('three panels; selecting on the canvas shows that block’s properties; the header or Page settings shows the page’s', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': ''}},
        {'id': 'b_text000002', 'type': 'text', 'v': 1, 'heading': {'en': 'Visit', 'ta': ''}},
      ]);
      await open(tester, id);
      expect(key('website-editor-structure'), findsOneWidget);
      expect(key('website-custom-preview'), findsOneWidget);
      expect(key('website-editor-properties'), findsOneWidget);
      expect(key('website-custom-title-en'), findsOneWidget, reason: 'nothing selected: page settings');
      expect(key('website-canvas-toolbar-b_text000001'), findsNothing);

      await tap(tester, key('website-canvas-block-b_text000002'));
      expect(key('website-canvas-toolbar-b_text000002'), findsOneWidget, reason: 'selected: outline and toolbar');
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Text');
      expect(field('website-block-b_text000002-heading-en'), findsOneWidget);
      expect(field('website-block-b_text000001-heading-en'), findsNothing, reason: 'only the selected block’s settings');
      expect(key('website-custom-title-en'), findsNothing);

      await type(tester, 'website-block-b_text000002-heading-en', 'Visit us');
      expect(onCanvas(find.text('Visit us')), findsOneWidget, reason: 'the canvas updates as you type');
      expect(key('website-custom-unsaved'), findsOneWidget);

      await tap(tester, key('website-block-b_text000001-select'));
      expect(field('website-block-b_text000001-heading-en'), findsOneWidget, reason: 'selected in the structure');
      await tap(tester, key('website-canvas-page-header'));
      expect(key('website-custom-title-en'), findsOneWidget);
      await tap(tester, key('website-block-b_text000002-select'));
      await tap(tester, key('website-inspector-close'));
      expect(key('website-custom-title-en'), findsOneWidget);

      await tap(tester, key('website-custom-save-draft'));
      expect(((await draft(id))['blocks'] as List)[1]['heading'], {'en': 'Visit us', 'ta': ''});
    });

    testWidgets('canvas toolbar: move, duplicate, hide/show and delete (confirmed); each selects the block it acted on', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'One', 'ta': ''}},
        {'id': 'b_text000002', 'type': 'text', 'v': 1, 'heading': {'en': 'Two', 'ta': ''}},
      ]);
      await open(tester, id);
      await tap(tester, key('website-canvas-block-b_text000002'));
      await tap(tester, key('website-canvas-b_text000002-up'));
      expect(ids(tester), ['b_text000002', 'b_text000001']);
      expect(key('website-canvas-toolbar-b_text000002'), findsOneWidget, reason: 'still selected after moving');

      await tap(tester, key('website-canvas-b_text000002-duplicate'));
      expect(editorBlocks(tester), hasLength(3));
      final copy = editorBlocks(tester)[1];
      expect(copy.id, isNot('b_text000002'));
      expect(key('website-canvas-toolbar-${copy.id}'), findsOneWidget, reason: 'the copy is selected');

      await tap(tester, key('website-canvas-${copy.id}-visibility'));
      expect(key('website-canvas-placeholder-${copy.id}'), findsOneWidget, reason: 'hidden: a placeholder, not left out');
      expect(key('website-block-${copy.id}-hidden'), findsOneWidget);
      expect(onCanvas(key('public-block-${copy.id}')), findsNothing);
      await tap(tester, key('website-canvas-${copy.id}-visibility'));
      expect(onCanvas(key('public-block-${copy.id}')), findsOneWidget);

      await tap(tester, key('website-canvas-${copy.id}-delete'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editorBlocks(tester), hasLength(3), reason: 'cancelled');
      await tap(tester, key('website-canvas-${copy.id}-delete'));
      await tap(tester, key('website-block-delete-confirm'));
      expect(ids(tester), ['b_text000002', 'b_text000001']);
      expect(key('website-custom-title-en'), findsOneWidget, reason: 'nothing selected after deleting');
    });

    testWidgets('keyboard: a focused canvas block is selected with Enter and deleted with Delete (confirmed)', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'One', 'ta': ''}},
      ]);
      await open(tester, id);
      final ink = tester.widget<InkWell>(key('website-canvas-block-b_text000001'));
      expect(ink.onTap, isNotNull);
      Focus.of(tester.element(find.descendant(of: key('website-canvas-block-b_text000001'), matching: find.byType(Container)).first)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(key('website-canvas-toolbar-b_text000001'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(key('website-block-delete-confirm'), findsOneWidget, reason: 'asks first');
      await tap(tester, key('website-block-delete-confirm'));
      expect(editorBlocks(tester), isEmpty);
    });
  });

  group('adding and placeholders', () {
    testWidgets('insertion points add a block where they are; Add block adds after the selected one', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'One', 'ta': ''}},
        {'id': 'b_text000002', 'type': 'text', 'v': 1, 'heading': {'en': 'Two', 'ta': ''}},
      ]);
      await open(tester, id);
      await pick(tester, 'website-canvas-insert-1', 'divider');
      expect(editorBlocks(tester).map((b) => b.type), ['text', 'divider', 'text']);
      final divider = editorBlocks(tester)[1].id;
      expect(key('website-canvas-toolbar-$divider'), findsOneWidget, reason: 'the new block is selected');
      expect(key('website-block-$divider-size'), findsOneWidget, reason: 'and its properties shown');

      await pick(tester, 'website-canvas-insert-0', 'buttons');
      expect(editorBlocks(tester).first.type, 'buttons');
      await tap(tester, key('website-block-b_text000002-select'));
      await pick(tester, 'website-blocks-add', 'image');
      expect(editorBlocks(tester).map((b) => b.type), ['buttons', 'text', 'divider', 'text', 'image']);
    });

    testWidgets('placeholders: unsupported, invalid, no image, empty columns; visitors’ texts never leak from invalid blocks', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_future0001', 'type': 'carousel', 'v': 3},
        {'id': 'b_btns000001', 'type': 'buttons', 'v': 1, 'buttons': [{'id': 'i_btn0000001', 'label': {'en': 'Secret', 'ta': ''}, 'target': 'javascript:alert(1)'}]},
        {'id': 'b_image00001', 'type': 'image', 'v': 1, 'mediaId': ''},
        {'id': 'b_cols000002', 'type': 'columns', 'v': 1, 'layout': '1:1', 'columns': [{'id': 'c_a000000001', 'blocks': []}, {'id': 'c_b000000001', 'blocks': []}]},
        {'id': 'b_image00002', 'type': 'image', 'v': 1, 'mediaId': 'm1'},
      ]);
      await open(tester, id);
      for (final b in ['b_future0001', 'b_btns000001', 'b_image00001']) {
        expect(key('website-canvas-placeholder-$b'), findsOneWidget, reason: b);
      }
      // Empty columns: drawn with an "Add a block" button in each column.
      expect(key('website-canvas-column-c_a000000001-add'), findsOneWidget);
      expect(key('website-canvas-column-c_b000000001-add'), findsOneWidget);
      expect(key('website-canvas-placeholder-b_image00002'), findsNothing);
      expect(onCanvas(key('public-block-b_image00002')), findsOneWidget);
      expect(onCanvas(find.text('Secret')), findsNothing);
      expect(onCanvas(find.textContaining('Unsupported block')), findsOneWidget);
      expect(onCanvas(find.textContaining('Choose an image')), findsOneWidget, reason: 'an image block needs an image');
      expect(key('website-block-b_btns000001-problems'), findsOneWidget);

      await tap(tester, key('website-editor-first-problem'));
      expect(key('website-inspector-problems'), findsOneWidget);
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Buttons');

      await tap(tester, key('website-canvas-block-b_future0001'));
      expect(key('website-inspector-locked'), findsOneWidget, reason: 'unsupported blocks are locked');
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('an empty page: the empty state on the canvas; Add block starts it', (tester) async {
      final id = await page(blocks: const []);
      await open(tester, id);
      expect(onCanvas(key('website-blocks-add-empty')), findsOneWidget);
      await tap(tester, key('website-blocks-add-quick-columns'));
      expect(editorBlocks(tester).single.type, 'columns');
      expect(key('website-blocks-add-empty'), findsNothing);
    });
  });

  group('columns', () {
    testWidgets('blocks inside columns: added in the structure, selected there or from the columns block, edited and saved', (tester) async {
      final id = await page(blocks: [_columns]);
      await open(tester, id);
      await pick(tester, 'website-column-c_two0000001-add', 'divider');
      final divider = BlockListOps.columnsOf(editorBlocks(tester).single)[1].blocks.single;
      expect(divider.type, 'divider');
      expect(key('website-block-${divider.id}-size'), findsOneWidget, reason: 'the new block is selected');
      expect(key('website-column-c_two0000001-add-columns'), findsNothing, reason: 'no columns inside columns');

      await tap(tester, key('website-inspector-parent'));
      expect(tester.widget<Text>(key('website-inspector-title')).data, 'Columns');
      await tap(tester, key('website-column-c_one0000001-select-0'));
      await type(tester, 'website-block-b_inner00001-heading-en', 'Left side');
      expect(onCanvas(find.text('Left side')), findsOneWidget);

      await tap(tester, key('website-custom-save-draft'));
      final saved = ((await draft(id))['blocks'] as List).single as Map;
      expect(((saved['columns'] as List)[0]['blocks'] as List).single['heading'], {'en': 'Left side', 'ta': ''});
      expect(((saved['columns'] as List)[1]['blocks'] as List).single['type'], 'divider');
    });

    testWidgets('a block inside a column is moved: the order changes in the editor and is saved', (tester) async {
      final id = await page(blocks: [_columns]);
      await open(tester, id);
      await pick(tester, 'website-column-c_one0000001-add', 'divider');
      List<String> firstColumn() => [for (final b in BlockListOps.columnsOf(editorBlocks(tester).single)[0].blocks) b.id];
      final divider = firstColumn()[1];
      expect(firstColumn(), ['b_inner00001', divider]);
      expect(tester.widget<IconButton>(find.descendant(of: key('website-block-b_inner00001-down'), matching: find.byType(IconButton))).onPressed, isNotNull,
          reason: 'there is somewhere to move it');

      await tap(tester, key('website-block-b_inner00001-down'));
      expect(firstColumn(), [divider, 'b_inner00001']);
      expect(tester.widget<IconButton>(find.descendant(of: key('website-block-b_inner00001-down'), matching: find.byType(IconButton))).onPressed, isNull,
          reason: 'now last in its column');
      await tap(tester, key('website-block-b_inner00001-up'));
      await tap(tester, key('website-block-b_inner00001-down'));
      expect(firstColumn(), [divider, 'b_inner00001']);

      await tap(tester, key('website-custom-save-draft'));
      final saved = ((await draft(id))['blocks'] as List).single as Map;
      final stored = ((saved['columns'] as List)[0]['blocks'] as List).cast<Map>();
      expect([for (final b in stored) b['id']], [divider, 'b_inner00001']);
      expect(stored[1]['heading'], {'en': 'Left', 'ta': ''}, reason: 'moved with its content');
      await open(tester, id);
      expect(firstColumn(), [divider, 'b_inner00001'], reason: 'reloads in the saved order');
    });

    testWidgets('with a block inside selected, the columns block keeps its outline but not its whole-block toolbar or keys', (tester) async {
      final id = await page(blocks: [_columns]);
      await open(tester, id);
      await tap(tester, key('website-block-b_inner00001-select'));
      expect(field('website-block-b_inner00001-heading-en'), findsOneWidget, reason: 'the child’s properties');
      expect(key('website-canvas-child-selected-b_cols000001'), findsOneWidget);
      expect(key('website-canvas-toolbar-b_cols000001'), findsNothing);
      expect(key('website-canvas-b_cols000001-delete'), findsNothing);
      expect(key('website-canvas-b_cols000001-duplicate'), findsNothing);

      // Delete on the focused columns block does nothing while a child is
      // the selection.
      Focus.of(tester.element(find.descendant(of: key('website-canvas-block-b_cols000001'), matching: find.byType(Container)).first)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(key('website-block-delete-confirm'), findsNothing);
      expect(editorBlocks(tester), hasLength(1));

      await tap(tester, key('website-inspector-parent'));
      expect(key('website-canvas-toolbar-b_cols000001'), findsOneWidget, reason: 'the columns block itself selected again');
      expect(key('website-canvas-child-selected-b_cols000001'), findsNothing);
    });

    testWidgets('blocks inside columns that visitors wouldn’t see are explained on the canvas; nothing stored changes', (tester) async {
      final id = await page(blocks: [
        {
          'id': 'b_cols000001', 'type': 'columns', 'v': 1, 'layout': '1:1',
          'columns': [
            {'id': 'c_one0000001', 'blocks': [
              {'id': 'b_shown00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Shown', 'ta': ''}},
              {'id': 'b_hidden0001', 'type': 'text', 'v': 1, 'hidden': true, 'heading': {'en': 'Hidden one', 'ta': ''}},
            ]},
            {'id': 'c_two0000001', 'blocks': [
              {'id': 'b_bad0000001', 'type': 'buttons', 'v': 1, 'buttons': [{'id': 'i_btn0000001', 'label': {'en': 'Bad', 'ta': ''}, 'target': 'javascript:x'}]},
              {'id': 'b_future0001', 'type': 'carousel', 'v': 2},
            ]},
          ],
        },
        {
          'id': 'b_cols000002', 'type': 'columns', 'v': 1, 'layout': '1:1',
          'columns': [
            {'id': 'c_three00001', 'blocks': [{'id': 'b_hidden0002', 'type': 'text', 'v': 1, 'hidden': true, 'heading': {'en': 'Also hidden', 'ta': ''}}]},
            {'id': 'c_four000001', 'blocks': []},
          ],
        },
      ]);
      final before = await draft(id);
      await open(tester, id);
      // Each block inside the columns is on the canvas where it is: shown,
      // or as a placeholder saying why visitors don't see it.
      Finder inColumns(String cols, Finder f) => find.descendant(of: key('website-canvas-block-$cols'), matching: f);
      expect(inColumns('b_cols000001', key('website-canvas-placeholder-b_hidden0001')), findsOneWidget);
      expect(inColumns('b_cols000001', find.textContaining('Hidden: Text')), findsOneWidget);
      expect(inColumns('b_cols000001', key('website-canvas-placeholder-b_bad0000001')), findsOneWidget);
      expect(inColumns('b_cols000001', find.textContaining('Buttons: to fix')), findsOneWidget);
      expect(inColumns('b_cols000001', key('website-canvas-placeholder-b_future0001')), findsOneWidget);
      expect(inColumns('b_cols000001', find.textContaining('Unsupported block')), findsOneWidget);
      expect(onCanvas(find.text('Shown')), findsOneWidget);
      expect(onCanvas(find.text('Bad')), findsNothing, reason: 'an invalid block’s visitor text never shows');

      // No block shown at all: the columns are still drawn, with the hidden
      // block's placeholder.
      expect(key('website-canvas-placeholder-b_cols000002'), findsNothing);
      expect(inColumns('b_cols000002', key('website-canvas-placeholder-b_hidden0002')), findsOneWidget);

      // The placeholders can be selected like any block.
      await tap(tester, key('website-canvas-block-b_hidden0001'));
      expect(field('website-block-b_hidden0001-heading-en'), findsOneWidget);

      expect(_plain(await draft(id)), _plain(before), reason: 'nothing stored changes');
      expect(_plain(BlockRegistry.toMapList(editorBlocks(tester))), _plain(BlockRegistry.toMapList(BlockRegistry.parseList(before['blocks']))),
          reason: 'the editor holds the stored blocks unchanged');
      expect(key('website-custom-unsaved'), findsNothing);
    });
  });

  group('legacy sections copy', () {
    const imageText = {
      'id': 'lq3x9bbb', 'type': 'columns', 'v': 1, 'layout': '1:1',
      'columns': [
        {'id': 'lq3x9bbb__c1', 'blocks': [{'id': 'lq3x9bbb__txt', 'type': 'text', 'v': 1, 'heading': {'en': 'Garden', 'ta': ''}, 'body': {'en': 'Outdoor learning.', 'ta': ''}}]},
        {'id': 'lq3x9bbb__c2', 'blocks': [{'id': 'lq3x9bbb__img', 'type': 'image', 'v': 1, 'mediaId': 'm1', 'alt': {'en': '', 'ta': ''}, 'caption': {'en': '', 'ta': ''}, 'aspect': '4:3'}]},
      ],
    };

    test('a columns block with a hidden block inside has no copy; its blocks are kept as they are', () {
      final shown = BlockRegistry.parseList([imageText]);
      expect(LegacySections.mirror(shown).single.heading.en, 'Garden', reason: 'the image-and-text shape has a copy');
      for (final hide in [const BlockPath.nested(0, 0, 0), const BlockPath.nested(0, 1, 0)]) {
        final hidden = BlockListOps.toggleHidden(shown, hide);
        expect(LegacySections.toSection(hidden.single), isNull);
        expect(LegacySections.mirror(hidden), isEmpty, reason: 'older versions never see a hidden block');
        final stored = _plain(BlockRegistry.toMapList(hidden)) as List;
        final child = (((stored.single as Map)['columns'] as List)[hide.column!] as Map)['blocks'][0] as Map;
        expect(child['hidden'], isTrue);
        expect(child.containsKey('heading') ? child['heading'] : child['mediaId'], isNotNull, reason: 'its content is kept');
      }
    });

    test('a style that only spells out the defaults keeps the copy; any other style (or unknown key) does not', () {
      Map<String, dynamic> text(Map<String, dynamic> style) => {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Hi', 'ta': ''}, 'style': style};
      CustomPageSection? copy(Map<String, dynamic> style) => LegacySections.toSection(BlockRegistry.parse(text(style)));
      expect(copy({'background': 'white', 'spacing': 'normal'}), isNotNull);
      expect(copy({'background': 'white'}), isNotNull);
      expect(copy({'spacing': 'normal'}), isNotNull);
      expect(copy({'background': 'sage'}), isNull);
      expect(copy({'spacing': 'compact'}), isNull);
      expect(copy({'background': 'white', 'border': 'thin'}), isNull, reason: 'an unknown style key is kept, and not lost from view');
      final columns = BlockRegistry.parse({...imageText, 'style': {'background': 'white'}});
      expect(LegacySections.toSection(columns), isNotNull);
      expect((_plain(columns.toMap()) as Map)['style'], {'background': 'white'}, reason: 'the stored style is unchanged');
    });

    testWidgets('in the editor: choosing the default background keeps the copy; hiding a block inside columns removes it; blocks saved intact', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Hi', 'ta': ''}},
        imageText,
      ]);
      await open(tester, id);
      await tap(tester, key('website-canvas-block-b_text000001'));
      await tap(tester, key('website-block-b_text000001-style-background-choose'));
      await tap(tester, key('website-block-b_text000001-style-background-legacy-white'));
      expect((editorBlocks(tester).first as StructuredBlock).style, {'background': 'white'}, reason: 'the explicit default is stored as chosen');
      await tap(tester, key('website-block-lq3x9bbb__txt-visibility'));
      await tap(tester, key('website-custom-save-draft'));

      final saved = await draft(id);
      expect([for (final s in saved['sections'] as List) s['id']], ['b_text000001'], reason: 'the text keeps its copy; the columns block with a hidden text has none');
      final blocks = saved['blocks'] as List;
      expect(blocks[0]['style'], {'background': 'white'});
      final txt = (((blocks[1] as Map)['columns'] as List)[0] as Map)['blocks'][0] as Map;
      expect(txt['hidden'], isTrue);
      expect(txt['heading'], {'en': 'Garden', 'ta': ''});
      expect(key('website-custom-warnings'), findsOneWidget, reason: 'the block without a copy is counted');
    });
  });

  group('desktop canvas', () {
    const twoColumns = {
      'id': 'b_cols000001', 'type': 'columns', 'v': 1, 'layout': '1:1',
      'columns': [
        {'id': 'c_one0000001', 'blocks': [{'id': 'b_left000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Left', 'ta': ''}}]},
        {'id': 'c_two0000001', 'blocks': [{'id': 'b_right00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Right', 'ta': ''}}]},
      ],
    };

    testWidgets('at 1280 px, Desktop lays the page out at desktop width, scaled to fit; Mobile at 390 px', (tester) async {
      final id = await page(blocks: [twoColumns]);
      await open(tester, id, size: const Size(1280, 1600));
      expect(tester.takeException(), isNull);
      final element = tester.element(key('public-block-b_cols000001'));
      expect(MediaQuery.sizeOf(element).width, desktopCanvasWidth);
      expect(PublicLayout.of(MediaQuery.sizeOf(element).width), PublicLayout.desktop);
      final left = tester.getTopLeft(key('public-block-column-c_one0000001'));
      final right = tester.getTopLeft(key('public-block-column-c_two0000001'));
      expect(right.dx, greaterThan(left.dx), reason: 'columns side by side, as on a desktop');
      expect(right.dy, closeTo(left.dy, 1));
      final canvas = tester.getRect(key('website-editor-canvas-scroll'));
      final frame = tester.getRect(key('website-custom-preview'));
      expect(frame.left, greaterThanOrEqualTo(canvas.left));
      expect(frame.right, lessThanOrEqualTo(canvas.right), reason: 'scaled to fit, no overflow');
      expect(frame.width, lessThan(desktopCanvasWidth));

      await tap(tester, key('website-canvas-block-b_cols000001'));
      expect(key('website-canvas-toolbar-b_cols000001'), findsOneWidget, reason: 'clicks still reach the scaled page');

      await tap(tester, key('website-custom-preview-mobile'));
      final mobile = tester.element(key('public-block-b_cols000001'));
      expect(MediaQuery.sizeOf(mobile).width, 390);
      expect(tester.getTopLeft(key('public-block-column-c_two0000001')).dy, greaterThan(tester.getTopLeft(key('public-block-column-c_one0000001')).dy),
          reason: 'stacked, as on a phone');
      expect(tester.getSize(key('website-custom-preview-mobile-frame')).width, 390);
    });

    testWidgets('a canvas already wide enough is not scaled', (tester) async {
      final id = await page(blocks: [twoColumns]);
      await open(tester, id, size: const Size(2200, 1600));
      final element = tester.element(key('public-block-b_cols000001'));
      expect(MediaQuery.sizeOf(element).width, greaterThan(desktopCanvasWidth));
      expect(find.ancestor(of: key('website-custom-preview-desktop-frame'), matching: find.byType(FittedBox)), findsNothing);
    });
  });

  group('phone toolbar', () {
    testWidgets('the main actions stay; the rest are in More, and work as before (width, discard, unpublish, archive, restore)', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': ''}},
      ]);
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft);
      await open(tester, id, size: const Size(390, 1400));
      expect(tester.takeException(), isNull);
      for (final k in ['website-custom-save-draft', 'website-custom-publish', 'website-custom-more', 'website-preview-ta']) {
        expect(key(k), findsOneWidget, reason: k);
      }
      for (final k in ['website-custom-unpublish', 'website-custom-archive', 'website-preview-source', 'website-custom-preview-toggle', 'website-custom-preview-mobile']) {
        expect(key(k), findsNothing, reason: '$k is in More');
      }
      expect(tester.getSize(key('website-custom-toolbar')).height, lessThan(200), reason: 'a compact toolbar: status, language, main actions');

      Future<void> more(String item) async {
        await tap(tester, key('website-custom-more'));
        await tester.tap(key('website-custom-more-$item'));
        await tester.pumpAndSettle();
      }

      await more('width');
      expect(key('website-custom-preview-mobile-frame'), findsOneWidget);
      await more('width');
      expect(key('website-custom-preview-desktop-frame'), findsOneWidget);

      await tap(tester, key('website-canvas-block-b_text000001'));
      await tap(tester, key('website-editor-edit-selected'));
      await type(tester, 'website-block-b_text000001-heading-en', 'About us');
      await more('discard');
      await tap(tester, key('website-custom-discard-confirm'));
      expect((editorBlocks(tester).single as StructuredBlock).text('heading').en, 'About', reason: 'discarded');

      await more('unpublish');
      expect((await firestore.collection(WebsiteCollections.livePages).doc(id).get()).exists, isFalse, reason: 'unpublished by the service');

      await more('archive');
      await tap(tester, key('website-custom-archive-confirm'));
      expect((await draft(id))['archived'], isTrue);
      expect(key('website-custom-restore'), findsOneWidget);
      await tap(tester, key('website-custom-restore'));
      expect((await draft(id))['archived'], isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('languages', () {
    testWidgets('English and Tamil are edited; the canvas follows the language; other languages are kept', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': 'பற்றி', 'hi': 'परिचय'}},
      ]);
      await open(tester, id);
      expect(onCanvas(find.text('About')), findsOneWidget);
      await tap(tester, key('website-preview-ta'));
      expect(onCanvas(find.text('பற்றி')), findsOneWidget);
      expect(onCanvas(find.text('சுற்றுலா')), findsOneWidget, reason: 'the page title in Tamil');

      await tap(tester, key('website-canvas-block-b_text000001'));
      await type(tester, 'website-block-b_text000001-heading-ta', 'எங்களைப் பற்றி');
      expect(onCanvas(find.text('எங்களைப் பற்றி')), findsOneWidget);
      await tap(tester, key('website-custom-save-draft'));
      expect(((await draft(id))['blocks'] as List).single['heading'], {'en': 'About', 'ta': 'எங்களைப் பற்றி', 'hi': 'परिचय'});
    });
  });

  group('responsive', () {
    testWidgets('medium width: side panels are shown and hidden', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': ''}},
      ]);
      await open(tester, id, size: const Size(1000, 1600));
      expect(tester.takeException(), isNull);
      expect(key('website-editor-structure'), findsNothing, reason: 'structure starts hidden');
      expect(key('website-editor-properties'), findsOneWidget);
      await tap(tester, key('website-editor-toggle-structure'));
      expect(key('website-editor-structure'), findsOneWidget);
      await tap(tester, key('website-editor-toggle-properties'));
      expect(key('website-editor-properties'), findsNothing);
      await tap(tester, key('website-canvas-block-b_text000001'));
      expect(key('website-canvas-toolbar-b_text000001'), findsOneWidget);
      await tap(tester, key('website-block-b_text000001-edit'));
      expect(key('website-editor-properties'), findsOneWidget, reason: 'editing a block brings its properties back');
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow width: Page, Structure and Edit tabs; selecting on the page offers Edit', (tester) async {
      final id = await page(blocks: [
        {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': ''}},
      ]);
      await open(tester, id, size: const Size(390, 1400));
      expect(tester.takeException(), isNull);
      expect(key('website-custom-preview'), findsOneWidget);
      expect(key('website-editor-structure'), findsNothing);
      expect(key('website-editor-properties'), findsNothing);

      await tap(tester, key('website-canvas-block-b_text000001'));
      await tap(tester, key('website-editor-edit-selected'));
      expect(key('website-editor-properties'), findsOneWidget);
      await type(tester, 'website-block-b_text000001-heading-en', 'About us');

      await tap(tester, key('website-editor-tab-structure'));
      expect(key('website-editor-structure'), findsOneWidget);
      await pick(tester, 'website-blocks-add', 'divider');
      expect(key('website-editor-properties'), findsOneWidget, reason: 'a new block opens its properties');

      await tap(tester, key('website-editor-tab-page'));
      expect(onCanvas(find.text('About us')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('pages made of sections', () {
    testWidgets('keep the form editor: no visual editor until converted', (tester) async {
      final id = await page(sections: [
        {'id': 'lq3x9aaa', 'type': 'text', 'heading': {'en': 'Welcome', 'ta': ''}, 'body': {'en': 'Hello', 'ta': ''}},
      ]);
      final before = await draft(id);
      await open(tester, id);
      expect(key('website-custom-blocks'), findsNothing);
      expect(key('website-editor-structure'), findsNothing);
      expect(key('website-custom-add-section'), findsOneWidget);
      expect(_plain(await draft(id)), _plain(before), reason: 'opening writes nothing');

      await tap(tester, key('website-custom-convert'));
      await tap(tester, key('website-custom-convert-confirm'));
      expect(key('website-editor-structure'), findsOneWidget, reason: 'converted in the editor');
      expect(ids(tester), ['lq3x9aaa']);
      expect((await draft(id)).containsKey('blocks'), isFalse, reason: 'nothing saved until Save draft');
      await tap(tester, key('website-custom-discard'));
      await tap(tester, key('website-custom-discard-confirm'));
      expect(key('website-custom-add-section'), findsOneWidget, reason: 'discarded: back to sections');
    });
  });
}
