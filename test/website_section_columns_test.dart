// Columns while editing a section: the Columns panel first in a
// section's (or columns block's) properties, naming whose columns they
// are, with the number of columns (1 to 4, the same content on every
// screen), what the screen being previewed shows, each screen size's
// columns per row (Automatic or set), and every column's blocks with an
// Add; the canvas toolbar's Columns control and the structure's summary;
// fewer columns ask which remaining column takes the blocks (nothing is
// deleted); more columns are empty; content, ids, images, Tamil and
// settings are kept; save, reopen, duplicate and publish. Synthetic test
// data only.
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
import 'package:montessori_app/modules/public_website/content/blocks/block_limits.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';

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

/// A section `b_sec00001` ("Programmes") of [count] equal columns
/// (`c_col0000<i>`), each holding [perColumn] text blocks, the first with
/// Tamil, the second column an image too; [values] for its settings.
Map<String, dynamic> _section(int count, {int perColumn = 1, Map<String, Object?> values = const {}}) => Map<String, dynamic>.from(BlockRegistry.toMapList(BlockRegistry.parseList([
      {
        'id': 'b_sec00001',
        'type': 'section',
        'v': 1,
        'name': {'en': 'Programmes', 'ta': ''},
        'layout': List.filled(count, '1').join(':'),
        ...values,
        'style': {'background': 'token:sageLight', 'columnGap': '24'},
        'columns': [
          for (var i = 0; i < count; i++)
            {
              'id': 'c_col0000$i',
              'blocks': [
                for (var j = 0; j < perColumn; j++) _text('b_c${i}t${j}0000', ta: j == 0 ? 'தலைப்பு $i' : ''),
                if (i == 1) {'id': 'b_img000001', 'type': 'image', 'v': 1, 'mediaId': 'media_photo_0001', 'aspect': '4:3'},
              ],
            },
        ],
      },
    ])).single as Map);

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parseList([raw]).single as StructuredBlock;

/// Every block id in [b]'s columns, in order.
List<String> _ids(StructuredBlock b) => [for (final c in b.columns('columns')) for (final x in c.blocks) x.id];

