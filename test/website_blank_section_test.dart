// The Blank section made configurable: a section's optional small
// heading, heading and description, and its columns added, removed
// (never losing blocks without asking), reordered and laid out from one
// to four, in the editor, the public site and storage. Synthetic test data
// only; nothing outside fake Firestore is read or written.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/block_list_ops.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _desktop = Size(1400, 2400);
const _tablet = Size(820, 2400);
const _phone = Size(390, 2400);
const _narrow = Size(320, 2400);
const _sectionId = 'b_section0001';

const _headerKeys = ['eyebrow', 'heading', 'description'];

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parse(raw) as StructuredBlock;

/// The stored map, as JSON (types as Firestore would hold them).
Object? _plain(Object? v) => jsonDecode(jsonEncode(v));

Map<String, dynamic> _textBlock(String id, String heading) => {'id': id, 'type': 'text', 'v': 1, 'heading': {'en': heading, 'ta': ''}, 'body': {'en': '', 'ta': ''}};

/// A stored section of [layout]; column i holds [blocksPerColumn][i] text
/// blocks; [header] adds the optional text.
Map<String, dynamic> _stored(String layout, {List<int>? blocksPerColumn, Map<String, Object?> header = const {}, Map<String, dynamic>? style}) {
  final n = columnLayouts[layout]!.length;
  final counts = blocksPerColumn ?? List.filled(n, 1);
  return {
    'id': _sectionId,
    'type': 'section',
    'v': 1,
    'name': {'en': 'Section', 'ta': ''},
    ...header,
    'layout': layout,
    'columns': [
      for (var i = 0; i < n; i++)
        {
          'id': 'c_column000$i',
          'blocks': [for (var j = 0; j < counts[i]; j++) _textBlock('b_col${i}text000$j', 'Column $i block $j')],
        },
    ],
    'style': ?style,
  };
}

StructuredBlock _section(String layout, {List<int>? blocksPerColumn, Map<String, Object?> header = const {}, Map<String, dynamic>? style}) =>
    _parse(_stored(layout, blocksPerColumn: blocksPerColumn, header: header, style: style));

