// The page block limit and section padding.
// - Limit: one page-wide limit (BlockLimits.pageMaxBlocks, 150), counting
//   every block once (sections, columns blocks, the blocks inside them,
//   hidden ones); a section (or columns block) is added only with room for
//   a block inside it, so it is never left empty and unusable; the editor
//   says why when the page is full; pages with many sections save, reload
//   and edit; a page stored over the limit still loads.
// - Section padding: top and bottom for desktop, tablets and phones
//   (tablets follow desktop, phones the tablet), 0–200 px, zero a value;
//   stored as the shared block padding (`blockPadding`), so there is one
//   setting; a section without it is drawn as before (its earlier padding,
//   else 48 px, at most 48 on phones). Synthetic test data only.
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
import 'package:montessori_app/modules/public_website/content/blocks/block_spacing.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/block_spacing_box.dart';
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

const _desktop = Size(1400, 3000);
const _tablet = Size(820, 3000);
const _phone = Size(390, 3000);
const _narrow = Size(320, 3000);

String _pad(int n, int width) => n.toString().padLeft(width, '0');

Map<String, dynamic> _text(String id, {String heading = 'Heading', Map<String, dynamic> style = const {}}) => {
      'id': id,
      'type': 'text',
      'v': 1,
      'heading': {'en': '$heading $id', 'ta': 'தலைப்பு'},
      'body': {'en': 'Words.', 'ta': ''},
      if (style.isNotEmpty) 'style': style,
    };

/// A section with [children] text blocks in one column (`b_s<n>`, its
/// texts `b_s<n>t<j>`).
Map<String, dynamic> _section(int n, {int children = 3, Map<String, dynamic> style = const {}}) => {
      'id': 'b_s${_pad(n, 6)}',
      'type': 'section',
      'v': 1,
      'layout': '1',
      'name': {'en': 'Section $n', 'ta': ''},
      'columns': [
        {
          'id': 'c_s${_pad(n, 6)}',
          'blocks': [for (var j = 0; j < children; j++) _text('b_s${_pad(n, 6)}t$j')],
        },
      ],
      if (style.isNotEmpty) 'style': style,
    };

/// [sections] sections of 1 + 3 blocks, then [loose] top-level text blocks.
List<Map<String, dynamic>> _page({required int sections, int loose = 0}) => [
      for (var i = 0; i < sections; i++) _section(i),
      for (var i = 0; i < loose; i++) _text('b_loose${_pad(i, 5)}'),
    ];

List<WebsiteBlock> _parse(List<Map<String, dynamic>> raw) => BlockRegistry.parseList(raw);

