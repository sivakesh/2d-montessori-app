// Responsive columns in sections (and columns blocks), on the existing
// column model: `layout` is the number of columns on every screen (and
// their widths), `columns` their blocks; `desktopColumns`, `tabletColumns`
// and `mobileColumns` optionally show fewer per row on that screen
// (Automatic, not stored, is how sections were always drawn). Covers the
// shared rule, rendering per screen size (the editor's canvas and the
// website alike), changing the number of columns without losing blocks,
// moving blocks between columns, the "Add section" column presets, the
// inspector's per-screen choices, and a save, reopen and publish
// round-trip. Synthetic test data only.
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
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_limits.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
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

Map<String, dynamic> _text(String id) => {
      'id': id,
      'type': 'text',
      'v': 1,
      'heading': {'en': 'Heading $id', 'ta': 'தலைப்பு'},
      'body': {'en': 'Words.', 'ta': ''},
    };

/// A section `b_sec00001` of [count] equal columns (`c_col0000<i>`), each
/// with [perColumn] text blocks (`b_c<i>t<j>0000`), and [values] (per-row
/// settings, a layout of other widths).
Map<String, dynamic> _section(int count, {int perColumn = 1, Map<String, Object?> values = const {}, Map<String, dynamic> style = const {}}) => {
      'id': 'b_sec00001',
      'type': 'section',
      'v': 1,
      'layout': List.filled(count, '1').join(':'),
      'name': {'en': 'Columns test', 'ta': ''},
      ...values,
      'columns': [
        for (var i = 0; i < count; i++)
          {
            'id': 'c_col0000$i',
            'blocks': [for (var j = 0; j < perColumn; j++) _text('b_c${i}t${j}0000')],
          },
      ],
      if (style.isNotEmpty) 'style': style,
    };

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parseList([raw]).single as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));

  // ------------------------------------------------------------ the rule
  group('columns per row', () {
    test('Automatic is exactly as sections were always drawn', () {
      for (final (count, desktop, tablet, phone) in [(1, 1, 1, 1), (2, 2, 2, 1), (3, 3, 3, 1), (4, 4, 2, 1)]) {
        final b = _parse(_section(count));
        expect([for (final s in ['desktop', 'tablet', 'mobile']) ColumnsPerRow.on(b, s)], [desktop, tablet, phone], reason: '$count columns');
        expect([for (final s in ['desktop', 'tablet', 'mobile']) ColumnsPerRow.own(b, s)], [null, null, null]);
      }
    });

    test('a screen’s own setting wins; tablets follow desktop; phones stay stacked unless set; never more than the columns', () {
      final b = _parse(_section(3, values: {'tabletColumns': '2'}));
      expect([ColumnsPerRow.on(b, 'desktop'), ColumnsPerRow.on(b, 'tablet'), ColumnsPerRow.on(b, 'mobile')], [3, 2, 1], reason: 'desktop 3, tablet 2, phone 1');
      final followed = _parse(_section(4, values: {'desktopColumns': '3'}));
      expect(ColumnsPerRow.on(followed, 'tablet'), 3, reason: 'tablets follow desktop');
      expect(ColumnsPerRow.on(_parse(_section(4, values: {'desktopColumns': '2'})), 'tablet'), 2);
      expect(ColumnsPerRow.on(_parse(_section(2, values: {'mobileColumns': '2'})), 'mobile'), 2, reason: 'phones can be set');
      expect(ColumnsPerRow.on(_parse(_section(2, values: {'desktopColumns': '4'})), 'desktop'), 2, reason: 'never more than it has');
      expect(ColumnsPerRow.on(_parse(_section(3, values: {'desktopColumns': '7'})), 'desktop'), 3, reason: 'an unknown value is Automatic');
    });

    test('stored only when set: a saved section is written back exactly; a setting is written as chosen', () {
      for (final count in [1, 2, 3, 4]) {
        final raw = _section(count);
        final back = BlockRegistry.toMapList(BlockRegistry.parseList([raw])).single;
        expect(back, raw, reason: '$count columns: unchanged, no new keys');
      }
      final set = _parse(_section(3)).withValue('tabletColumns', '2').withValue('mobileColumns', 'auto');
      final map = set.toMap();
      expect(map['tabletColumns'], '2');
      expect(map.containsKey('mobileColumns'), isFalse, reason: 'Automatic is not stored');
      expect(map.containsKey('desktopColumns'), isFalse);
      expect(BlockRegistry.blockProblems(set), isEmpty);
    });

    test('the columns block has the same settings', () {
      final b = BlockRegistry.create(BlockRegistry.columns);
      expect([for (final k in ColumnsPerRow.keys.values) b.definition.field(k)], everyElement(isNotNull));
      expect(ColumnsPerRow.on(b, 'mobile'), 1);
    });
  });

  // ------------------------------------------------------------ counts
  group('changing the number of columns', () {
    test('four to two: nothing lost; the removed columns’ blocks follow at the end of column 2, in order; ids kept', () {
      final b = _parse(_section(4, perColumn: 2, values: {'desktopColumns': '4', 'tabletColumns': '3'}));
      final before = [for (final c in b.columns('columns')) for (final x in c.blocks) x.id];
      final two = ColumnOps.withLayout(b, '1:1', moveBlocks: true);
      final cols = two.columns('columns');
      expect(cols.map((c) => c.id), ['c_col00000', 'c_col00001'], reason: 'the columns kept keep their ids');
      expect(cols[0].blocks.map((x) => x.id), ['b_c0t00000', 'b_c0t10000']);
      expect(cols[1].blocks.map((x) => x.id), ['b_c1t00000', 'b_c1t10000', 'b_c2t00000', 'b_c2t10000', 'b_c3t00000', 'b_c3t10000']);
      expect([for (final c in cols) for (final x in c.blocks) x.id]..sort(), [...before]..sort(), reason: 'every block, once');
      expect((two.option('desktopColumns'), two.option('tabletColumns')), ('2', '2'), reason: 'settings capped at the columns it has');
      expect(() => ColumnOps.withLayout(b, '1:1'), throwsStateError, reason: 'never silently: the editor asks first');
    });

    test('two back to four: new empty columns; nothing duplicated', () {
      final b = _parse(_section(2, perColumn: 2));
      final four = ColumnOps.withLayout(b, '1:1:1:1');
      final cols = four.columns('columns');
      expect(cols, hasLength(4));
      expect(cols.take(2).map((c) => c.id), ['c_col00000', 'c_col00001']);
      expect(cols.skip(2).every((c) => c.blocks.isEmpty), isTrue);
      expect({for (final c in cols) c.id}, hasLength(4), reason: 'fresh ids');
      expect(BlockRegistry.flatten([four]).length, BlockRegistry.flatten([b]).length, reason: 'the same blocks, once each');
    });

    test('removing a column with blocks moves them (or deletes only when asked); per-row settings follow', () {
      final b = _parse(_section(3, values: {'desktopColumns': '3'}));
      final moved = ColumnOps.withColumnRemoved(b, 2, moveInto: 1)!;
      expect(moved.columns('columns')[1].blocks.map((x) => x.id), ['b_c1t00000', 'b_c2t00000']);
      expect(moved.option('desktopColumns'), '2');
    });
  });

  group('moving a block to another column', () {
    test('kept as it is (id and content), at the end of that column', () {
      final blocks = BlockRegistry.parseList([_section(3, perColumn: 2)]);
      final (next, to) = BlockListOps.moveToColumn(blocks, const BlockPath.nested(0, 0, 0), 2);
      final cols = (next.single as StructuredBlock).columns('columns');
      expect(to, const BlockPath.nested(0, 2, 2));
      expect(cols[0].blocks.map((x) => x.id), ['b_c0t10000']);
      expect(cols[2].blocks.map((x) => x.id), ['b_c2t00000', 'b_c2t10000', 'b_c0t00000']);
      expect(cols[2].blocks.last.toMap(), _text('b_c0t00000'));
      expect(BlockListOps.canMoveToColumn(blocks, const BlockPath.nested(0, 0, 0), 0), isFalse, reason: 'not to its own column');
      expect(BlockListOps.canMoveToColumn(blocks, const BlockPath(0), 1), isFalse, reason: 'only blocks inside columns');
    });

    test('not into a full column', () {
      final full = BlockRegistry.parseList([_section(2, perColumn: BlockLimits.defaults.maxColumnBlocks)]);
      expect(BlockListOps.canMoveToColumn(full, const BlockPath.nested(0, 0, 0), 1), isFalse);
      final (same, _) = BlockListOps.moveToColumn(full, const BlockPath.nested(0, 0, 0), 1);
      expect(identical(same, full), isTrue);
    });
  });

  test('Add section offers one to four empty columns, ready to fill', () {
    for (final (id, count) in [('blank', 1), ('columns_2', 2), ('columns_3', 3), ('columns_4', 4)]) {
      final preset = SectionPreset.all.firstWhere((p) => p.id == id);
      final section = preset.create();
      final cols = section.columns('columns');
      expect(cols, hasLength(count), reason: id);
      expect(cols.every((c) => c.blocks.isEmpty), isTrue);
      expect(section.string('layout'), List.filled(count, '1').join(':'), reason: 'equal widths');
      expect(BlockRegistry.blockProblems(section), isEmpty);
      expect(section.toMap().keys.where((k) => k.endsWith('Columns')), isEmpty, reason: 'Automatic on every screen');
    }
  });

  // ------------------------------------------------------------ rendering
  group('on the page', () {
    Future<void> pump(WidgetTester tester, StructuredBlock section, double width, {bool interactive = false}) async {
      tester.view.physicalSize = Size(width, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteDesignScope(
              design: SiteDesign.defaults,
              child: WebsiteBlocksView(blocks: [section], media: const {}, language: PublicLanguage.english, interactive: interactive, spaced: false, fullBleed: true),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow at $width px');
    }

    List<Rect> columns(WidgetTester tester, int count) => [for (var i = 0; i < count; i++) tester.getRect(key('public-block-column-c_col0000$i'))];

    /// The columns' rows: how many columns share each top edge.
    List<int> rows(List<Rect> rects) {
      final tops = <double, int>{};
      for (final r in rects) {
        final top = tops.keys.firstWhere((t) => (t - r.top).abs() < 1, orElse: () => r.top);
        tops[top] = (tops[top] ?? 0) + 1;
      }
      return tops.values.toList();
    }

    testWidgets('Automatic, as before: desktop in a row; tablets in a row (four as two rows of two); phones stacked', (tester) async {
      for (final (count, width, expected) in [
        (3, 1280.0, [3]),
        (3, 820.0, [3]),
        (3, 390.0, [1, 1, 1]),
        (4, 1280.0, [4]),
        (4, 820.0, [2, 2]),
        (4, 390.0, [1, 1, 1, 1]),
        (2, 1280.0, [2]),
        (2, 820.0, [2]),
        (2, 390.0, [1, 1]),
      ]) {
        await pump(tester, _parse(_section(count)), width);
        expect(rows(columns(tester, count)), expected, reason: '$count columns at $width');
      }
    });

    testWidgets('desktop 3, tablet 2, phone 1: each screen as set; a wrapped row keeps equal widths', (tester) async {
      final b = _parse(_section(3, values: {'tabletColumns': '2'}));
      await pump(tester, b, 1280);
      var r = columns(tester, 3);
      expect(rows(r), [3]);
      expect((r[0].width - r[1].width).abs() < 1 && (r[1].width - r[2].width).abs() < 1, isTrue, reason: 'equal widths by default');
      await pump(tester, b, 820);
      r = columns(tester, 3);
      expect(rows(r), [2, 1]);
      expect(r[2].width, moreOrLessEquals(r[0].width, epsilon: 1), reason: 'the last row keeps the widths');
      expect(r[2].left, moreOrLessEquals(r[0].left, epsilon: 1));
      await pump(tester, b, 390);
      r = columns(tester, 3);
      expect(rows(r), [1, 1, 1]);
      expect(r.every((c) => (c.left - r[0].left).abs() < 1), isTrue, reason: 'stacked');
    });

    testWidgets('desktop set to fewer: rows on desktop too', (tester) async {
      await pump(tester, _parse(_section(4, values: {'desktopColumns': '2'})), 1280);
      expect(rows(columns(tester, 4)), [2, 2]);
      await pump(tester, _parse(_section(4, values: {'desktopColumns': '1'})), 1280);
      expect(rows(columns(tester, 4)), [1, 1, 1, 1]);
    });

    testWidgets('phones set to two, even at 320 px: side by side, inside the screen, never overflowing', (tester) async {
      final b = _parse(_section(4, values: {'mobileColumns': '2'}, style: {'columnGap': '16'}));
      for (final width in [390.0, 320.0]) {
        await pump(tester, b, width);
        final r = columns(tester, 4);
        expect(rows(r), [2, 2], reason: '$width');
        expect(r.every((c) => c.width > 0 && c.left >= 0 && c.right <= width), isTrue, reason: 'within the screen at $width');
        expect(r[1].left - r[0].right, moreOrLessEquals(16, epsilon: 0.5), reason: 'the configured gap');
      }
    });

    testWidgets('the column gap and unequal widths still apply when all columns are in one row', (tester) async {
      final b = _parse({..._section(2, style: {'columnGap': '24'}), 'layout': '1:2'});
      await pump(tester, b, 1280);
      final r = columns(tester, 2);
      expect(r[1].left - r[0].right, moreOrLessEquals(24, epsilon: 0.5));
      expect(r[1].width / r[0].width, moreOrLessEquals(2, epsilon: 0.05), reason: 'wider right, as before');
    });

    testWidgets('the editor’s canvas and the published page lay columns out alike', (tester) async {
      final b = _parse(_section(3, values: {'tabletColumns': '2'}));
      for (final width in [1280.0, 820.0, 390.0]) {
        await pump(tester, b, width, interactive: true);
        final canvas = [for (final c in columns(tester, 3)) c.size];
        final published = BlockRegistry.withoutHidden(BlockRegistry.parseList(BlockRegistry.toMapList([b]))).single as StructuredBlock;
        await pump(tester, published, width);
        expect([for (final c in columns(tester, 3)) c.size], canvas, reason: '$width');
      }
    });
  });

  // ------------------------------------------------------------ inspector
  group('the inspector', () {
    Future<StructuredBlock Function()> edit(WidgetTester tester, StructuredBlock start) async {
      var current = start;
      tester.view.physicalSize = const Size(420, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteBlockForm(block: current, library: const [], generation: 0, onChanged: (b) => setState(() => current = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => current;
    }

    const k = 'website-block-b_sec00001';
    String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

    Future<void> pick(WidgetTester tester, String dropdown, String option) async {
      await tester.ensureVisible(key(dropdown));
      await tester.tap(key(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(key('$dropdown-$option').last);
      await tester.pumpAndSettle();
    }

    testWidgets('every screen size, Automatic or its own, marked as which; the summary follows', (tester) async {
      final block = await edit(tester, _parse(_section(3)));
      expect(tester.takeException(), isNull, reason: 'fits a narrow properties panel');
      expect(key('$k-screens-heading'), findsOneWidget, reason: 'in plain view, not folded away');
      expect(find.text('Columns (all devices)'), findsOneWidget);
      expect(text(tester, '$k-desktopColumns-status'), 'Automatic: 3 per row');
      expect(text(tester, '$k-tabletColumns-status'), 'Automatic: 3 per row');
      expect(text(tester, '$k-mobileColumns-status'), 'Automatic: 1 per row');
      expect(text(tester, '$k-layout-screens'), 'Per row: desktop 3 · tablet 3 · phone 1');

      await pick(tester, '$k-tabletColumns', '2');
      expect(block().option('tabletColumns'), '2');
      expect(text(tester, '$k-tabletColumns-status'), 'Set for this screen: 2 per row');
      expect(text(tester, '$k-layout-screens'), 'Per row: desktop 3 · tablet 2 (set) · phone 1');

      await pick(tester, '$k-desktopColumns', '2');
      await pick(tester, '$k-tabletColumns', 'auto');
      expect(block().toMap().containsKey('tabletColumns'), isFalse, reason: 'Automatic again: not stored');
      expect(text(tester, '$k-tabletColumns-status'), 'Automatic: 2 per row', reason: 'inherited from desktop');
      expect(tester.widget<Text>(key('$k-tabletColumns-auto').last).data, 'Automatic (2 per row, from desktop)');

      await pick(tester, '$k-mobileColumns', '2');
      expect(block().option('mobileColumns'), '2');
    });

    testWidgets('only as many as the section has; fewer columns (after asking) cap the settings', (tester) async {
      final block = await edit(tester, _parse(_section(4, values: {'desktopColumns': '4'})));
      await tester.ensureVisible(key('$k-desktopColumns'));
      await tester.tap(key('$k-desktopColumns'));
      await tester.pumpAndSettle();
      expect(key('$k-desktopColumns-4'), findsWidgets);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      await pick(tester, '$k-layout', '1:1');
      expect(find.text('Fewer columns'), findsOneWidget, reason: 'asks before moving blocks');
      await tester.tap(key('website-columns-layout-move'));
      await tester.pumpAndSettle();
      expect(block().columns('columns'), hasLength(2));
      expect(BlockRegistry.flatten([block()]).length, 5, reason: 'the section and its four blocks');
      expect(block().option('desktopColumns'), '2');
      expect(text(tester, '$k-desktopColumns-status'), 'Set for this screen: 2 per row');
      await tester.ensureVisible(key('$k-desktopColumns'));
      await tester.tap(key('$k-desktopColumns'));
      await tester.pumpAndSettle();
      expect(key('$k-desktopColumns-3'), findsNothing, reason: 'no more than two now');
      expect(tester.takeException(), isNull);
    });

    testWidgets('one column: no per-screen choices beyond one', (tester) async {
      await edit(tester, _parse(_section(1)));
      expect(key('$k-layout-screens'), findsNothing);
      expect(text(tester, '$k-desktopColumns-status'), 'Automatic: 1 per row');
    });
  });

  // ------------------------------------------------------------ editor
  group('in the page editor', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<String> pageWith(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Columns', ta: 'நெடுவரிசைகள்'), slug: 'columns-test');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    Future<void> open(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1400, 2400);
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

    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
    StructuredBlock section(WidgetTester tester) => blocks(tester).last as StructuredBlock;
    List<List<String>> types(WidgetTester tester) => [for (final c in section(tester).columns('columns')) [for (final b in c.blocks) b.type]];

    Future<void> addTo(WidgetTester tester, int column, String type) async {
      final id = section(tester).columns('columns')[column].id;
      await tap(tester, key('website-column-$id-add'));
      await tester.tap(key('website-column-$id-add-$type').last);
      await tester.pumpAndSettle();
    }

    Future<void> heading(WidgetTester tester, String blockId, String text) async {
      final f = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('website-block-$blockId-heading-en') == true);
      await tester.ensureVisible(f);
      await tester.enterText(f, text);
      await tester.pumpAndSettle();
    }

    testWidgets('three columns from Add section; blocks added, moved, duplicated and deleted in each on their own; per-screen settings; previews; save, reopen, publish', (tester) async {
      final id = await pageWith(const []);
      await open(tester, id);

      // Add section → Three columns: three empty columns, each with Add.
      await tap(tester, key('website-sections-add'));
      expect(find.text('Three columns'), findsWidgets, reason: 'offered in the menu (and the empty page’s own list)');
      await tester.tap(key('website-sections-add-columns_3'));
      await tester.pumpAndSettle();
      final cols = section(tester).columns('columns');
      expect(tester.takeException(), isNull, reason: 'three empty columns on the canvas');
      expect(cols, hasLength(3));
      for (final (i, c) in cols.indexed) {
        expect(find.text('Column ${i + 1} (empty)'), findsOneWidget);
        expect(key('website-column-${c.id}-add'), findsOneWidget, reason: 'an Add in every column');
      }

      // Each column on its own.
      await addTo(tester, 0, 'text');
      await addTo(tester, 0, 'text');
      await addTo(tester, 1, 'text');
      await addTo(tester, 2, 'divider');
      expect(types(tester), [['text', 'text'], ['text'], ['divider']]);
      final texts = [for (final c in section(tester).columns('columns')) for (final b in c.blocks) if (b.type == 'text') b.id];
      for (final (i, t) in texts.indexed) {
        await tap(tester, key('website-block-$t-select'));
        await tap(tester, key('website-block-$t-edit'));
        await heading(tester, t, 'Text ${i + 1}');
      }

      // Move the second text of column 1 to column 3.
      final second = texts[1];
      await tap(tester, key('website-block-$second-more'));
      expect(key('website-block-$second-to-column-0'), findsNothing, reason: 'not its own column');
      expect(key('website-block-$second-to-column-1'), findsOneWidget);
      await tester.tap(key('website-block-$second-to-column-2').last);
      await tester.pumpAndSettle();
      expect(types(tester), [['text'], ['text'], ['divider', 'text']]);
      expect(section(tester).columns('columns')[2].blocks.last.id, second, reason: 'the same block, moved');

      // Duplicate in column 2, reorder there, then delete the copy.
      final middle = texts[2];
      await tap(tester, key('website-block-$middle-more'));
      await tap(tester, key('website-block-$middle-duplicate'));
      expect(types(tester), [['text'], ['text', 'text'], ['divider', 'text']]);
      final copy = section(tester).columns('columns')[1].blocks[1].id;
      expect(copy, isNot(middle));
      await tap(tester, key('website-block-$copy-up'));
      expect(section(tester).columns('columns')[1].blocks.first.id, copy);
      await tap(tester, key('website-block-$copy-more'));
      await tap(tester, key('website-block-$copy-delete'));
      await tap(tester, key('website-block-delete-confirm'));
      expect(types(tester), [['text'], ['text'], ['divider', 'text']]);

      // Tablets two per row.
      final sid = section(tester).id;
      await tap(tester, key('website-block-$sid-select'));
      await tap(tester, key('website-block-$sid-edit'));
      await tap(tester, key('website-block-$sid-tabletColumns'));
      await tester.tap(key('website-block-$sid-tabletColumns-2').last);
      await tester.pumpAndSettle();
      expect(section(tester).option('tabletColumns'), '2');

      // The previews follow at once.
      List<int> previewRows() {
        final r = [for (final c in section(tester).columns('columns')) tester.getRect(key('public-block-column-${c.id}'))];
        final tops = <int>[];
        for (final x in r) {
          if (tops.isEmpty || (x.top - r[r.indexOf(x) - 1].top).abs() > 1) {
            tops.add(1);
          } else {
            tops[tops.length - 1]++;
          }
        }
        return tops;
      }

      expect(previewRows(), [3], reason: 'desktop');
      expect(tester.takeException(), isNull, reason: 'desktop preview');
      await tap(tester, key('website-custom-preview-tablet'));
      expect(previewRows(), [2, 1], reason: 'tablet');
      expect(tester.takeException(), isNull, reason: 'tablet preview');
      await tap(tester, key('website-custom-preview-mobile'));
      expect(previewRows(), [1, 1, 1], reason: 'phone');
      expect(tester.takeException(), isNull, reason: 'phone preview');
      await tap(tester, key('website-custom-preview-desktop'));
      expect(previewRows(), [3]);
      expect(tester.takeException(), isNull);

      // Save, reopen, publish.
      final before = section(tester).toMap();
      await tap(tester, key('website-custom-save-draft'));
      final stored = (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks'] as List;
      expect(Map<String, dynamic>.from(stored.single as Map), before);
      expect((stored.single as Map)['tabletColumns'], '2');
      expect((stored.single as Map).containsKey('mobileColumns'), isFalse);
      await open(tester, id);
      expect(section(tester).toMap(), before, reason: 'reopened unchanged: ids, order, settings');
      await tap(tester, key('website-custom-publish'));
      if (key('website-custom-publish-confirm').evaluate().isNotEmpty) await tap(tester, key('website-custom-publish-confirm'));
      final live = (await firestore.collection(WebsiteCollections.livePages).doc(id).get()).data()!;
      final published = BlockRegistry.parseList(live['blocks'] as List).single as StructuredBlock;
      expect(published.toMap(), before, reason: 'published as edited');
      expect([for (final s in ['desktop', 'tablet', 'mobile']) ColumnsPerRow.on(published, s)], [3, 2, 1]);
    });

    testWidgets('an existing section loads and saves unchanged', (tester) async {
      final raw = {..._section(2, perColumn: 2), 'layout': '2:1'};
      final id = await pageWith([raw]);
      await open(tester, id);
      expect(section(tester).toMap(), raw);
      await tap(tester, key('website-block-b_c0t00000-select'));
      await tap(tester, key('website-block-b_c0t00000-edit'));
      await heading(tester, 'b_c0t00000', 'Edited');
      await tap(tester, key('website-custom-save-draft'));
      final stored = Map<String, dynamic>.from(((await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks'] as List).single as Map);
      expect(stored.keys.where((k) => k.endsWith('Columns')), isEmpty, reason: 'no new settings written');
      expect(stored['layout'], '2:1');
      expect([for (final c in stored['columns'] as List) (c as Map)['id']], ['c_col00000', 'c_col00001']);
    });
  });
}
