// Columns / Row: inner columns inside a section's column. Three kinds of
// block, kept apart: a section (outer columns, top level only), a
// Columns / Row (`row`: inner columns, only in a section's column) and
// content blocks (in any column). Never nested further: a row holds
// content only. Covers 1–4 inner columns, each screen size on its own
// (Automatic and set), adding to each inner column, several rows in one
// section column, reorder / duplicate / hide / delete, fewer columns
// without losing content, save / reopen / publish, pages from before and
// narrow / phone layouts. Synthetic test data only.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/block_list_ops.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
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

Map<String, dynamic> _text(String id, {String ta = ''}) => {'id': id, 'type': 'text', 'v': 1, 'heading': {'en': 'Heading $id', 'ta': ta}, 'body': {'en': 'Words.', 'ta': ''}};

/// A row `b_<tag>row00` of [count] inner columns (`c_<tag>col0<i>`), each
/// with [perColumn] text blocks (`b_<tag>c<i>t<j>0`, Tamil in the first)
/// and, in the second, an image (unless not [image]: publishing needs
/// images in the library); [values] for its settings.
Map<String, dynamic> _row(String tag, int count, {int perColumn = 1, Map<String, Object?> values = const {}, Map<String, Object?> style = const {}, bool hidden = false, bool image = true}) => {
      'id': 'b_${tag}row00',
      'type': 'row',
      'v': 1,
      'layout': List.filled(count, '1').join(':'),
      if (hidden) 'hidden': true,
      ...values,
      if (style.isNotEmpty) 'style': style,
      'columns': [
        for (var i = 0; i < count; i++)
          {
            'id': 'c_${tag}col0$i',
            'blocks': [
              for (var j = 0; j < perColumn; j++) _text('b_${tag}c${i}t${j}0', ta: j == 0 ? 'உள் $tag $i' : ''),
              if (i == 1 && image) {'id': 'b_${tag}img001', 'type': 'image', 'v': 1, 'mediaId': 'media_${tag}_photo', 'aspect': '4:3'},
            ],
          },
      ],
    };

/// A one-column section `b_sec00001` ("Programmes", column `c_col00000`)
/// holding [blocks] (in their stored form, normalised as the app stores
/// them).
Map<String, dynamic> _section(List<Map<String, dynamic>> blocks, {String layout = '1'}) => Map<String, dynamic>.from(BlockRegistry.toMapList(BlockRegistry.parseList([
      {
        'id': 'b_sec00001',
        'type': 'section',
        'v': 1,
        'name': {'en': 'Programmes', 'ta': ''},
        'layout': layout,
        'style': {'background': 'token:sageLight', 'columnGap': '24'},
        'columns': [
          {'id': 'c_col00000', 'blocks': blocks},
          for (var i = 1; i < (columnLayouts[layout]?.length ?? 1); i++) {'id': 'c_col0000$i', 'blocks': <Object?>[]},
        ],
      },
    ])).single as Map);

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parseList([raw]).single as StructuredBlock;

/// Every id at every depth inside [b].
Set<String> _allIds(WebsiteBlock b) => {
      for (final x in BlockRegistry.flatten([b])) ...[x.id, for (final c in BlockListOps.columnsOf(x)) c.id],
    };