void main() {
  Finder key(String k) => find.byKey(Key(k));

  // ------------------------------------------------------------ limit
  group('the page block limit', () {
    test('one page-wide limit of 150, counting every block once: sections, columns, blocks inside them, hidden ones', () {
      expect(BlockLimits.defaults.maxBlocks, BlockLimits.pageMaxBlocks);
      expect(BlockLimits.pageMaxBlocks, 150);
      final blocks = _parse([
        _section(1),
        {
          'id': 'b_cols000001',
          'type': 'columns',
          'v': 1,
          'layout': '1:1',
          'columns': [
            {'id': 'c_cols000001', 'blocks': [_text('b_colt000001')]},
            {'id': 'c_cols000002', 'blocks': [_text('b_colt000002'), {..._text('b_colt000003'), 'hidden': true}]},
          ],
        },
        {..._text('b_hidden00001'), 'hidden': true},
      ]);
      expect(BlockRegistry.flatten(blocks).length, 4 + 4 + 1);
    });

    test('40 blocks is no longer full; a section is added only with room for a block inside it', () {
      final forty = _parse(_page(sections: 10));
      expect(BlockRegistry.flatten(forty).length, 40);
      expect(BlockListOps.pageHasRoom(forty), isTrue);
      for (final preset in SectionPreset.all) {
        expect(BlockListOps.canInsert(forty, preset.create()), isTrue, reason: preset.id);
      }
      final blank = SectionPreset.all.firstWhere((p) => p.id == 'blank');
      final near = _parse(_page(sections: 37, loose: 1)); // 149
      expect(BlockRegistry.flatten(near).length, 149);
      expect(BlockListOps.canInsert(near, blank.create()), isFalse, reason: 'it would fill the page with an empty section');
      expect(BlockListOps.canAdd(near, BlockRegistry.section), isFalse);
      expect(BlockListOps.canAdd(near, BlockRegistry.columns), isFalse);
      expect(BlockListOps.canAdd(near, BlockRegistry.text), isTrue, reason: 'one more block still fits');
      final room = _parse(_page(sections: 37)); // 148
      expect(BlockListOps.canInsert(room, blank.create()), isTrue, reason: 'the section and a block in it');
      final withBlank = BlockListOps.insert(room, BlockPath(room.length), blank.create());
      expect(BlockListOps.columnHasRoom(withBlank, withBlank.length - 1, 0), isTrue, reason: 'its column can take a block');
      final full = _parse(_page(sections: 37, loose: 2)); // 150
      expect(BlockListOps.pageHasRoom(full), isFalse);
      expect(BlockListOps.canAdd(full, BlockRegistry.text), isFalse);
    });

    test('saving checks the same limit; many sections save and reload exactly; Tamil kept', () {
      final page = _page(sections: 30); // 120 blocks
      final blocks = _parse(page);
      expect(BlockRegistry.validate(blocks), isEmpty);
      expect(BlockRegistry.toMapList(blocks), page, reason: 'written back exactly');
      expect((BlockRegistry.parseList(BlockRegistry.toMapList(blocks))[5] as StructuredBlock).columns('columns').single.blocks.first.toMap()['heading'],
          {'en': 'Heading b_s000005t0', 'ta': 'தலைப்பு'});
      expect(BlockRegistry.validate(_parse(_page(sections: 37, loose: 2))), isEmpty, reason: '150');
      expect(BlockRegistry.validate(_parse(_page(sections: 37, loose: 3))), ['A page can have at most 150 blocks.']);
    });
  });

  group('the page block limit in the editor', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<String> pageWith(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Home test', ta: 'முகப்பு'), slug: 'home-test');
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

    List<WebsiteBlock> editorBlocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
    String used(WidgetTester tester) => tester.widget<Text>(key('website-custom-uses-blocks')).data!;

    testWidgets('past 40: a new section takes blocks; saved and reopened with every block', (tester) async {
      final id = await pageWith(_page(sections: 10)); // 40
      await open(tester, id);
      expect(used(tester), startsWith('40 of 150 blocks used'));
      await tap(tester, key('website-sections-add'));
      await tester.tap(key('website-sections-add-blank'));
      await tester.pumpAndSettle();
      final section = editorBlocks(tester).last as StructuredBlock;
      expect(section.type, 'section');
      final column = section.columns('columns').single;
      await tap(tester, key('website-canvas-column-${column.id}-add'));
      await tester.tap(key('website-canvas-column-${column.id}-add-text'));
      await tester.pumpAndSettle();
      expect((editorBlocks(tester).last as StructuredBlock).columns('columns').single.blocks.single.type, 'text', reason: 'the new section’s column accepts a block');
      expect(used(tester), startsWith('42 of 150'));
      final added = (editorBlocks(tester).last as StructuredBlock).columns('columns').single.blocks.single;
      final heading = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('website-block-${added.id}-heading-en') == true);
      await tester.ensureVisible(heading);
      await tester.enterText(heading, 'New content');
      await tester.pumpAndSettle();

      await tap(tester, key('website-custom-save-draft'));
      final stored = (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks'] as List;
      expect(BlockRegistry.flatten(BlockRegistry.parseList(stored)).length, 42);
      await open(tester, id);
      expect(used(tester), startsWith('42 of 150'));
      expect(((stored.first as Map)['columns'] as List).single['blocks'][0]['heading'], {'en': 'Heading b_s000000t0', 'ta': 'தலைப்பு'});
    });

    testWidgets('near and at the limit: sections that would be empty are refused, the reason shown', (tester) async {
      final id = await pageWith(_page(sections: 37, loose: 1)); // 149
      await open(tester, id);
      expect(key('website-custom-blocks-limit'), findsOneWidget, reason: 'nearly full');
      await tap(tester, key('website-sections-add'));
      final blank = tester.widget<PopupMenuItem<SectionPreset>>(key('website-sections-add-blank'));
      expect(blank.enabled, isFalse);
      expect(find.text('No room on this page for this section and a block in it'), findsWidgets);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tap(tester, key('website-blocks-add'));
      expect(tester.widget<PopupMenuItem<BlockDefinition>>(key('website-blocks-add-section')).enabled, isFalse);
      await tester.tap(key('website-blocks-add-text'));
      await tester.pumpAndSettle();
      expect(used(tester), startsWith('150 of 150'));
      expect(tester.widget<Text>(key('website-custom-blocks-limit')).data, contains('room for 150 blocks'));
      expect(tester.widget<PopupMenuButton<SectionPreset>>(key('website-sections-add')).enabled, isFalse);
      expect(tester.widget<PopupMenuButton<BlockDefinition>>(key('website-blocks-add')).enabled, isFalse);
      expect(BlockRegistry.validate(editorBlocks(tester)), isNot(contains(startsWith('A page can have'))), reason: 'within the limit when saved');
    });

    testWidgets('a page stored over the limit still loads and can be edited down', (tester) async {
      final id = await pageWith(_page(sections: 38)); // 152
      await open(tester, id);
      expect(used(tester), startsWith('152 of 150'));
      expect(editorBlocks(tester), hasLength(38));
      expect(tester.widget<PopupMenuButton<BlockDefinition>>(key('website-blocks-add')).enabled, isFalse);
      expect(BlockRegistry.validate(editorBlocks(tester)), ['A page can have at most 150 blocks.'], reason: 'saving explains it rather than failing silently');
    });
  });

  // ------------------------------------------------------------ padding
  group('section padding on the page', () {
    Future<void> pump(WidgetTester tester, List<WebsiteBlock> blocks, {Size at = _desktop, bool interactive = true}) async {
      tester.view.physicalSize = at;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteDesignScope(
              design: SiteDesign.defaults,
              child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, interactive: interactive, spaced: false, fullBleed: true),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    StructuredBlock section(Map<String, dynamic> style) => _parse([_section(1, children: 1, style: {'background': 'token:sageLight', ...style})]).single as StructuredBlock;
    Rect band(WidgetTester tester) => tester.getRect(key('public-section-b_s000001'));
    Rect content(WidgetTester tester) => tester.getRect(find.text('Heading b_s000001t0'));
    (double, double) gaps(WidgetTester tester) {
      double r(double v) => (v * 100).roundToDouble() / 100;
      return (r(content(tester).top - band(tester).top), r(band(tester).bottom - tester.getRect(find.text('Words.')).bottom));
    }

    testWidgets('no override: exactly as before (48 px, its earlier setting, at most 48 on phones)', (tester) async {
      await pump(tester, [section({})]);
      expect(tester.widget<Container>(key('public-section-b_s000001')).padding, const EdgeInsets.only(top: 48, bottom: 48));
      expect(find.byType(FitPadding), findsNothing, reason: 'nothing added');
      await pump(tester, [section({'padding': '96', 'paddingBottom': '16'})]);
      expect(tester.widget<Container>(key('public-section-b_s000001')).padding, const EdgeInsets.only(top: 96, bottom: 16));
      await pump(tester, [section({'padding': '96'})], at: _phone);
      expect(tester.widget<Container>(key('public-section-b_s000001')).padding, const EdgeInsets.only(top: 48, bottom: 48));
    });

    testWidgets('top and bottom set on their own; zero is zero, not Automatic; the background reaches the edges', (tester) async {
      await pump(tester, [section({BlockSpacing.padding: {'desktop': {'top': 0, 'bottom': 12}}})]);
      expect(gaps(tester), (0.0, 12.0));
      expect(band(tester).left, 0, reason: 'edge to edge');
      expect(band(tester).width, _desktop.width);
      final decoration = tester.widget<Container>(key('public-section-b_s000001')).decoration! as BoxDecoration;
      expect(decoration.color, isNotNull, reason: 'the background is the band itself: no gap between it and its padding');
      await pump(tester, [section({BlockSpacing.padding: {'desktop': {'bottom': 0}}})]);
      expect(gaps(tester), (48.0, 0.0), reason: 'top stays Automatic');
    });

    testWidgets('desktop, tablets and phones: their own values, tablets following desktop, phones the tablet', (tester) async {
      final style = {
        'padding': '96',
        BlockSpacing.padding: {
          'desktop': {'top': 120, 'bottom': 80},
          'tablet': {'top': 40},
          'mobile': {'bottom': 0},
        },
      };
      final seen = <Size, (double, double)>{};
      for (final s in [_desktop, _tablet, _phone]) {
        await pump(tester, [section(style)], at: s);
        seen[s] = gaps(tester);
      }
      expect(seen[_desktop], (120.0, 80.0));
      expect(seen[_tablet], (40.0, 80.0), reason: 'its own top; desktop’s bottom');
      expect(seen[_phone], (40.0, 0.0), reason: 'the tablet’s top; its own bottom (no 48 px cap on a value set)');
    });

    testWidgets('never doubled: replaces the earlier section padding; blocks inside keep only their own', (tester) async {
      await pump(tester, [section({'padding': '96', BlockSpacing.padding: {'desktop': {'top': 10}}})]);
      expect(gaps(tester).$1, 10, reason: 'not 96 + 10');
      final withChild = _parse([
        {
          ..._section(1, children: 0, style: {'background': 'token:sageLight', BlockSpacing.padding: {'desktop': {'top': 10}}}),
          'columns': [
            {'id': 'c_s000001', 'blocks': [_text('b_s000001t0', style: {BlockSpacing.padding: {'desktop': {'top': 6}}})]},
          ],
        },
      ]);
      await pump(tester, withChild);
      expect(gaps(tester).$1, 16, reason: 'the section’s 10 and the block’s own 6, each once');
      expect(find.byType(FitPadding), findsNWidgets(2));
    });

    testWidgets('the editor’s canvas, the visitor preview and the published page draw the same', (tester) async {
      final raw = {BlockSpacing.padding: {'desktop': {'top': 4, 'bottom': 20}, 'mobile': {'top': 0}}};
      for (final s in [_desktop, _phone]) {
        await pump(tester, [section(raw)], at: s, interactive: false); // the canvas
        final canvas = (band(tester), content(tester));
        await pump(tester, [section(raw)], at: s); // the preview
        final preview = (band(tester), content(tester));
        final published = BlockRegistry.withoutHidden(BlockRegistry.parseList(BlockRegistry.toMapList([section(raw)])));
        await pump(tester, published, at: s);
        expect(preview, canvas, reason: '$s');
        expect((band(tester), content(tester)), canvas, reason: '$s');
      }
    });

    testWidgets('narrow screens: large values never overflow sideways', (tester) async {
      await pump(tester, [section({BlockSpacing.padding: {'desktop': {'top': 200, 'bottom': 200, 'left': 200, 'right': 200}}})], at: _narrow);
      expect(tester.takeException(), isNull);
      expect(gaps(tester), (200.0, 200.0));
      expect(content(tester).left, greaterThanOrEqualTo(0));
      expect(content(tester).right, lessThanOrEqualTo(_narrow.width));
    });
  });

  group('section padding in the editor', () {
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
              child: WebsiteStyleEditor(block: current, design: SiteDesign.defaults, onChanged: (b) => setState(() => current = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => current;
    }

    const k = 'website-block-b_s000001-style-section-padding';
    String status(WidgetTester tester, String side) => tester.widget<Text>(key('$k-$side-status')).data!;

    testWidgets('first in the section’s Design, open; the earlier dropdowns replaced; zero, each side, reset; one stored setting', (tester) async {
      final block = await edit(tester, _parse([_section(1, style: {'padding': '96'})]).single as StructuredBlock);
      expect(tester.takeException(), isNull, reason: 'fits a narrow properties panel');
      expect(key('$k-top'), findsOneWidget, reason: 'open, easy to find');
      expect(tester.getTopLeft(key('website-block-b_s000001-style-section-padding-group')).dy,
          lessThan(tester.getTopLeft(key('website-block-b_s000001-style-background')).dy));
      expect(key('website-block-b_s000001-style-padding'), findsNothing, reason: 'not two controls for one thing');
      expect(key('$k-left'), findsNothing);
      expect(status(tester, 'top'), 'Automatic: 96', reason: 'its earlier setting');

      await tester.enterText(key('$k-top'), '0');
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': {'top': 0}});
      expect(status(tester, 'top'), 'Set');
      expect(block().style['padding'], '96', reason: 'kept (it is what Automatic is)');
      await tester.enterText(key('$k-bottom'), '24');
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': {'top': 0, 'bottom': 24}});

      await tester.tap(key('$k-screen-mobile'));
      await tester.pumpAndSettle();
      expect(status(tester, 'top'), 'From desktop: 0');
      await tester.enterText(key('$k-bottom'), '8');
      await tester.pump();
      await tester.tap(key('$k-screen-tablet'));
      await tester.pumpAndSettle();
      expect(status(tester, 'bottom'), 'From desktop: 24');
      await tester.tap(key('$k-screen-mobile'));
      await tester.pumpAndSettle();
      await tester.tap(key('$k-bottom-reset'));
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': {'top': 0, 'bottom': 24}}, reason: 'one value reset');

      await tester.tap(key('$k-link'));
      await tester.pump();
      await tester.enterText(key('$k-top'), '16');
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': {'top': 0, 'bottom': 24}, 'mobile': {'top': 16, 'bottom': 16}}, reason: 'linked: top and bottom');

      // Left and right (set in the shared Padding group) are kept by Reset all.
      final withSides = BlockSpacing.withValues(block().style[BlockSpacing.padding], 'desktop', {'left': 20});
      final b2 = await edit(tester, block().copyWith(style: {...block().style, BlockSpacing.padding: withSides}));
      await tester.ensureVisible(key('$k-reset-all'));
      await tester.tap(key('$k-reset-all'));
      await tester.pump();
      expect(b2().style[BlockSpacing.padding], {'desktop': {'left': 20}}, reason: 'top and bottom Automatic on every screen size');
      expect(tester.widget<Text>(key('website-block-b_s000001-style-blockPadding-group-summary')).data, 'Desktop: left 20', reason: 'the same setting as the shared Padding');
    });

    testWidgets('other blocks are unchanged: no section padding control', (tester) async {
      await edit(tester, _parse([_text('b_s000001')]).single as StructuredBlock);
      expect(key('website-block-b_s000001-style-section-padding-group'), findsNothing);
      expect(key('website-block-b_s000001-style-blockPadding-group'), findsOneWidget);
    });
  });
}