void main() {
  Finder key(String k) => find.byKey(Key(k));
  const k = 'website-block-b_sec00001';

  // ------------------------------------------------------------ model
  group('fewer columns: the blocks go where chosen', () {
    test('into any remaining column, in order, at its end; nothing lost; ids kept', () {
      final b = _parse(_section(4, perColumn: 2));
      final into1 = ColumnOps.withLayout(b, '1:1', moveBlocks: true, moveInto: 0);
      final cols = into1.columns('columns');
      expect(cols[0].blocks.map((x) => x.id), ['b_c0t00000', 'b_c0t10000', 'b_c2t00000', 'b_c2t10000', 'b_c3t00000', 'b_c3t10000']);
      expect(cols[1].blocks.map((x) => x.id), ['b_c1t00000', 'b_c1t10000', 'b_img000001']);
      expect(_ids(into1)..sort(), _ids(b)..sort());
      expect(() => ColumnOps.withLayout(b, '1:1', moveBlocks: true, moveInto: 2), throwsStateError, reason: 'not a column that goes');
      expect(ColumnOps.movableInto(b, '1:1', limits: const BlockLimits(maxColumnBlocks: 6)), [0],
          reason: 'with a column limit of 6, column 2 (two texts and an image) has no room for four more');
      expect(ColumnOps.movableInto(b, '1:1'), [0, 1], reason: 'no column limit by default: either column takes them');
      expect(ColumnOps.layoutFor(_parse({..._section(2), 'layout': '1:2'}), 2), '1:2', reason: 'the same count keeps its widths');
      expect(ColumnOps.layoutFor(b, 3), '1:1:1');
    });
  });

  // ------------------------------------------------------------ inspector
  group('the Columns panel', () {
    Future<StructuredBlock Function()> edit(WidgetTester tester, StructuredBlock start, {String screen = 'desktop', double width = 360}) async {
      var current = start;
      tester.view.physicalSize = Size(width, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteBlockForm(
                block: current,
                library: const [],
                generation: 0,
                screen: screen,
                onChanged: (b) => setState(() => current = b as StructuredBlock),
                onAddToColumn: (c, d) => setState(() {
                  final cols = [...current.columns('columns')];
                  cols[c] = cols[c].copyWith(blocks: [...cols[c].blocks, BlockRegistry.create(d)]);
                  current = current.withValue('columns', cols);
                }),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => current;
    }

    String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

    Future<void> tap(WidgetTester tester, String k) async {
      await tester.ensureVisible(key(k).first);
      await tester.pumpAndSettle();
      await tester.tap(key(k).first);
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String dropdown, String option) async {
      await tap(tester, dropdown);
      await tester.tap(key('$dropdown-$option').last);
      await tester.pumpAndSettle();
    }

    testWidgets('first in the properties, naming the section; 2, 3 and 4 columns, each new one empty, the rest unchanged', (tester) async {
      final block = await edit(tester, _parse(_section(1)));
      expect(tester.takeException(), isNull, reason: 'fits a narrow properties panel');
      expect(text(tester, '$k-columns-panel-title'), 'Columns of section “Programmes”');
      final name = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('$k-name-en') == true);
      expect(tester.getTopLeft(key('$k-columns-panel')).dy, lessThan(tester.getTopLeft(name).dy), reason: 'before the section’s text');
      expect(text(tester, '$k-columns-current'), 'One column on every screen.');
      final before = block().columns('columns').single;
      for (final n in [2, 3, 4]) {
        await tap(tester, '$k-column-count-$n');
        final cols = block().columns('columns');
        expect(cols, hasLength(n));
        expect(cols.first.toMap(), before.toMap(), reason: 'the first column, its id and blocks, unchanged');
        expect(cols.skip(1).every((c) => c.blocks.isEmpty), isTrue, reason: 'new columns are empty');
        expect(block().string('layout'), List.filled(n, '1').join(':'));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('fewer columns: asks which column takes the blocks; Cancel changes nothing', (tester) async {
      final block = await edit(tester, _parse(_section(4, perColumn: 1, values: {'desktopColumns': '4'})));
      final start = block().toMap();
      await tap(tester, '$k-column-count-2');
      expect(key('website-columns-layout-dialog'), findsOneWidget);
      expect(find.textContaining('Columns 3 and 4 hold 2 blocks'), findsOneWidget);
      await tap(tester, 'website-columns-layout-cancel');
      expect(block().toMap(), start, reason: 'Cancel keeps everything');

      await tap(tester, '$k-column-count-2');
      await tap(tester, 'website-columns-layout-into-0');
      expect(find.text('Move blocks to column 1'), findsOneWidget);
      await tap(tester, 'website-columns-layout-move');
      final cols = block().columns('columns');
      expect(cols.map((c) => c.blocks.map((x) => x.id).toList()), [
        ['b_c0t00000', 'b_c2t00000', 'b_c3t00000'],
        ['b_c1t00000', 'b_img000001'],
      ]);
      expect((cols[0].blocks[1] as StructuredBlock).text('heading').ta, 'தலைப்பு 2', reason: 'Tamil kept');
      expect(block().option('desktopColumns'), '2', reason: 'capped at the columns it has');
      expect(block().style, start['style'], reason: 'background and gap kept');
    });

    testWidgets('each screen size on its own: Automatic follows the screen above; a set one says so; the previewed one is marked', (tester) async {
      var block = await edit(tester, _parse(_section(3)), screen: 'tablet');
      expect(key('$k-tabletColumns-previewing'), findsOneWidget);
      expect(text(tester, '$k-columns-current'), 'Tablet (previewing): 3 of 3 per row, Automatic.');
      await pick(tester, '$k-desktopColumns', '3');
      await pick(tester, '$k-tabletColumns', '2');
      await pick(tester, '$k-mobileColumns', '1');
      expect([block().option('desktopColumns'), block().option('tabletColumns'), block().option('mobileColumns')], ['3', '2', '1']);
      expect(text(tester, '$k-columns-current'), 'Tablet (previewing): 2 of 3 per row, set for this screen.');
      await pick(tester, '$k-tabletColumns', 'auto');
      await pick(tester, '$k-desktopColumns', '2');
      expect(text(tester, '$k-tabletColumns-status'), 'Automatic: 2 per row', reason: 'inherited from desktop');

      block = await edit(tester, block(), screen: 'mobile');
      expect(key('$k-mobileColumns-previewing'), findsOneWidget);
      expect(text(tester, '$k-columns-current'), 'Phone (previewing): 1 of 3 per row, set for this screen.');
    });

    testWidgets('an Add in every column; a block added to one column only', (tester) async {
      final block = await edit(tester, _parse(_section(3, perColumn: 0)));
      for (final i in [0, 1, 2]) {
        expect(key('website-column-c_col0000$i-panel-add'), findsOneWidget);
      }
      await tap(tester, 'website-column-c_col00002-panel-add');
      await tester.tap(key('website-column-c_col00002-panel-add-text').last);
      await tester.pumpAndSettle();
      expect(block().columns('columns').map((c) => c.blocks.length), [0, 1, 1], reason: 'column 2 had its image; column 3 has the new text');
      expect(find.textContaining('Add a block to column', findRichText: true), findsNothing);
    });

    testWidgets('a narrow panel (320 px): no overflow with four columns', (tester) async {
      await edit(tester, _parse(_section(4, perColumn: 2)), width: 320);
      expect(tester.takeException(), isNull);
      expect(key('$k-column-count-4'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ editor
  group('in the page editor', () {
    late FakeFirebaseFirestore db;
    late WebsiteContentAdminService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<String> pageWith(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Columns', ta: 'நெடுவரிசைகள்'), slug: 'columns-page');
      await db.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

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

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
    StructuredBlock section(WidgetTester tester) => blocks(tester).first as StructuredBlock;
    /// Selects the section by its structure row's title (a click on the
    /// canvas inside a section selects the block there).
    Future<void> selectSection(WidgetTester tester) async {
      await tester.ensureVisible(key('$k-select'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(key('$k-select')) + const Offset(40, 14));
      await tester.pumpAndSettle();
    }

    String chip(WidgetTester tester) => tester.widget<Text>(find.descendant(of: key('$k-columns-chip'), matching: find.byType(Text))).data!;

    testWidgets('a section from before: shown and saved as it was; its columns found from the structure', (tester) async {
      final raw = _section(1);
      final id = await pageWith([raw]);
      await open(tester, id);
      expect(section(tester).toMap(), raw);
      expect(chip(tester), '1 column');
      await tap(tester, key('$k-more'));
      await tap(tester, key('$k-columns'));
      expect(key('$k-columns-panel'), findsOneWidget, reason: '“Columns and layout…” opens the panel');
      await tap(tester, key('website-custom-save-draft'));
      final stored = ((await db.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks'] as List).single as Map;
      expect(Map<String, dynamic>.from(stored), raw, reason: 'nothing new stored');
    });

    testWidgets('canvas toolbar: 1 → 3 columns; blocks added to each column; previews; 3 → 2 into a chosen column; duplicate; save, reopen, publish', (tester) async {
      final id = await pageWith([_section(1)]);
      await open(tester, id);
      await selectSection(tester);
      expect(tester.widget<Text>(key('website-canvas-b_sec00001-columns-count')).data, '1');
      await tap(tester, key('website-canvas-b_sec00001-columns'));
      await tester.tap(key('website-canvas-b_sec00001-columns-3').last);
      await tester.pumpAndSettle();
      expect(section(tester).columns('columns'), hasLength(3));
      expect(chip(tester), '3 columns · Desktop: 3 per row');
      expect(tester.widget<Text>(key('website-canvas-b_sec00001-columns-count')).data, '3');

      // Add a block to each new column from the panel.
      await tap(tester, key('$k-edit'));
      for (final c in section(tester).columns('columns').skip(1).toList()) {
        await tap(tester, key('website-column-${c.id}-panel-add'));
        await tester.tap(key('website-column-${c.id}-panel-add-text').last);
        await tester.pumpAndSettle();
        await tap(tester, key('$k-edit'));
      }
      expect(section(tester).columns('columns').map((c) => c.blocks.length), [1, 1, 1]);
      final added = [for (final c in section(tester).columns('columns').skip(1)) c.blocks.single.id];
      for (final (i, b) in added.indexed) {
        await tap(tester, key('website-block-$b-edit'));
        final f = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('website-block-$b-heading-en') == true);
        await tester.ensureVisible(f);
        await tester.enterText(f, 'Column ${i + 2} text');
        await tester.pumpAndSettle();
      }

      // Tablet two per row; the structure and panel say what the tablet shows.
      await tap(tester, key('$k-edit'));
      await tap(tester, key('website-custom-preview-tablet'));
      await tap(tester, key('$k-tabletColumns'));
      await tester.tap(key('$k-tabletColumns-2').last);
      await tester.pumpAndSettle();
      expect(chip(tester), '3 columns · Tablet: 2 per row');
      expect(tester.widget<Text>(key('$k-columns-current')).data, 'Tablet (previewing): 2 of 3 per row, set for this screen.');
      await tap(tester, key('website-custom-preview-mobile'));
      expect(chip(tester), '3 columns · Phone: 1 per row');
      await tap(tester, key('website-custom-preview-desktop'));
      expect(tester.takeException(), isNull);

      // Fewer: column 3's block goes to column 1, as chosen.
      await selectSection(tester);
      await tap(tester, key('website-canvas-b_sec00001-columns'));
      await tester.tap(key('website-canvas-b_sec00001-columns-2').last);
      await tester.pumpAndSettle();
      await tap(tester, key('website-columns-layout-into-0'));
      await tap(tester, key('website-columns-layout-move'));
      final cols = section(tester).columns('columns');
      expect(cols.map((c) => c.blocks.map((x) => x.id).toList()), [
        ['b_c0t00000', added[1]],
        [added[0]],
      ]);
      expect((cols[0].blocks.first as StructuredBlock).text('heading').ta, 'தலைப்பு 0', reason: 'Tamil kept');
      expect(section(tester).option('tabletColumns'), '2');

      // Duplicate: a copy with new ids and the same columns and settings.
      await tap(tester, key('$k-more'));
      await tap(tester, key('$k-duplicate'));
      final copy = blocks(tester)[1] as StructuredBlock;
      expect(copy.id, isNot('b_sec00001'));
      expect(copy.columns('columns').map((c) => c.blocks.length), [2, 1]);
      expect(copy.option('tabletColumns'), '2');
      expect(_ids(copy).toSet().intersection(_ids(section(tester)).toSet()), isEmpty);

      // Save, reopen, publish.
      final before = [for (final b in blocks(tester)) b.toMap()];
      await tap(tester, key('website-custom-save-draft'));
      await open(tester, id);
      expect([for (final b in blocks(tester)) b.toMap()], before, reason: 'reopened as saved');
      await tap(tester, key('website-custom-publish'));
      if (key('website-custom-publish-confirm').evaluate().isNotEmpty) await tap(tester, key('website-custom-publish-confirm'));
      final live = (await db.collection(WebsiteCollections.livePages).doc(id).get()).data()!;
      expect([for (final b in BlockRegistry.parseList(live['blocks'])) b.toMap()], before, reason: 'published as edited');
    });

    testWidgets('narrow editor and phone preview: the panel, chip and toolbar fit', (tester) async {
      final id = await pageWith([_section(4, perColumn: 2)]);
      await open(tester, id, size: const Size(920, 2400));
      await tap(tester, key('website-editor-toggle-structure'));
      expect(chip(tester), '4 columns · Desktop: 4 per row');
      await selectSection(tester);
      await tap(tester, key('website-custom-preview-mobile'));
      expect(chip(tester), '4 columns · Phone: 1 per row');
      await tap(tester, key('$k-more'));
      await tap(tester, key('$k-columns'));
      expect(key('$k-columns-panel'), findsOneWidget, reason: '“Columns and layout…” opens the panel');
      expect(key('website-canvas-b_sec00001-columns'), findsOneWidget, reason: 'the canvas toolbar, on the phone preview');
      expect(tester.widget<Text>(key('$k-columns-current')).data, 'Phone (previewing): 1 of 4 per row, Automatic.');
      expect(tester.takeException(), isNull);
    });
  });
}