void main() {
  Finder key(String k) => find.byKey(Key(k));

  // ------------------------------------------------------------ model
  group('the model', () {
    test('a row is its own type: in a section’s column only, holding content only; two levels at most', () {
      expect(BlockRegistry.row.type, 'row');
      expect(BlockRegistry.row.label, 'Columns / Row');
      expect(containerTypes, containsAll(['section', 'columns', 'row']));
      expect(ColumnOps.range(BlockRegistry.create(BlockRegistry.row)), (1, 4));
      expect(BlockRegistry.nestableIn('section').first.type, 'row', reason: 'offered first in a section’s column');
      expect(BlockRegistry.nestableIn('row').map((d) => d.type), isNot(contains('row')), reason: 'never a row in a row');
      expect(BlockRegistry.nestableIn('columns').map((d) => d.type), isNot(contains('row')));
      expect(BlockRegistry.nestable.map((d) => d.type), isNot(anyOf(contains('row'), contains('section'), contains('columns'))), reason: 'content blocks only');
      expect(BlockRegistry.topLevel.map((d) => d.type), isNot(contains('row')), reason: 'not in the page’s own Add block');

      final ok = BlockRegistry.parseList([_section([_row('a', 3), _text('b_between0'), _row('b', 2)])]);
      expect(BlockRegistry.validate(ok), isEmpty, reason: 'several rows and blocks in one section column');

      String errors(List<Object?> raw) => BlockRegistry.validate(BlockRegistry.parseList(raw)).join('\n');
      expect(errors([_row('a', 2)]), contains('a Columns / Row block goes inside a section’s column'));
      final rowInRow = _row('a', 1)..['columns'] = [
          {'id': 'c_acol00', 'blocks': [_row('b', 1)]},
        ];
      expect(errors([_section([rowInRow])]), contains('columns / row can’t contain columns / row'));
      expect(errors([
        {'id': 'b_cols0001', 'type': 'columns', 'v': 1, 'layout': '1:1', 'columns': [{'id': 'c_x1', 'blocks': [_row('a', 1)]}, {'id': 'c_x2', 'blocks': []}]},
      ]), contains('columns can’t contain columns / row'));
      final sectionInRow = _row('a', 1)..['columns'] = [
          {'id': 'c_acol00', 'blocks': [{'id': 'b_inner001', 'type': 'section', 'v': 1, 'layout': '1', 'columns': [{'id': 'c_in1', 'blocks': []}]}]},
        ];
      expect(errors([_section([sectionInRow])]), contains('columns / row can’t contain section'));
    });

    test('stored as it was read: ids, Tamil, image, per-screen settings, style and unknown fields kept', () {
      final raw = _section([
        _row('a', 4, perColumn: 2, values: {'name': {'en': 'Facts'}, 'desktopColumns': '4', 'tabletColumns': '2', 'mobileColumns': '1', 'verticalAlign': 'center'}, style: {'columnGap': '16', 'background': 'token:goldLight', 'align': 'center'}),
        _row('b', 1),
      ]);
      final rawRow = ((raw['columns'] as List).first as Map)['blocks'] as List;
      (rawRow.first as Map)['futureSetting'] = {'kept': true};
      ((rawRow.first as Map)['columns'] as List).first['futureColumnSetting'] = 7;
      final parsed = _parse(raw);
      expect(parsed.toMap(), raw, reason: 'round trip, unknown fields too');
      final row = parsed.columns('columns').first.blocks.first as StructuredBlock;
      expect(row.type, 'row');
      expect(row.columns('columns'), hasLength(4));
      expect((row.columns('columns').first.blocks.first as StructuredBlock).text('heading').ta, 'உள் a 0');
      expect(BlockRegistry.referencedMedia([parsed]), contains('media_a_photo'), reason: 'images inside a row are counted as used');
      expect(ColumnsPerRow.on(row, 'desktop'), 4);
      expect(ColumnsPerRow.on(row, 'tablet'), 2);
      expect(ColumnsPerRow.on(row, 'mobile'), 1);
      expect(row.option('verticalAlign'), 'center');

      final plain = _parse(_section([_row('b', 2)])).columns('columns').first.blocks.first as StructuredBlock;
      expect(plain.toMap().keys, isNot(anyOf(contains('name'), contains('verticalAlign'), contains('desktopColumns'))), reason: 'defaults not stored');
    });

    test('new rows of 1 to 4 empty, equal columns; Automatic on every screen', () {
      for (var n = 1; n <= 4; n++) {
        final row = ColumnOps.newRow(n);
        expect(row.columns('columns'), hasLength(n));
        expect(row.columns('columns').every((c) => c.blocks.isEmpty), isTrue);
        expect(row.string('layout'), List.filled(n, '1').join(':'));
        expect(row.toMap().keys.where((k) => k.endsWith('Columns')), isEmpty);
        expect(ColumnsPerRow.on(row, 'mobile'), 1);
        expect(ColumnsPerRow.on(row, 'tablet'), n > 3 ? 2 : n, reason: 'Automatic: as on desktop, four become two');
      }
    });

    test('paths into a row: at, replace, insert, move, move to column, duplicate, hide, remove; walk', () {
      var blocks = BlockRegistry.parseList([_text('b_top00001'), _section([_text('b_first001'), _row('a', 3), _row('b', 2)])]);
      const row = BlockPath.nested(1, 0, 1);
      const inner = BlockPath.inRow(1, 0, 1, 2, 0);
      expect(BlockListOps.at(blocks, row)!.id, 'b_arow00');
      expect(BlockListOps.at(blocks, inner)!.id, 'b_ac2t00');
      expect(inner.parent, row);
      expect(inner.depth, 2);
      expect(inner.isWithin(row), isTrue);
      expect(inner.isWithin(const BlockPath(1)), isTrue);
      expect(BlockPath.inside(row, 2, 0), inner);
      expect(BlockListOps.parentOf(blocks, inner)!.id, 'b_arow00');

      final walked = [for (final (p, b) in BlockListOps.walk(blocks)) '${b.id}@${p.depth}'];
      expect(walked.take(6), ['b_top00001@0', 'b_sec00001@0', 'b_first001@1', 'b_arow00@1', 'b_ac0t00@2', 'b_ac1t00@2']);

      // Insert into an inner column; a row can't go into a row.
      expect(BlockListOps.canInsertInColumn(blocks, row, 0, BlockRegistry.create(BlockRegistry.divider)), isTrue);
      expect(BlockListOps.canInsertInColumn(blocks, row, 0, ColumnOps.newRow(2)), isFalse, reason: 'no row in a row');
      expect(BlockListOps.canInsertInColumn(blocks, const BlockPath(1), 0, ColumnOps.newRow(2)), isTrue, reason: 'a row in a section column');
      final (withDivider, at) = BlockListOps.insertInColumn(blocks, row, 0, BlockRegistry.create(BlockRegistry.divider));
      expect(at, const BlockPath.inRow(1, 0, 1, 0, 1));
      expect(BlockListOps.at(withDivider, at)!.type, 'divider');
      expect((BlockListOps.at(withDivider, row) as StructuredBlock).columns('columns')[1].blocks.map((b) => b.id), ['b_ac1t00', 'b_aimg001'], reason: 'other inner columns unchanged');
      expect(withDivider.first, same(blocks.first), reason: 'untouched blocks kept as they are');

      // Move an inner block to another inner column of the same row.
      final (moved, to) = BlockListOps.moveToColumn(blocks, inner, 0);
      expect(to, const BlockPath.inRow(1, 0, 1, 0, 1));
      expect(BlockListOps.at(moved, to)!.id, 'b_ac2t00');
      expect((BlockListOps.at(moved, row) as StructuredBlock).columns('columns')[2].blocks, isEmpty);

      // Reorder rows within the section column.
      final (reordered, rowTo) = BlockListOps.move(blocks, row, 1);
      expect(rowTo, const BlockPath.nested(1, 0, 2));
      expect([for (final b in (reordered[1] as StructuredBlock).columns('columns').first.blocks) b.id], ['b_first001', 'b_brow00', 'b_arow00']);
      expect(BlockListOps.at(reordered, rowTo)!.toMap(), BlockListOps.at(blocks, row)!.toMap(), reason: 'its content moves with it');

      // Duplicate a row: new ids throughout, the same content.
      final (copied, copyAt) = BlockListOps.duplicate(blocks, row);
      final original = BlockListOps.at(copied, row)!;
      final copy = BlockListOps.at(copied, copyAt)!;
      expect(copyAt, const BlockPath.nested(1, 0, 2));
      expect(_allIds(copy).intersection(_allIds(original)), isEmpty);
      expect(BlockRegistry.validate(copied), isEmpty, reason: 'ids still unique on the page');
      expect(BlockRegistry.flatten([copy]).map((b) => b.type), BlockRegistry.flatten([original]).map((b) => b.type));
      expect((BlockListOps.at(copied, BlockPath.inside(copyAt, 0, 0)) as StructuredBlock).text('heading').ta, 'உள் a 0');

      // Hide an inner block, then the row; publishing leaves them out.
      blocks = BlockListOps.toggleHidden(blocks, inner);
      expect((BlockListOps.at(blocks, inner) as StructuredBlock).hidden, isTrue);
      var published = BlockRegistry.withoutHidden(blocks);
      expect(BlockRegistry.flatten(published).map((b) => b.id), isNot(contains('b_ac2t00')));
      expect(BlockRegistry.flatten(published).map((b) => b.id), contains('b_arow00'));
      blocks = BlockListOps.toggleHidden(blocks, row);
      published = BlockRegistry.withoutHidden(blocks);
      expect(BlockRegistry.flatten(published).map((b) => b.id), isNot(anyOf(contains('b_arow00'), contains('b_ac0t00'))), reason: 'a hidden row goes with its content');

      // Remove an inner block, then the row.
      final removed = BlockListOps.remove(blocks, inner);
      expect((BlockListOps.at(removed, row) as StructuredBlock).columns('columns')[2].blocks, isEmpty);
      final noRow = BlockListOps.remove(blocks, row);
      expect([for (final b in (noRow[1] as StructuredBlock).columns('columns').first.blocks) b.id], ['b_first001', 'b_brow00']);
    });

    test('fewer inner columns: the removed columns’ blocks move to a chosen column; more columns are empty', () {
      final row = _parse(_row('a', 4, perColumn: 1));
      expect(ColumnOps.blocksRemovedBy(row, '1:1'), 2);
      final two = ColumnOps.withLayout(row, '1:1', moveBlocks: true, moveInto: 0);
      expect(two.columns('columns').map((c) => c.blocks.map((b) => b.id).toList()), [
        ['b_ac0t00', 'b_ac2t00', 'b_ac3t00'],
        ['b_ac1t00', 'b_aimg001'],
      ]);
      expect(two.columns('columns').map((c) => c.id), ['c_acol00', 'c_acol01'], reason: 'kept columns keep their ids');
      expect(() => ColumnOps.withLayout(row, '1:1'), throwsStateError, reason: 'never dropped silently');
      final four = ColumnOps.withLayout(two, '1:1:1:1');
      expect(four.columns('columns').skip(2).every((c) => c.blocks.isEmpty), isTrue);
      expect(four.columns('columns').take(2).map((c) => c.blocks.length), [3, 2], reason: 'existing content unchanged');
    });
  });

  // ------------------------------------------------------------ rendering
  group('on the page (the same renderer as the editor’s canvas)', () {
    Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> raw, double width) async {
      tester.view.physicalSize = Size(width, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteDesignScope(
              design: SiteDesign.defaults,
              child: WebsiteBlocksView(blocks: BlockRegistry.parseList(raw), media: const {}, language: PublicLanguage.english, interactive: false, spaced: false, fullBleed: true),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow at $width px');
    }

    /// How many of the row's inner columns share each top edge.
    List<int> rows(WidgetTester tester, String tag, int count) {
      final tops = <double, int>{};
      for (var i = 0; i < count; i++) {
        final top = tester.getRect(key('public-block-column-c_${tag}col0$i')).top;
        final at = tops.keys.firstWhere((t) => (t - top).abs() < 1, orElse: () => top);
        tops[at] = (tops[at] ?? 0) + 1;
      }
      return tops.values.toList();
    }

    testWidgets('each screen size on its own: 3 on desktop, 2 on tablets, 1 on phones; Automatic as a section’s', (tester) async {
      final page = [
        _section([
          _row('a', 3, values: {'desktopColumns': '3', 'tabletColumns': '2', 'mobileColumns': '1'}),
          _row('b', 4),
        ]),
      ];
      for (final (width, a, b) in [
        (1280.0, [3], [4]),
        (820.0, [2, 1], [2, 2]),
        (390.0, [1, 1, 1], [1, 1, 1, 1]),
      ]) {
        await pump(tester, page, width);
        expect(rows(tester, 'a', 3), a, reason: 'set: $width px');
        expect(rows(tester, 'b', 4), b, reason: 'Automatic: $width px');
        expect(key('public-row-b_arow00'), findsOneWidget);
        expect(find.text('Heading b_ac2t00'), findsOneWidget, reason: 'every inner column’s content shown');
      }
    });

    testWidgets('inside one of four section columns on a phone; the row’s own gap; hidden and empty rows left out', (tester) async {
      final page = [
        _section([
          _row('a', 2, style: {'columnGap': '16'}),
          _row('h', 2, hidden: true),
          {'id': 'b_erow0000', 'type': 'row', 'v': 1, 'layout': '1:1', 'columns': [{'id': 'c_e0', 'blocks': []}, {'id': 'c_e1', 'blocks': []}]},
        ], layout: '1:1:1:1'),
      ];
      await pump(tester, page, 1280);
      final left = tester.getRect(key('public-block-column-c_acol00'));
      final right = tester.getRect(key('public-block-column-c_acol01'));
      expect(right.left - left.right, closeTo(16, 0.5), reason: 'its own column gap');
      expect(key('public-row-b_hrow00'), findsNothing, reason: 'hidden');
      expect(key('public-row-b_erow0000'), findsNothing, reason: 'nothing to show');
      await pump(tester, page, 360);
      expect(rows(tester, 'a', 2), [1, 1]);
    });

    testWidgets('a page from before (sections, a columns block, no rows) is drawn as before', (tester) async {
      final page = [
        _section([_text('b_plain0001')], layout: '1:1'),
        {'id': 'b_cols0001', 'type': 'columns', 'v': 1, 'layout': '1:1', 'columns': [{'id': 'c_old1', 'blocks': [_text('b_old00001')]}, {'id': 'c_old2', 'blocks': [_text('b_old00002')]}]},
      ];
      await pump(tester, page, 1280);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('public-row-')), findsNothing);
      expect(tester.getRect(key('public-block-column-c_old1')).top, tester.getRect(key('public-block-column-c_old2')).top);
      expect(tester.getRect(key('public-block-column-c_old2')).left - tester.getRect(key('public-block-column-c_old1')).right, closeTo(40, 0.5), reason: 'the columns block’s gap as before');
    });
  });

  // ------------------------------------------------------------ editor
  group('in the editor', () {
    late FakeFirebaseFirestore db;
    late WebsiteContentAdminService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<String> pageWith(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Rows', ta: 'வரிசைகள்'), slug: 'rows-page');
      await db.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    Future<void> open(WidgetTester tester, String id, {Size size = const Size(1400, 2600)}) async {
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

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    /// Opens [menu] and chooses its item [item].
    Future<void> choose(WidgetTester tester, String menu, String item) async {
      await tap(tester, key(menu));
      await tester.tap(key(item).last);
      await tester.pumpAndSettle();
    }

    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
    StructuredBlock section(WidgetTester tester) => blocks(tester).first as StructuredBlock;
    List<WebsiteBlock> sectionColumn(WidgetTester tester) => section(tester).columns('columns').first.blocks;
    String inspectorTitle(WidgetTester tester) => tester.widget<Text>(key('website-inspector-title')).data!;

    testWidgets('Add block in a section column offers Columns / Row; choose 1–4; then add to every inner column; several rows in one column', (tester) async {
      final id = await pageWith([_section([_text('b_first001')])]);
      await open(tester, id);

      // The structure's Add for the section's column offers it, first.
      await tap(tester, key('website-column-c_col00000-add'));
      expect(key('website-column-c_col00000-add-row'), findsOneWidget);
      expect(find.text('Columns / Row'), findsOneWidget);
      await tester.tap(key('website-column-c_col00000-add-row').last);
      await tester.pumpAndSettle();
      expect(key('website-row-columns-dialog'), findsOneWidget, reason: 'asks how many inner columns');
      for (var n = 1; n <= 4; n++) {
        expect(key('website-row-columns-$n'), findsOneWidget);
      }
      // Cancel adds nothing.
      await tap(tester, key('website-row-columns-cancel'));
      expect(sectionColumn(tester), hasLength(1));

      await choose(tester, 'website-column-c_col00000-add', 'website-column-c_col00000-add-row');
      await tap(tester, key('website-row-columns-3'));
      expect(sectionColumn(tester), hasLength(2));
      final row = sectionColumn(tester)[1] as StructuredBlock;
      expect(row.type, 'row');
      expect(row.columns('columns'), hasLength(3));
      expect(blocks(tester), hasLength(1), reason: 'not a new section');
      // Selected, with its own panel and where it is.
      expect(inspectorTitle(tester), 'Columns / Row');
      expect(tester.widget<Text>(key('website-block-${row.id}-columns-panel-title')).data, 'Inner columns of this row');
      expect(tester.widget<Text>(key('website-inspector-location')).data, 'In section “Programmes”, column 1');

      // Each inner column its own Add (canvas), content blocks only.
      final inner = row.columns('columns');
      for (final (i, type) in [(0, 'text'), (1, 'image'), (2, 'divider')]) {
        await tap(tester, key('website-canvas-column-${inner[i].id}-add'));
        expect(key('website-canvas-column-${inner[i].id}-add-row'), findsNothing, reason: 'no row in a row');
        expect(key('website-canvas-column-${inner[i].id}-add-section'), findsNothing);
        await tester.tap(key('website-canvas-column-${inner[i].id}-add-$type').last);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(key('website-inspector-location')).data, 'In section “Programmes”, column 1 › row, inner column ${i + 1}');
      }
      final filled = sectionColumn(tester)[1] as StructuredBlock;
      expect(filled.columns('columns').map((c) => c.blocks.map((b) => b.type).toList()), [
        ['text'],
        ['image'],
        ['divider'],
      ], reason: 'each inner column only its own block');
      // Back to the row from an inner block.
      await tap(tester, key('website-inspector-parent'));
      expect(inspectorTitle(tester), 'Columns / Row');

      // The structure shows the inner columns, each with an Add (content only).
      await tap(tester, key('website-column-${inner[0].id}-add'));
      expect(key('website-column-${inner[0].id}-add-row'), findsNothing);
      expect(key('website-column-${inner[0].id}-add-text'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(find.text('Inner column 2'), findsOneWidget);

      // A second row in the same column, from the section's own panel.
      await tap(tester, key('website-block-b_sec00001-edit'));
      await choose(tester, 'website-column-c_col00000-panel-add', 'website-column-c_col00000-panel-add-row');
      await tap(tester, key('website-row-columns-2'));
      expect(sectionColumn(tester).map((b) => b.type), ['text', 'row', 'row']);
      expect((sectionColumn(tester)[2] as StructuredBlock).columns('columns'), hasLength(2));
      // (The new blocks are still empty, to fill in; nothing about where they are.)
      expect(BlockRegistry.validate(blocks(tester)).where((e) => e.contains('contain') || e.contains('nested') || e.contains('goes inside')), isEmpty);

      // The page's own Add block doesn't offer it.
      await tap(tester, key('website-blocks-add'));
      expect(key('website-blocks-add-row'), findsNothing);
      expect(key('website-blocks-add-text'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row’s columns on each screen: desktop, tablet and phone set on their own; Automatic shown; 4 → 2 into a chosen column', (tester) async {
      final id = await pageWith([_section([_row('a', 4)])]);
      await open(tester, id);
      const r = 'website-block-b_arow00';
      await tap(tester, key('$r-edit'));
      expect(key('$r-columns-panel'), findsOneWidget);
      expect(tester.widget<Text>(key('$r-columns-current')).data, 'Desktop (previewing): 4 of 4 per row, Automatic.');

      // Desktop 3, tablet 2, phone 1: each its own.
      await choose(tester, '$r-desktopColumns', '$r-desktopColumns-3');
      await tap(tester, key('website-custom-preview-tablet'));
      expect(tester.widget<Text>(key('$r-columns-current')).data, 'Tablet (previewing): 3 of 4 per row, Automatic.', reason: 'Automatic follows desktop');
      await choose(tester, '$r-tabletColumns', '$r-tabletColumns-2');
      expect(tester.widget<Text>(key('$r-columns-current')).data, 'Tablet (previewing): 2 of 4 per row, set for this screen.');
      expect(key('$r-tabletColumns-previewing'), findsOneWidget);
      await tap(tester, key('website-custom-preview-mobile'));
      expect(tester.widget<Text>(key('$r-columns-current')).data, 'Phone (previewing): 1 of 4 per row, Automatic.');
      await choose(tester, '$r-mobileColumns', '$r-mobileColumns-2');
      final set = sectionColumn(tester).single as StructuredBlock;
      expect([set.option('desktopColumns'), set.option('tabletColumns'), set.option('mobileColumns')], ['3', '2', '2']);
      // Back to Automatic on the phone.
      await choose(tester, '$r-mobileColumns', '$r-mobileColumns-auto');
      expect((sectionColumn(tester).single as StructuredBlock).toMap().containsKey('mobileColumns'), isFalse);
      expect(section(tester).toMap().keys.where((k) => k.endsWith('Columns')), isEmpty, reason: 'the section’s own settings untouched');
      await tap(tester, key('website-custom-preview-desktop'));

      // Fewer: inner columns 3 and 4's blocks go to column 1, as chosen.
      await tap(tester, key('$r-column-count-2'));
      expect(key('website-columns-layout-dialog'), findsOneWidget);
      await tap(tester, key('website-columns-layout-cancel'));
      expect((sectionColumn(tester).single as StructuredBlock).columns('columns'), hasLength(4), reason: 'Cancel changes nothing');
      await tap(tester, key('$r-column-count-2'));
      await tap(tester, key('website-columns-layout-into-0'));
      await tap(tester, key('website-columns-layout-move'));
      final two = sectionColumn(tester).single as StructuredBlock;
      expect(two.columns('columns').map((c) => c.blocks.map((b) => b.id).toList()), [
        ['b_ac0t00', 'b_ac2t00', 'b_ac3t00'],
        ['b_ac1t00', 'b_aimg001'],
      ]);
      expect((two.columns('columns').first.blocks[1] as StructuredBlock).text('heading').ta, 'உள் a 2', reason: 'Tamil kept');
      expect(two.option('desktopColumns'), '2', reason: 'per-screen settings never ask for more columns than there are');
      // More: an empty one, the rest unchanged.
      await tap(tester, key('$r-column-count-3'));
      final three = sectionColumn(tester).single as StructuredBlock;
      expect(three.columns('columns').map((c) => c.blocks.length), [3, 2, 0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reorder, duplicate, hide and delete a row keep its contents; save, reopen and publish', (tester) async {
      final id = await pageWith([_section([_row('a', 2, image: false), _text('b_between0'), _row('b', 3, image: false)])]);
      await open(tester, id);
      final original = (sectionColumn(tester).first as StructuredBlock).toMap();

      // Reorder: down past the text block.
      await tap(tester, key('website-block-b_arow00-down'));
      expect(sectionColumn(tester).map((b) => b.id), ['b_between0', 'b_arow00', 'b_brow00']);
      expect(sectionColumn(tester)[1].toMap(), original, reason: 'moved with its contents');
      await tap(tester, key('website-block-b_arow00-up'));
      expect(sectionColumn(tester).map((b) => b.id), ['b_arow00', 'b_between0', 'b_brow00']);

      // Duplicate: the copy right after it, new ids throughout.
      await tap(tester, key('website-block-b_arow00-more'));
      expect(key('website-block-b_arow00-save-template'), findsNothing, reason: 'saved with its section, not alone');
      expect(find.text('Columns and layout…'), findsOneWidget);
      await tester.tap(key('website-block-b_arow00-duplicate'));
      await tester.pumpAndSettle();
      final copy = sectionColumn(tester)[1] as StructuredBlock;
      expect(copy.type, 'row');
      expect(_allIds(copy).intersection(_allIds(sectionColumn(tester).first)), isEmpty);
      expect(BlockRegistry.flatten([copy]).length, BlockRegistry.flatten([sectionColumn(tester).first]).length);

      // Hide the copy: kept in the draft, left out when published.
      await tap(tester, key('website-block-${copy.id}-more'));
      await tester.tap(key('website-block-${copy.id}-visibility'));
      await tester.pumpAndSettle();
      expect(key('website-block-${copy.id}-hidden'), findsOneWidget);

      // Delete the third row: asks first.
      await tap(tester, key('website-block-b_brow00-more'));
      await tester.tap(key('website-block-b_brow00-delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tap(tester, key('website-block-delete-confirm'));
      expect(sectionColumn(tester).map((b) => b.id), ['b_arow00', copy.id, 'b_between0']);

      // Save, reopen, publish.
      final before = [for (final b in blocks(tester)) b.toMap()];
      await tap(tester, key('website-custom-save-draft'));
      await open(tester, id);
      expect([for (final b in blocks(tester)) b.toMap()], before, reason: 'reopened as saved');
      await tap(tester, key('website-custom-publish'));
      if (key('website-custom-publish-confirm').evaluate().isNotEmpty) await tap(tester, key('website-custom-publish-confirm'));
      final live = (await db.collection(WebsiteCollections.livePages).doc(id).get()).data()!;
      final published = BlockRegistry.parseList(live['blocks']);
      final ids = BlockRegistry.flatten(published).map((b) => b.id).toList();
      expect(ids, containsAll(['b_arow00', 'b_ac0t00', 'b_ac1t00', 'b_between0']));
      expect(ids, isNot(contains(copy.id)), reason: 'the hidden copy isn’t published');
      expect(((published.first as StructuredBlock).columns('columns').first.blocks.first).toMap(), original, reason: 'published as edited');
    });

    testWidgets('a page from before (no rows): shown and saved exactly as it was', (tester) async {
      final raw = [
        _section([_text('b_plain0001')], layout: '1:1'),
        Map<String, dynamic>.from(BlockRegistry.toMapList(BlockRegistry.parseList([
          {'id': 'b_cols0001', 'type': 'columns', 'v': 1, 'layout': '1:1', 'columns': [{'id': 'c_old1', 'blocks': [_text('b_old00001')]}, {'id': 'c_old2', 'blocks': []}]},
        ])).single as Map),
        _text('b_loose0001'),
      ];
      final id = await pageWith(raw);
      await open(tester, id);
      expect([for (final b in blocks(tester)) b.toMap()], raw);
      // A top-level columns block's column offers content only, as before.
      await tap(tester, key('website-column-c_old1-add'));
      expect(key('website-column-c_old1-add-row'), findsNothing);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      await tap(tester, key('website-custom-save-draft'));
      final stored = (await db.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks'] as List;
      expect([for (final b in stored) Map<String, dynamic>.from(b as Map)], raw, reason: 'nothing new stored');
    });

    testWidgets('narrow editor and phone preview: rows in the structure and canvas fit; adding still works', (tester) async {
      final id = await pageWith([_section([_row('a', 4, perColumn: 2), _row('b', 2)], layout: '1:1:1:1')]);
      // Medium window, structure open.
      await open(tester, id, size: const Size(920, 2600));
      await tap(tester, key('website-editor-toggle-structure'));
      expect(key('website-block-b_arow00'), findsOneWidget);
      expect(key('website-structure-column-c_acol03'), findsOneWidget);
      await tap(tester, key('website-custom-preview-mobile'));
      expect(tester.takeException(), isNull);
      await choose(tester, 'website-column-c_bcol00-add', 'website-column-c_bcol00-add-text');
      expect((sectionColumn(tester)[1] as StructuredBlock).columns('columns').first.blocks, hasLength(2));
      expect(tester.takeException(), isNull);

      // Narrow window: the Structure tab, then Edit.
      await open(tester, id, size: const Size(600, 2600));
      await tap(tester, key('website-editor-tab-structure'));
      expect(key('website-block-b_ac3t10'), findsOneWidget, reason: 'inner blocks listed');
      await tap(tester, key('website-block-b_arow00-edit'));
      expect(key('website-block-b_arow00-columns-panel'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, key('website-editor-tab-page'));
      expect(key('website-canvas-column-c_acol00-add'), findsOneWidget, reason: 'each inner column’s Add on the canvas');
      expect(tester.takeException(), isNull);
    });
  });
}
