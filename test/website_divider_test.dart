// The Divider block, configurable: solid, dashed or dotted; its colour
// (the Design panel's line colour); thickness and width per screen; left,
// centre or right; space above and below. Every new setting is stored only
// when set, so dividers saved before are stored and drawn exactly as they
// were. Decorative: screen readers skip it. Synthetic test data only.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/block_list_ops.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

Map<String, dynamic> _divider({String id = 'b_div0000001', Map<String, dynamic> extra = const {}, Map<String, dynamic> style = const {}}) => {
      'id': id,
      'type': 'divider',
      'v': 1,
      'size': 'medium',
      ...extra,
      if (style.isNotEmpty) 'style': style,
    };

StructuredBlock _parse(Map<String, dynamic> m) => BlockRegistry.parse(m) as StructuredBlock;

/// Records what a painter draws.
class _RecordingCanvas implements Canvas {
  final rects = <Rect>[];
  final circles = <(Offset, double)>[];
  final colors = <Color>{};

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add(rect);
    colors.add(paint.color);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles.add((c, radius));
    colors.add(paint.color);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

_RecordingCanvas _paint(String style, Size size, {Color color = Colors.black}) {
  final canvas = _RecordingCanvas();
  DividerLinePainter(style: style, color: color).paint(canvas, size);
  return canvas;
}

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pumpBlocks(WidgetTester tester, List<WebsiteBlock> blocks, {Size size = const Size(1400, 1200), bool interactive = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, interactive: interactive)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect line(WidgetTester tester, [String id = 'b_div0000001']) => tester.getRect(key('public-block-$id-line'));
  DividerLinePainter painter(WidgetTester tester, [String id = 'b_div0000001']) =>
      tester.widget<CustomPaint>(find.descendant(of: key('public-block-$id-line'), matching: find.byType(CustomPaint))).painter! as DividerLinePainter;

  // ------------------------------------------------------------ registration
  group('registration', () {
    test('1–2. in the Add menu, at page level and inside sections, columns and rows', () {
      expect(BlockRegistry.topLevel.map((d) => d.type), contains('divider'));
      for (final container in ['section', 'columns', rowType]) {
        expect(BlockRegistry.nestableIn(container).map((d) => d.type), contains('divider'), reason: container);
      }
      final section = BlockRegistry.parse({
        'id': 'b_sec0000001', 'type': 'section', 'v': 1, 'layout': '1',
        'columns': [{'id': 'c_sec0000001', 'blocks': []}],
      });
      expect(BlockListOps.canInsertInColumn([section], BlockPath(0), 0, BlockRegistry.create(BlockRegistry.divider)), isTrue);
      final (inside, at) = BlockListOps.insertInColumn([section], BlockPath(0), 0, BlockRegistry.create(BlockRegistry.divider));
      expect((BlockListOps.at(inside, at) as StructuredBlock).type, 'divider');
    });

    test('11. a divider saved before: stored exactly as it was, drawn the old way; a new one is subtle', () {
      for (final raw in [_divider(), _divider(extra: {'size': 'large'}, style: {'lineColor': '#CCCCCC', 'width': 'narrow'})]) {
        final block = _parse(raw);
        expect(block.toMap(), raw);
        expect(DividerLine.customised(block), isFalse);
      }
      final made = BlockRegistry.create(BlockRegistry.divider);
      expect(made.toMap().keys.toSet(), {'id', 'type', 'v', 'size'}, reason: 'nothing new stored until set');
      expect([DividerLine.styleOf(made), DividerLine.thicknessOn(made, 'desktop'), DividerLine.widthOn(made, 'desktop'), DividerLine.alignOf(made)], ['solid', 1, 100, 'center']);
    });

    test('12. invalid or missing settings fall back safely; out-of-range ones are reported', () {
      final bad = _parse(_divider(extra: {'lineStyle': 'wavy', 'thickness': 99, 'lineWidth': 0, 'spaceAbove': -4}));
      expect([DividerLine.styleOf(bad), DividerLine.thicknessOn(bad, 'desktop'), DividerLine.widthOn(bad, 'desktop'), DividerLine.spaceAbove(bad)], ['solid', 16, 5, 0]);
      expect(BlockRegistry.blockProblems(bad), containsAll([contains('“wavy” is not a style option'), contains('thickness on desktop must be from 1 to 16 px')]));
      final unreadable = _parse(_divider(extra: {'thickness': 'thick'}));
      expect(DividerLine.thicknessOn(unreadable, 'desktop'), 1, reason: 'unreadable: the default');
      expect(unreadable.toMap()['thickness'], 'thick', reason: 'kept as stored');
    });
  });

  // ------------------------------------------------------------ painting
  group('painting', () {
    test('3. solid, dashed and dotted', () {
      final solid = _paint('solid', const Size(300, 2));
      expect([solid.rects, solid.circles], [[const Rect.fromLTWH(0, 0, 300, 2)], isEmpty]);
      final dashed = _paint('dashed', const Size(300, 2));
      expect(dashed.rects.length, greaterThan(10));
      expect(dashed.rects.every((r) => r.height == 2 && r.width <= 6), isTrue);
      expect(dashed.rects.last.right, lessThanOrEqualTo(300));
      final dotted = _paint('dotted', const Size(300, 4));
      expect([dotted.rects, dotted.circles.length], [isEmpty, greaterThan(20)]);
      expect(dotted.circles.every((c) => c.$2 == 2 && c.$1.dy == 2), isTrue);
      expect(_paint('unknown', const Size(10, 1)).rects, hasLength(1), reason: 'an unknown style paints solid');
    });
  });

  // ------------------------------------------------------------ rendering
  group('rendering', () {
    testWidgets('4–7. colour, thickness, width, alignment and spacing, per screen', (tester) async {
      final block = _parse(_divider(
        extra: {'lineStyle': 'dashed', 'thickness': 4, 'tabletThickness': 3, 'mobileThickness': 2, 'lineWidth': 50, 'tabletLineWidth': 60, 'mobileLineWidth': 80, 'spaceAbove': 40, 'spaceBelow': 10},
        style: {'lineColor': '#AA0000', 'align': 'end'},
      ));
      for (final (size, thickness, percent) in [(const Size(1400, 1200), 4.0, 50.0), (const Size(820, 1200), 3.0, 60.0), (const Size(390, 1200), 2.0, 80.0)]) {
        await pumpBlocks(tester, [block], size: size);
        final box = tester.getRect(key('public-block-b_div0000001-divider'));
        final l = line(tester);
        expect(l.height, thickness, reason: '$size');
        expect(l.width, moreOrLessEquals(box.width * percent / 100, epsilon: 0.5), reason: '$size');
        expect(l.right, moreOrLessEquals(box.right, epsilon: 0.5), reason: 'right-aligned at $size');
        expect(l.top - box.top, moreOrLessEquals(40, epsilon: 0.01), reason: 'space above');
        expect(box.bottom - l.bottom, moreOrLessEquals(10, epsilon: 0.01), reason: 'space below');
        expect([painter(tester).style, painter(tester).color], ['dashed', const Color(0xFFAA0000)]);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('5. left, centre (the default) and right', (tester) async {
      Future<Rect> at(String? align) async {
        await pumpBlocks(tester, [_parse(_divider(extra: {'lineWidth': 40}, style: {'align': ?align}))]);
        return line(tester);
      }

      final box = Rect.fromLTWH(0, 0, 1400, 1);
      final left = await at('start'), centre = await at(null), right = await at('end');
      final page = tester.getRect(key('public-block-b_div0000001-divider'));
      expect(left.left, moreOrLessEquals(page.left, epsilon: 0.5));
      expect(centre.center.dx, moreOrLessEquals(page.center.dx, epsilon: 0.5));
      expect(right.right, moreOrLessEquals(page.right, epsilon: 0.5));
      expect(box.width, 1400);
    });

    testWidgets('11. an old divider is the same Divider as before', (tester) async {
      await pumpBlocks(tester, [_parse(_divider(extra: {'size': 'large'}))]);
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect([divider.height, divider.thickness], [1, 1]);
      expect(key('public-block-b_div0000001-line'), findsNothing);
    });

    testWidgets('10. the editor canvas and the website draw the same line', (tester) async {
      final block = _parse(_divider(extra: {'lineStyle': 'dotted', 'thickness': 3, 'lineWidth': 70}, style: {'lineColor': '#00AA00'}));
      await pumpBlocks(tester, [block]);
      final preview = (line(tester), painter(tester).style, painter(tester).color);
      await pumpBlocks(tester, [block], interactive: true);
      expect((line(tester), painter(tester).style, painter(tester).color), preview);
    });

    testWidgets('13. decorative: nothing for screen readers, nothing focusable', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBlocks(tester, [_parse(_divider(extra: {'lineStyle': 'dashed'}))]);
      expect(find.ancestor(of: key('public-block-b_div0000001-line'), matching: find.byType(ExcludeSemantics)), findsWidgets);
      expect(find.descendant(of: key('public-block-b_div0000001-divider'), matching: find.byType(Focus)), findsNothing);
      expect(find.descendant(of: key('public-block-b_div0000001-divider'), matching: find.byType(InkWell)), findsNothing);
      handle.dispose();
    });
  });

  // ------------------------------------------------------------ editing
  group('in the editor', () {
    test('9. duplicate (new id, same settings), move, hide and delete', () {
      final blocks = [_parse(_divider(extra: {'lineStyle': 'dotted', 'thickness': 2})), _parse(_divider(id: 'b_div0000002'))];
      final (copied, at) = BlockListOps.duplicate(blocks, BlockPath(0));
      final copy = BlockListOps.at(copied, at) as StructuredBlock;
      expect(copy.id, isNot('b_div0000001'));
      expect([copy.string('lineStyle'), copy.values['thickness']], ['dotted', 2]);
      final (moved, _) = BlockListOps.move(blocks, BlockPath(0), 1);
      expect(moved.map((b) => b.id), ['b_div0000002', 'b_div0000001']);
      final hidden = [blocks.first.copyWith(hidden: true), blocks.last];
      expect(BlockRegistry.forVisitors(hidden).map((b) => b.id), ['b_div0000002']);
      expect(BlockListOps.remove(blocks, BlockPath(0)).map((b) => b.id), ['b_div0000002']);
    });

    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

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

    testWidgets('1, 8, 10. added from the menu, set in its panel, previewed, saved, reopened and published', (tester) async {
      late String id;
      await tester.runAsync(() async {
        final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Dividers', ta: ''), slug: 'dividers');
        await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
          'blocks': [
            {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Above', 'ta': 'மேலே'}, 'body': {'en': '', 'ta': ''}},
          ],
        });
        id = created.id;
      });
      await open(tester, id);
      await tap(tester, key('website-blocks-add'));
      await tester.tap(key('website-blocks-add-divider'));
      await tester.pumpAndSettle();
      final added = tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.last as StructuredBlock;
      expect(added.type, 'divider');
      final p = 'website-block-${added.id}';

      await tap(tester, key('$p-group-line'));
      await tap(tester, key('$p-lineStyle'));
      await tester.tap(key('$p-lineStyle-dashed').last);
      await tester.pumpAndSettle();
      await tester.enterText(key('$p-thickness'), '3');
      await tester.enterText(key('$p-lineWidth'), '60');
      await tester.pumpAndSettle();
      await tap(tester, key('$p-group-spacing'));
      await tester.enterText(key('$p-spaceAbove'), '24');
      await tester.pumpAndSettle();
      // Previewed at once on the canvas (drawn scaled to fit the editor).
      final edited = tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.last as StructuredBlock;
      expect([edited.values['thickness'], edited.values['lineWidth']], [3, 60]);
      expect(painter(tester, added.id).style, 'dashed');
      final canvasLine = line(tester, added.id);
      expect(canvasLine.height, greaterThan(1), reason: 'thicker than the default');

      await tap(tester, key('website-custom-save-draft'));
      final stored = ((await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()))!.data()!['blocks'] as List);
      final saved = Map<String, dynamic>.from(stored.last as Map);
      expect([saved['lineStyle'], saved['thickness'], saved['lineWidth'], saved['spaceAbove']], ['dashed', 3, 60, 24]);
      expect(stored.first, {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Above', 'ta': 'மேலே'}, 'body': {'en': '', 'ta': ''}}, reason: 'the rest unchanged');

      await open(tester, id);
      final reopened = tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.last as StructuredBlock;
      expect([reopened.string('lineStyle'), reopened.values['thickness'], reopened.values['lineWidth'], reopened.values['spaceAbove']], ['dashed', 3, 60, 24]);
      expect(painter(tester, added.id).style, 'dashed');

      await tester.runAsync(() async {
        final page = (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
        await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      });
      final live = (await tester.runAsync(() => firestore.collection(WebsiteCollections.livePages).doc(id).get()))!.data()!['blocks'] as List;
      expect((live.last as Map)['lineStyle'], 'dashed');
    });
  });
}