List<String> _ids(StructuredBlock b) => [for (final c in b.columns('columns')) c.id];
List<List<String>> _blockIds(StructuredBlock b) => [for (final c in b.columns('columns')) [for (final x in c.blocks) x.id]];

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
  });

  Finder key(String k) => find.byKey(Key(k));
  Finder header(String part) => key('public-section-$_sectionId-$part');

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpBlocks(WidgetTester tester, List<WebsiteBlock> blocks, {Size at = _desktop, bool interactive = true, PublicLanguage language = PublicLanguage.english}) async {
    await size(tester, at);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: blocks, media: const {}, language: language, interactive: interactive, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The section's properties form; returns the block as edited.
  Future<StructuredBlock Function()> pumpForm(WidgetTester tester, StructuredBlock initial) async {
    var block = initial;
    await size(tester, const Size(900, 3000));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: WebsiteBlockForm(block: block, library: const [], generation: 0, onChanged: (b) => setState(() => block = b as StructuredBlock)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return () => block;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('optional heading text', () {
    test('the Blank section: valid as created, stores none of the new fields', () {
      final blank = SectionPreset.byId('blank')!.create();
      expect(BlockRegistry.blockProblems(blank), isEmpty);
      final stored = blank.toMap();
      for (final k in _headerKeys) {
        expect(stored.containsKey(k), isFalse, reason: '$k is not stored while empty');
      }
      expect((stored['layout'], (stored['columns'] as List).length), ('1', 1));
    });

    test('a section stored before the fields existed is read and saved back exactly, and is valid', () {
      final raw = _plain(_stored('1:1:1', style: {'padding': '72', 'columnGap': '24'})) as Map<String, dynamic>;
      final block = _parse(raw);
      expect(_plain(block.toMap()), raw);
      expect(BlockRegistry.blockProblems(block), isEmpty);
      for (final k in _headerKeys) {
        expect(block.text(k).en, '');
      }
    });

    test('each field on its own, and all three: valid and stored; too long is a problem', () {
      for (final k in _headerKeys) {
        final block = _section('1', header: {k: {'en': 'Only $k', 'ta': ''}});
        expect(BlockRegistry.blockProblems(block), isEmpty, reason: k);
        expect(_plain(block.toMap()), containsPair(k, {'en': 'Only $k', 'ta': ''}));
        for (final other in _headerKeys.where((o) => o != k)) {
          expect(block.toMap().containsKey(other), isFalse, reason: '$other not stored with only $k');
        }
      }
      final all = _section('1', header: {for (final k in _headerKeys) k: {'en': 'Text $k', 'ta': ''}});
      expect(BlockRegistry.blockProblems(all), isEmpty);
      expect(BlockRegistry.blockProblems(_section('1', header: {'eyebrow': {'en': 'x' * 61}})).single, contains('Small heading'));
    });

    test('an empty section is valid, and the blocks inside it are still checked', () {
      final empty = _section('1:1', blocksPerColumn: [0, 0]);
      expect(BlockRegistry.validate([empty]), isEmpty);
      final raw = _stored('1:1', blocksPerColumn: [0, 0]);
      (raw['columns'] as List)[1]['blocks'] = [
        {'id': 'b_badtext0001', 'type': 'text', 'v': 1, 'heading': {'en': ''}, 'body': {'en': ''}},
      ];
      expect(BlockRegistry.validate([_parse(raw)]).single, contains('column 2, block 1 (Text): add a heading or some text'));
    });

    testWidgets('none of the three: no heading area, no extra space; the same height as before', (tester) async {
      final plain = _section('1:1');
      await pumpBlocks(tester, [plain]);
      expect(header('header'), findsNothing);
      final before = tester.getRect(key('public-section-$_sectionId'));
      final column = tester.getRect(key('public-block-column-c_column0000'));
      expect(column.top - before.top, 48, reason: 'the columns start right after the padding');

      // A section with nothing to show isn't drawn at all for visitors.
      await pumpBlocks(tester, [_section('1:1', blocksPerColumn: [0, 0])]);
      expect(key('public-section-$_sectionId'), findsNothing);
    });

    testWidgets('each field on its own is drawn, alone, with no gaps for the others', (tester) async {
      for (final k in _headerKeys) {
        final block = _section('1', header: {k: {'en': 'Only $k'}});
        await pumpBlocks(tester, [block]);
        expect(header(k), findsOneWidget, reason: k);
        for (final other in _headerKeys.where((o) => o != k)) {
          expect(header(other), findsNothing);
        }
        final area = tester.getRect(header('header'));
        expect((area.top, area.bottom), (tester.getRect(header(k)).top, tester.getRect(header(k)).bottom), reason: 'the heading area is just $k');
        expect(tester.getRect(key('public-block-column-c_column0000')).top - area.bottom, 32);
      }
    });

    testWidgets('all three in order, above the columns; a heading-only section with no blocks is shown without trailing space', (tester) async {
      final all = _section('1:1', header: {'eyebrow': {'en': 'OUR APPROACH'}, 'heading': {'en': 'How children learn'}, 'description': {'en': 'First paragraph.\n\nSecond paragraph.'}});
      await pumpBlocks(tester, [all]);
      final (e, h, d) = (tester.getRect(header('eyebrow')), tester.getRect(header('heading')), tester.getRect(header('description')));
      expect((h.top - e.bottom, d.top - h.bottom), (12, 12));
      expect(find.text('Second paragraph.'), findsOneWidget);
      expect(tester.getRect(key('public-block-column-c_column0000')).top - d.bottom, 32);
      expect(tester.widget<Semantics>(find.ancestor(of: find.text('How children learn'), matching: find.byType(Semantics)).first).properties.header, isTrue);

      final headingOnly = _section('1', blocksPerColumn: [0], header: {'heading': {'en': 'Coming soon'}});
      await pumpBlocks(tester, [headingOnly]);
      final section = tester.getRect(key('public-section-$_sectionId'));
      expect(section.bottom - tester.getRect(header('header')).bottom, 48, reason: 'only the bottom padding below the heading');
    });

    testWidgets('the section’s alignment and colours apply to the heading text', (tester) async {
      final centred = _section('1', header: {'heading': {'en': 'Centred'}}, style: {'align': 'center', 'headingColor': '#123456'});
      await pumpBlocks(tester, [centred]);
      final text = tester.widget<Text>(find.text('Centred'));
      expect(text.textAlign, TextAlign.center);
      expect(text.style!.color, const Color(0xFF123456));
    });

    testWidgets('Tamil visitors see stored Tamil text, else the English', (tester) async {
      final block = _section('1', header: {'heading': {'en': 'Welcome', 'ta': 'வரவேற்பு'}, 'description': {'en': 'English only'}});
      await pumpBlocks(tester, [block], language: PublicLanguage.tamil);
      expect(find.text('வரவேற்பு'), findsOneWidget);
      expect(find.text('English only'), findsOneWidget);
    });

    testWidgets('editing the English keeps stored Tamil; no Tamil fields are offered', (tester) async {
      final current = await pumpForm(tester, _section('1', header: {'heading': {'en': 'Welcome', 'ta': 'வரவேற்பு'}}));
      expect(find.text('Small heading above the title (English), optional'), findsOneWidget);
      expect(find.text('Section heading (English), optional'), findsOneWidget);
      expect(find.text('Section description (English), optional'), findsOneWidget);
      expect(find.textContaining('(Tamil)'), findsNothing);

      await tester.enterText(key('website-block-$_sectionId-heading-en-0'), 'Welcome, families');
      await tester.enterText(key('website-block-$_sectionId-eyebrow-en-0'), 'HELLO');
      await tester.pump();
      expect((current().text('heading').en, current().text('heading').ta), ('Welcome, families', 'வரவேற்பு'));
      expect(current().text('eyebrow').en, 'HELLO');

      // Cleared again, a field is not stored.
      await tester.enterText(key('website-block-$_sectionId-eyebrow-en-0'), '');
      await tester.pump();
      expect(current().toMap().containsKey('eyebrow'), isFalse);
    });
  });

  group('column operations', () {
    test('add: one to four columns, equal widths, existing ids and blocks kept', () {
      var b = _section('1');
      final first = _ids(b).single;
      for (final layout in ['1:1', '1:1:1', '1:1:1:1']) {
        b = ColumnOps.withColumnAdded(b)!;
        expect(b.string('layout'), layout);
        expect(BlockRegistry.blockProblems(b), isEmpty);
      }
      expect(_ids(b).first, first);
      expect(_blockIds(b).first, ['b_col0text0000']);
      expect(ColumnOps.withColumnAdded(b), isNull, reason: 'at most four');
      expect(ColumnOps.withColumnAdded(_section('1:2'))!.string('layout'), '1:1:1');
      expect(ColumnOps.range(b), (1, 4));
      expect(ColumnOps.range(_parse({...BlockRegistry.create(BlockRegistry.columns).toMap()})), (2, 4));
    });

    test('remove: an empty column goes; one with blocks only with a move or delete', () {
      final b = _section('1:1:1', blocksPerColumn: [1, 0, 2]);
      final emptyGone = ColumnOps.withColumnRemoved(b, 1)!;
      expect([emptyGone.string('layout'), _ids(emptyGone)], ['1:1', ['c_column0000', 'c_column0002']]);

      expect(() => ColumnOps.withColumnRemoved(b, 2), throwsStateError, reason: 'never silently');
      final moved = ColumnOps.withColumnRemoved(b, 2, moveInto: 1)!;
      expect(_blockIds(moved), [['b_col0text0000'], ['b_col2text0000', 'b_col2text0001']]);
      expect(BlockRegistry.blockProblems(moved), isEmpty);
      final deleted = ColumnOps.withColumnRemoved(b, 2, deleteBlocks: true)!;
      expect(_blockIds(deleted), [['b_col0text0000'], <String>[]]);

      // The remaining widths are kept when a layout has them.
      expect(ColumnOps.withColumnRemoved(_section('1:2', blocksPerColumn: [0, 1]), 0)!.string('layout'), '1');
      expect(ColumnOps.withColumnRemoved(_section('1', blocksPerColumn: [0]), 0), isNull, reason: 'a section keeps one column');
    });

    test('a move that would overfill a column is refused', () {
      final b = _section('1:1', blocksPerColumn: [4, 3]);
      expect(ColumnOps.canMerge(b, 1, 0), isFalse);
      expect(() => ColumnOps.withColumnRemoved(b, 1, moveInto: 0), throwsStateError);
      expect(() => ColumnOps.withLayout(b, '1', moveBlocks: true), throwsStateError);
    });

    test('reorder: columns move with their blocks and widths', () {
      final b = _section('1:2', blocksPerColumn: [1, 2]);
      final swapped = ColumnOps.withColumnMoved(b, 0, 1);
      expect([swapped.string('layout'), _ids(swapped)], ['2:1', ['c_column0001', 'c_column0000']]);
      expect(_blockIds(swapped).first, ['b_col1text0000', 'b_col1text0001']);
      expect(identical(ColumnOps.withColumnMoved(b, 0, -1), b), isTrue, reason: 'can’t move further');
      final four = ColumnOps.withColumnMoved(_section('1:1:1:1'), 3, -2);
      expect(_ids(four), ['c_column0000', 'c_column0003', 'c_column0001', 'c_column0002']);
    });

    test('layout: fewer columns move the removed blocks into the last one kept, only when asked', () {
      final b = _section('1:1:1:1', blocksPerColumn: [1, 1, 1, 1]);
      expect(ColumnOps.blocksRemovedBy(b, '1:1'), 2);
      expect(() => ColumnOps.withLayout(b, '1:1'), throwsStateError);
      final two = ColumnOps.withLayout(b, '1:2', moveBlocks: true);
      expect([two.string('layout'), _ids(two)], ['1:2', ['c_column0000', 'c_column0001']]);
      expect(_blockIds(two)[1], ['b_col1text0000', 'b_col2text0000', 'b_col3text0000']);
      final more = ColumnOps.withLayout(_section('1'), '1:1:1');
      expect(_ids(more).first, 'c_column0000');
      expect(BlockRegistry.blockProblems(more), isEmpty);
    });
  });

  group('column editing in the properties form', () {
    testWidgets('Add column up to four, then disabled', (tester) async {
      final current = await pumpForm(tester, _section('1'));
      for (var n = 2; n <= 4; n++) {
        await tap(tester, key('website-block-$_sectionId-columns-add-column'));
        expect(current().columns('columns').length, n);
      }
      expect(find.text('At most 4 columns'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.ancestor(of: find.text('At most 4 columns'), matching: find.byType(OutlinedButton))).onPressed, isNull);
      expect(current().string('layout'), '1:1:1:1');
    });

    testWidgets('removing a column with blocks asks: cancel keeps it, move keeps the blocks, delete removes them', (tester) async {
      final current = await pumpForm(tester, _section('1:1:1', blocksPerColumn: [1, 2, 0]));
      await tap(tester, key('website-column-c_column0001-remove'));
      expect(find.text('Remove column 2?'), findsOneWidget);
      expect(find.textContaining('holds 2 blocks'), findsOneWidget);
      await tap(tester, key('website-column-remove-cancel'));
      expect(_ids(current()).length, 3);

      await tap(tester, key('website-column-c_column0001-remove'));
      await tap(tester, key('website-column-remove-move'));
      expect(_blockIds(current()), [['b_col0text0000', 'b_col1text0000', 'b_col1text0001'], <String>[]]);
      expect(current().string('layout'), '1:1');

      await tap(tester, key('website-column-c_column0000-remove'));
      await tap(tester, key('website-column-remove-delete'));
      expect([current().string('layout'), _blockIds(current())], ['1', [<String>[]]]);
      expect(tester.widget<IconButton>(key('website-column-c_column0002-remove')).onPressed, isNull, reason: 'the last column stays');
    });

    testWidgets('an empty column is removed at once; columns move left and right', (tester) async {
      final current = await pumpForm(tester, _section('1:2', blocksPerColumn: [0, 1]));
      expect(tester.widget<IconButton>(key('website-column-c_column0000-left')).onPressed, isNull);
      await tap(tester, key('website-column-c_column0000-right'));
      expect([current().string('layout'), _ids(current())], ['2:1', ['c_column0001', 'c_column0000']]);
      await tap(tester, key('website-column-c_column0000-remove'));
      expect(find.byType(AlertDialog), findsNothing);
      expect([current().string('layout'), _ids(current())], ['1', ['c_column0001']]);
    });

    testWidgets('a layout with fewer columns asks before moving blocks; cancelled, the layout stays', (tester) async {
      final current = await pumpForm(tester, _section('1:1:1', blocksPerColumn: [1, 1, 1]));
      Future<void> choose(String label) async {
        await tap(tester, key('website-block-$_sectionId-layout'));
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await choose('One column');
      expect(find.textContaining('hold 2 blocks'), findsOneWidget);
      await tap(tester, key('website-columns-layout-cancel'));
      expect(current().string('layout'), '1:1:1');
      expect(find.descendant(of: key('website-block-$_sectionId-layout'), matching: find.text('Three columns')), findsOneWidget, reason: 'the choice goes back');

      await choose('Two equal columns');
      await tap(tester, key('website-columns-layout-move'));
      expect([current().string('layout'), _blockIds(current())], ['1:1', [['b_col0text0000'], ['b_col1text0000', 'b_col2text0000']]]);

      // More columns, or fewer when the removed ones are empty: no question.
      await choose('Four columns');
      expect(find.byType(AlertDialog), findsNothing);
      expect(current().columns('columns').length, 4);
      await choose('Two columns, wider right');
      expect(find.byType(AlertDialog), findsNothing);
      expect(current().string('layout'), '1:2');
    });
  });

  group('responsive layout', () {
    final full = _section('1:1:1:1', header: {'eyebrow': {'en': 'PROGRAMS'}, 'heading': {'en': 'Four programmes'}, 'description': {'en': 'One sentence.'}});

    testWidgets('desktop one row, tablet two by two, phones stacked; heading text above; no overflow', (tester) async {
      Rect col(int i) => tester.getRect(key('public-block-column-c_column000$i'));
      await pumpBlocks(tester, [full]);
      expect({for (var i = 0; i < 4; i++) col(i).top}.length, 1);
      expect(col(0).top, greaterThan(tester.getRect(header('header')).bottom));

      await pumpBlocks(tester, [full], at: _tablet);
      expect((col(1).top, col(2).left), (col(0).top, col(0).left));
      expect(col(0).width, greaterThan(300), reason: 'not cramped');

      for (final at in [_phone, _narrow]) {
        await pumpBlocks(tester, [full], at: at);
        expect(tester.takeException(), isNull, reason: 'no overflow at ${at.width}');
        for (var i = 1; i < 4; i++) {
          expect(col(i).top, greaterThan(col(i - 1).bottom));
        }
        expect(tester.getRect(header('header')).right, lessThanOrEqualTo(at.width));
        expect(tester.getRect(header('header')).top - tester.getRect(key('public-section-$_sectionId')).top, closeTo(48, 0.001), reason: 'at most 48 px padding on phones');
      }
    });

    testWidgets('the editor’s canvas (not interactive) draws the same sizes as the public page', (tester) async {
      Map<String, Size> sizes() => {for (final k in ['public-section-$_sectionId-header', 'public-block-column-c_column0000', 'public-block-column-c_column0003']) k: tester.getSize(key(k))};
      for (final at in [_desktop, _tablet, _phone]) {
        await pumpBlocks(tester, [full], at: at);
        final public = sizes();
        await pumpBlocks(tester, [full], at: at, interactive: false);
        expect(sizes(), public, reason: 'at ${at.width}');
      }
    });
  });

  group('saved, published, reloaded, reverted', () {
    final blank = SectionPreset.byId('blank')!.create();
    List<WebsiteBlock> blocks() => [
          _section('1:1:1', header: {'eyebrow': {'en': 'VISIT', 'ta': 'வருகை'}, 'heading': {'en': 'Plan your visit', 'ta': 'உங்கள் வருகை'}, 'description': {'en': 'Three things to know.'}}, style: {'columnGap': '24', 'width': 'wide'}),
          blank,
        ];

    test('an additional page: draft, reload, publish, edit, unpublish keep the text, Tamil and ids', () async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Visit'), slug: 'visit');
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => blocks()));
      var state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(_plain(BlockRegistry.toMapList(state.draft.blocks!)), _plain(BlockRegistry.toMapList(blocks())));
      expect(state.live, isNull);

      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: state.draft);
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      final live = state.live!.blocks!.first as StructuredBlock;
      expect((live.text('heading').en, live.text('heading').ta, live.text('eyebrow').ta), ('Plan your visit', 'உங்கள் வருகை', 'வருகை'));

      // A column removed in the draft (blocks moved): the published page is unchanged.
      final edited = ColumnOps.withColumnRemoved(state.draft.blocks!.first as StructuredBlock, 2, moveInto: 1)!;
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: state.draft.copyWith(blocks: () => [edited, ...state.draft.blocks!.skip(1)]));
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect((state.draft.blocks!.first as StructuredBlock).columns('columns').length, 2);
      expect((state.live!.blocks!.first as StructuredBlock).columns('columns').length, 3);

      await service.unpublishCustomPage(requesterRole: 'admin', actor: _admin, pageId: created.id);
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(state.live, isNull);
      expect(_blockIds(state.draft.blocks!.first as StructuredBlock)[1], ['b_col1text0000', 'b_col2text0000']);
    });

    test('a built-in page (Admissions): draft, publish, unpublish and revert', () async {
      const page = BuiltInPage.admissions;
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: page, blocks: blocks());
      var state = await service.getBuiltInPage(requesterRole: 'admin', page: page);
      expect(_plain(BlockRegistry.toMapList(state.draft!)), _plain(BlockRegistry.toMapList(blocks())));
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: page, blocks: state.draft!);
      state = await service.getBuiltInPage(requesterRole: 'admin', page: page);
      expect(_plain(BlockRegistry.toMapList(state.live!)), _plain(BlockRegistry.toMapList(blocks())));
      await service.unpublishBuiltInPage(requesterRole: 'admin', actor: _admin, page: page);
      state = await service.getBuiltInPage(requesterRole: 'admin', page: page);
      expect((state.live, state.draft?.length), (null, 2));
      await service.revertBuiltInPage(requesterRole: 'admin', actor: _admin, page: page);
      state = await service.getBuiltInPage(requesterRole: 'admin', page: page);
      expect((state.live, state.draft), (null, null));
    });

    testWidgets('the published page draws the heading text, and the canvas draws the same sizes', (tester) async {
      final created = await tester.runAsync(() => service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Visit'), slug: 'visit'));
      await tester.runAsync(() => service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: created!.copyWith(blocks: () => blocks())));

      await size(tester, _desktop);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
        ],
        child: const MontessoriApp(),
      ));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/pages/visit');
      await tester.pumpAndSettle();
      expect(find.text('Plan your visit'), findsOneWidget);
      Map<String, Size> sizes() => {for (final k in ['public-section-$_sectionId-header', 'public-block-column-c_column0000']) k: tester.getSize(key(k))};
      final published = sizes();

      await pumpBlocks(tester, blocks(), interactive: false);
      expect(sizes(), published);
    });
  });
}
