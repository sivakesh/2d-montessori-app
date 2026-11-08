// The website icon system: one icon library (WebsiteIcons, Material
// Symbols outlined, stored by stable id), one renderer (WebsiteIconView)
// and one picker, used by the new Icon block and by Text blocks' optional
// icon (before, after or above the text). Text blocks without an icon are
// stored and drawn exactly as before; unknown icon ids draw nothing.
// Synthetic test data only.
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_icon_picker.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/field_spec.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_icons.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_icon_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

Map<String, dynamic> _textMap({String id = 'b_text000001', Map<String, dynamic> extra = const {}, Map<String, dynamic> style = const {}}) => {
      'id': id,
      'type': 'text',
      'v': 1,
      'heading': {'en': 'Our classrooms', 'ta': 'எங்கள் வகுப்பறைகள்'},
      'body': {'en': 'Bright, calm spaces.\n\nWith *care*.', 'ta': ''},
      ...extra,
      if (style.isNotEmpty) 'style': style,
    };

Map<String, dynamic> _iconMap({String id = 'b_icon000001', String icon = 'book', Map<String, dynamic> extra = const {}, Map<String, dynamic> style = const {}}) => {
      'id': id,
      'type': 'icon',
      'v': 1,
      'icon': icon,
      ...extra,
      if (style.isNotEmpty) 'style': style,
    };

StructuredBlock _parse(Map<String, dynamic> m) => BlockRegistry.parse(m) as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pumpBlocks(WidgetTester tester, List<WebsiteBlock> blocks, {Size size = const Size(1400, 1600), bool interactive = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, interactive: interactive),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  // ------------------------------------------------------------ library
  group('the icon library', () {
    test('at least 150 icons in 10 named categories; ids unique and well formed; no two alike', () {
      expect(WebsiteIcons.all.length, greaterThanOrEqualTo(150));
      expect(WebsiteIcons.categories, hasLength(10));
      for (final (id, label) in WebsiteIcons.categories) {
        expect(WebsiteIcons.search('', category: id), isNotEmpty, reason: label);
      }
      expect({for (final i in WebsiteIcons.all) i.id}.length, WebsiteIcons.all.length, reason: 'unique ids');
      expect({for (final i in WebsiteIcons.all) (i.data.codePoint, i.data.fontFamily)}.length, WebsiteIcons.all.length, reason: 'no two the same glyph');
      expect({for (final i in WebsiteIcons.all) i.label.toLowerCase()}.length, WebsiteIcons.all.length, reason: 'unique names');
      expect(WebsiteIcons.all.every((i) => WebsiteIcons.isWellFormed(i.id) && WebsiteIcons.categories.any((c) => c.$1 == i.category)), isTrue);
    });

    test('5. the 17 Cards and Features icon names are the same glyphs as before', () {
      // The glyphs the Cards and Features blocks drew before the shared
      // library (their own name-to-icon table, now removed).
      const before = {
        'family': Icons.family_restroom_outlined, 'school': Icons.school_outlined, 'spa': Icons.spa_outlined, 'grid': Icons.grid_view_outlined,
        'care': Icons.volunteer_activism_outlined, 'star': Icons.star_outline, 'book': Icons.menu_book_outlined, 'palette': Icons.palette_outlined,
        'nature': Icons.park_outlined, 'heart': Icons.favorite_border, 'calendar': Icons.event_outlined, 'place': Icons.place_outlined,
        'phone': Icons.phone_outlined, 'mail': Icons.mail_outline, 'question': Icons.help_outline, 'quote': Icons.format_quote_outlined,
        'check': Icons.check_circle_outline,
      };
      expect(before.keys.toSet(), blockIconNames.toSet());
      for (final e in before.entries) {
        expect(WebsiteIcons.lookup(e.key)?.data, e.value, reason: e.key);
      }
    });

    test('3–4. every one of the 200 icons is found by its own name and by its id', () {
      for (final icon in WebsiteIcons.all) {
        expect(WebsiteIcons.search(icon.label).map((i) => i.id), contains(icon.id), reason: icon.label);
        expect(WebsiteIcons.search(icon.id.replaceAll('_', ' ')).map((i) => i.id), contains(icon.id), reason: icon.id);
        expect(WebsiteIcons.search('', category: icon.category).map((i) => i.id), contains(icon.id));
      }
    });

    test('9. one registry and one picker: no other icon-name table or icon picker in the website code', () {
      final files = [
        for (final dir in ['lib/modules/public_website', 'lib/modules/admin/website'])
          for (final f in Directory(dir).listSync(recursive: true))
            if (f is File && f.path.endsWith('.dart')) f,
      ];
      expect(files, isNotEmpty);
      final nameTable = RegExp(r"'(family|spa|care|nature|grid)'\s*=>\s*Icons\.");
      for (final f in files) {
        final source = f.readAsStringSync();
        expect(nameTable.hasMatch(source), isFalse, reason: '${f.path} maps icon names itself');
        if (!f.path.endsWith('website_icon_picker.dart')) {
          expect(source.contains('Future<String?> show') && source.contains('Choose an icon'), isFalse, reason: '${f.path} has its own icon picker');
        }
      }
    });

    test('3, 9. every icon field of every block (and of their items) is the shared icon field', () {
      final iconish = <String>[];
      void check(String where, List<FieldSpec> fields) {
        for (final f in fields) {
          if (f is ItemsFieldSpec) check('$where › ${f.key}', f.itemFields);
          final looksLikeIcon = f.key == 'icon' || f.label.toLowerCase() == 'icon';
          if (looksLikeIcon) {
            iconish.add('$where.${f.key}');
            expect(f, isA<IconFieldSpec>(), reason: '$where.${f.key}');
          }
          // (A few words like "grid" are also layout options elsewhere.)
          if (f is ChoiceFieldSpec) expect(f.options.toSet().intersection(blockIconNames.toSet()).length, lessThan(3), reason: 'no icon list in a dropdown: $where.${f.key}');
        }
      }

      for (final d in BlockRegistry.all) {
        check(d.type, d.fields);
      }
      expect(iconish, containsAll(['text.icon', 'icon.icon', 'cards › cards.icon', 'features › items.icon']));
    });

    test('3. search by name, id, search word or category; filtered by category; nothing for no match', () {
      List<String> ids(String q, {String? category}) => [for (final i in WebsiteIcons.search(q, category: category)) i.id];
      expect(ids('calculator'), ['calculator']);
      expect(ids('maths'), containsAll(['calculator', 'numbers']));
      expect(ids('  PHONE '), containsAll(['phone', 'contact_phone']));
      expect(ids('graduation'), ['school']);
      expect(ids('', category: 'media'), contains('camera'));
      expect(ids('book', category: 'places'), ['library'], reason: 'books are in Education; the Library is a place');
      expect(ids('qwertyuiop'), isEmpty);
    });

    test('11. unknown ids: looked up as nothing, kept as stored; only malformed ones are reported', () {
      expect(WebsiteIcons.lookup('icon_from_a_newer_app'), isNull);
      final unknown = _parse(_iconMap(icon: 'icon_from_a_newer_app'));
      expect(BlockRegistry.blockProblems(unknown), isEmpty);
      expect(unknown.toMap()['icon'], 'icon_from_a_newer_app');
      expect(BlockRegistry.blockProblems(_parse(_iconMap(icon: '<svg onload=x>'))), contains('“<svg onload=x>” is not an icon name'));
    });
  });

  // ------------------------------------------------------------ Icon block
  group('the Icon block', () {
    test('1. offered wherever blocks are added: top level and inside columns; a new one is a star', () {
      expect(BlockRegistry.topLevel.map((d) => d.type), contains('icon'));
      expect(BlockRegistry.nestableIn('section').map((d) => d.type), contains('icon'));
      expect(BlockRegistry.nestableIn(rowType).map((d) => d.type), contains('icon'));
      final made = BlockRegistry.create(BlockRegistry.icon);
      expect([made.string('icon'), BlockRegistry.blockProblems(made)], ['star', isEmpty]);
      expect(made.toMap().keys.toSet(), {'id', 'type', 'v', 'icon', 'label', 'color', 'iconBackground'}..removeWhere((k) => !made.toMap().containsKey(k)));
    });

    testWidgets('4–5, 10. drawn at its size per screen, in its colour, aligned, on a background with padding', (tester) async {
      final block = _parse(_iconMap(
        icon: 'calculator',
        extra: {'size': 80, 'tabletSize': 60, 'mobileSize': 40, 'color': '#AA3300', 'iconBackground': 'token:sageLight', 'iconPadding': 10, 'radius': 8},
        style: {'align': 'center'},
      ));
      for (final (size, expected) in [(const Size(1400, 1600), 80.0), (const Size(820, 1600), 60.0), (const Size(390, 1600), 40.0)]) {
        await pumpBlocks(tester, [block], size: size);
        final icon = tester.widget<Icon>(find.descendant(of: key('public-block-b_icon000001-icon'), matching: find.byType(Icon)));
        expect([icon.icon, icon.size, icon.color], [Icons.calculate_outlined, expected, const Color(0xFFAA3300)], reason: '$size');
        final box = tester.getRect(key('public-block-b_icon000001-icon'));
        expect(box.width, expected + 20, reason: 'padding on each side');
        final page = tester.getRect(find.byType(WebsiteBlocksView));
        expect((box.center.dx - page.center.dx).abs(), lessThan(2), reason: 'centred at $size');
        expect(tester.takeException(), isNull);
      }
      final container = tester.widget<Container>(find.descendant(of: key('public-block-b_icon000001-icon'), matching: find.byType(Container)).first);
      expect((container.decoration as BoxDecoration).borderRadius, BorderRadius.circular(8));
    });

    testWidgets('4. aligned left and right', (tester) async {
      final page = Rect.fromLTWH(0, 0, 1400, 1600);
      await pumpBlocks(tester, [_parse(_iconMap(style: {'align': 'end'}))]);
      final right = tester.getRect(key('public-block-b_icon000001-icon'));
      await pumpBlocks(tester, [_parse(_iconMap(style: {'align': 'start'}))]);
      final left = tester.getRect(key('public-block-b_icon000001-icon'));
      expect(right.center.dx, greaterThan(page.center.dx));
      expect(left.center.dx, lessThan(page.center.dx));
    });

    testWidgets('12. accessibility: decorative without a label; named with one; a linked icon is a named link', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBlocks(tester, [_parse(_iconMap())]);
      expect(tester.getSemantics(key('public-block-b_icon000001-icon')).label, isEmpty);

      await pumpBlocks(tester, [_parse(_iconMap(extra: {'label': {'en': 'Reading corner', 'ta': 'வாசிப்பு மூலை'}}))]);
      expect(find.bySemanticsLabel('Reading corner'), findsOneWidget);

      await pumpBlocks(tester, [_parse(_iconMap(extra: {'label': {'en': 'Call us', 'ta': ''}, 'icon': 'phone', 'link': 'tel:+914400000000'}))], interactive: true);
      final linked = tester.getSemantics(find.bySemanticsLabel('Call us'));
      expect(linked.flagsCollection.isLink, isTrue);
      expect(linked.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();

      final unlabelledLink = _parse(_iconMap(extra: {'link': '/admissions'}));
      expect(BlockRegistry.blockProblems(unlabelledLink), contains(startsWith('add an accessibility label')));
      expect(BlockRegistry.blockProblems(_parse(_iconMap(extra: {'link': 'javascript:alert(1)', 'label': {'en': 'x'}}))), isNotEmpty, reason: 'links are checked like buttons');
    });

    testWidgets('11. an unknown icon draws nothing (no broken glyph)', (tester) async {
      await pumpBlocks(tester, [_parse(_iconMap(icon: 'icon_from_a_newer_app'))]);
      expect(key('website-icon-missing'), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });
  });

  // ------------------------------------------------------------ Text icons
  group('Text blocks', () {
    test('8. without an icon: stored exactly as before (no new keys), and the icon settings start off', () {
      final raw = _textMap(style: {'align': 'center'});
      final block = _parse(raw);
      expect(block.toMap(), raw);
      expect(TextIcon.showsIcon(block), isFalse);
      expect(BlockRegistry.create(BlockRegistry.text).toMap().keys, isNot(contains(TextIcon.show)));
      // Turned off again: its settings are kept, but drawn and stored as off.
      final off = _parse(_textMap(extra: {TextIcon.icon: 'leaf', TextIcon.position: 'above'}));
      expect(TextIcon.showsIcon(off), isFalse);
      expect(off.toMap()[TextIcon.icon], 'leaf');
    });

    testWidgets('8, 13. without an icon: drawn exactly as before', (tester) async {
      await pumpBlocks(tester, [_parse(_textMap())]);
      expect(find.byType(WebsiteIconView), findsNothing);
      expect(key('public-block-b_text000001-icon-row'), findsNothing);
      expect(find.text('Our classrooms'), findsOneWidget);
    });

    testWidgets('6–7, 10. before, after and above the text, with its size, colour and spacing; formatting and Tamil kept', (tester) async {
      Map<String, dynamic> withIcon(String position) =>
          _textMap(extra: {TextIcon.show: true, TextIcon.icon: 'leaf', TextIcon.position: position, TextIcon.size: 40, TextIcon.color: '#225500', TextIcon.gap: 20});
      for (final screen in [const Size(1400, 1600), const Size(390, 1600)]) {
        for (final position in TextIcon.positions) {
          final block = _parse(withIcon(position));
          expect(block.toMap()['body'], {'en': 'Bright, calm spaces.\n\nWith *care*.', 'ta': ''}, reason: 'text untouched');
          expect(block.toMap()['heading'], {'en': 'Our classrooms', 'ta': 'எங்கள் வகுப்பறைகள்'});
          await pumpBlocks(tester, [block], size: screen);
          final icon = tester.getRect(key('public-block-b_text000001-icon'));
          final heading = tester.getRect(find.text('Our classrooms'));
          expect(icon.width, 40);
          expect(tester.widget<Icon>(find.descendant(of: key('public-block-b_text000001-icon'), matching: find.byType(Icon))).color, const Color(0xFF225500));
          switch (position) {
            case 'before':
              expect(icon.right + 20, moreOrLessEquals(heading.left, epsilon: 1), reason: '$screen');
            case 'after':
              expect(icon.left, greaterThanOrEqualTo(heading.right + 20 - 1), reason: '$screen');
            case 'above':
              expect(icon.bottom + 20, moreOrLessEquals(heading.top, epsilon: 1), reason: '$screen');
          }
          expect(tester.takeException(), isNull, reason: '$position at $screen');
        }
      }
    });

    testWidgets('an icon of a centred Text block is centred with it (above)', (tester) async {
      await pumpBlocks(tester, [_parse(_textMap(extra: {TextIcon.show: true, TextIcon.icon: 'star', TextIcon.position: 'above'}, style: {'align': 'center'}))]);
      final icon = tester.getRect(key('public-block-b_text000001-icon'));
      final heading = tester.getRect(find.text('Our classrooms'));
      expect((icon.center.dx - heading.center.dx).abs(), lessThan(2));
    });

    testWidgets('11. an unknown icon: the text is drawn as without one', (tester) async {
      await pumpBlocks(tester, [_parse(_textMap(extra: {TextIcon.show: true, TextIcon.icon: 'icon_from_a_newer_app'}))]);
      expect(find.byType(WebsiteIconView), findsNothing);
      expect(find.text('Our classrooms'), findsOneWidget);
    });

    test('12. a Text block’s icon is decorative (the text names it)', () {
      expect(const WebsiteIconView(id: 'leaf', size: 20, color: Colors.black).semanticLabel, isEmpty);
    });
  });

  // ------------------------------------------------------------ Cards & Features
  group('Cards and Features', () {
    Map<String, dynamic> cards(List<String> icons, {String id = 'b_cards00001'}) => {
          'id': id,
          'type': 'cards',
          'v': 1,
          'heading': {'en': 'Pathways', 'ta': 'பாதைகள்'},
          'cards': [
            for (final (i, icon) in icons.indexed)
              {'id': 'i_card${id.substring(id.length - 1)}${'$i'.padLeft(4, '0')}', 'icon': icon, 'title': {'en': 'Card $i', 'ta': 'அட்டை'}, 'body': {'en': 'Text', 'ta': ''}, 'linkLabel': {'en': '', 'ta': ''}, 'target': '', 'accent': 'primary'},
          ],
        };
    Map<String, dynamic> features(List<String> icons) => {
          'id': 'b_feat000001',
          'type': 'features',
          'v': 1,
          'eyebrow': {'en': '', 'ta': ''},
          'heading': {'en': 'Principles', 'ta': ''},
          'items': [
            for (final (i, icon) in icons.indexed) {'id': 'i_feat${'$i'.padLeft(5, '0')}', 'icon': icon, 'title': {'en': 'Point $i', 'ta': 'புள்ளி'}, 'body': {'en': '', 'ta': ''}},
          ],
        };

    testWidgets('5, 8. existing icon names draw the same glyphs, in the editor canvas and on the website alike', (tester) async {
      final names = [...blockIconNames];
      for (final interactive in [false, true]) {
        // At most 8 per block: two Cards blocks and a Features block.
        await pumpBlocks(tester, [
          _parse(cards(names.take(8).toList())),
          _parse(features(names.skip(8).take(8).toList())),
          _parse(cards(names.skip(16).toList(), id: 'b_cards00002')),
        ], interactive: interactive);
        for (final name in names) {
          expect(find.byIcon(WebsiteIcons.lookup(name)!.data), findsOneWidget, reason: '$name (interactive: $interactive)');
        }
        // As before: card icons 24 px in the accent, feature icons 28 px in sage.
        final cardIcon = tester.widget<Icon>(find.byIcon(Icons.family_restroom_outlined));
        expect(cardIcon.size, isNull, reason: 'the default 24 px, as before');
        final featureIcon = tester.widget<Icon>(find.byIcon(WebsiteIcons.lookup(names[8])!.data));
        expect(featureIcon.size, 28);
      }
    });

    test('6. saved icon names, contents and Tamil survive editing and saving; nothing new is stored', () {
      final rawCards = cards(['family', 'none', 'school']);
      final rawFeatures = features(['spa', 'grid', 'care']);
      expect(_parse(rawCards).toMap(), rawCards);
      expect(_parse(rawFeatures).toMap(), rawFeatures);
      final edited = _parse(rawCards).withValue('heading', const LocalizedText(en: 'New heading', ta: 'பாதைகள்'));
      expect([for (final c in edited.toMap()['cards'] as List) (c as Map)['icon']], ['family', 'none', 'school']);
      expect((edited.toMap()['cards'] as List).first['title'], {'en': 'Card 0', 'ta': 'அட்டை'});
      final absent = _parse({...cards(['family']), 'cards': [{...(cards(['family'])['cards'] as List).single as Map}..remove('icon')]});
      expect(absent.items('cards').single.string('icon'), 'star', reason: 'an absent card icon is still the star');
    });

    testWidgets('7. unknown names draw no icon (cards and features), never a different one', (tester) async {
      await pumpBlocks(tester, [_parse(cards(['icon_from_a_newer_app'])), _parse(features(['icon_from_a_newer_app']))]);
      expect(find.byIcon(Icons.star_outline), findsNothing, reason: 'no silent replacement');
      expect(find.text('Card 0'), findsOneWidget);
      expect(find.text('Point 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('icon size and colour for the whole block, when set', (tester) async {
      await pumpBlocks(tester, [
        _parse({...cards(['family']), ListIcons.size: 40, ListIcons.color: '#123456'}),
        _parse({...features(['spa']), ListIcons.size: 20, ListIcons.color: '#654321'}),
      ]);
      final card = tester.widget<Icon>(find.byIcon(Icons.family_restroom_outlined));
      expect([card.size, card.color], [40, const Color(0xFF123456)]);
      final feature = tester.widget<Icon>(find.byIcon(Icons.spa_outlined));
      expect([feature.size, feature.color], [20, const Color(0xFF654321)]);
    });

    testWidgets('1–2. both open the shared picker from their items', (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      for (final (raw, item, list) in [(cards(['family']), 'i_card10000', 'cards'), (features(['spa']), 'i_feat00000', 'items')]) {
        var block = _parse(raw);
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
        final field = 'website-block-${block.id}-$list-item-$item-icon';
        await tester.ensureVisible(key('$field-choose'));
        await tester.tap(key('$field-choose'));
        await tester.pumpAndSettle();
        expect(key('website-icon-picker'), findsOneWidget);
        await tester.enterText(key('website-icon-picker-search'), 'rocket');
        await tester.pumpAndSettle();
        await tester.tap(key('website-icon-option-rocket'));
        await tester.pumpAndSettle();
        await tester.tap(key('website-icon-picker-choose'));
        await tester.pumpAndSettle();
        expect(block.items(list).single.string('icon'), 'rocket', reason: block.type);
        expect(tester.widget<Text>(key('$field-status')).data, 'Rocket');
      }
    });
  });

  // ------------------------------------------------------------ picker
  group('the icon picker', () {
    Future<String?> openPicker(WidgetTester tester, {String? selected}) async {
      String? result = 'not closed';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () async => result = await showWebsiteIconPicker(context, selected: selected), child: const Text('open')),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('2–3. search, categories, a clear selected state and a preview before choosing', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      String? chosen = 'not closed';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () async => chosen = await showWebsiteIconPicker(context, selected: 'book'), child: const Text('open')),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('website-icon-picker-chosen')).data, 'Book · Education & Montessori', reason: 'the current icon is selected and previewed');
      expect(find.text('Book'), findsWidgets);

      await tester.enterText(key('website-icon-picker-search'), 'calc');
      await tester.pumpAndSettle();
      expect(key('website-icon-option-calculator'), findsOneWidget);
      expect(key('website-icon-option-book'), findsNothing);

      await tester.enterText(key('website-icon-picker-search'), '');
      await tester.tap(key('website-icon-picker-category-media'));
      await tester.pumpAndSettle();
      expect(key('website-icon-option-camera'), findsOneWidget);
      expect(key('website-icon-option-book'), findsNothing);

      await tester.enterText(key('website-icon-picker-search'), 'qwertyuiop');
      await tester.pumpAndSettle();
      expect(key('website-icon-picker-empty'), findsOneWidget);

      await tester.enterText(key('website-icon-picker-search'), 'camera');
      await tester.pumpAndSettle();
      await tester.tap(key('website-icon-option-camera'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('website-icon-picker-chosen')).data, 'Camera · Media & social');
      expect(find.descendant(of: key('website-icon-picker-preview'), matching: find.byIcon(Icons.photo_camera_outlined)), findsOneWidget);
      await tester.tap(key('website-icon-picker-choose'));
      await tester.pumpAndSettle();
      expect(chosen, 'camera');
    });

    testWidgets('cancel returns nothing; with nothing chosen, Choose is disabled', (tester) async {
      await openPicker(tester, selected: 'icon_from_a_newer_app');
      expect(tester.widget<FilledButton>(key('website-icon-picker-choose')).onPressed, isNull);
      await tester.tap(key('website-icon-picker-cancel'));
      await tester.pumpAndSettle();
      expect(key('website-icon-picker'), findsNothing);
    });
  });

  // ------------------------------------------------------------ editor
  group('in the visual editor', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    Future<String> pageWith(List<Map<String, dynamic>> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Icons', ta: ''), slug: 'icons');
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

    Future<void> pick(WidgetTester tester, String chooseKey, String search, String id) async {
      await tap(tester, key(chooseKey));
      await tester.enterText(key('website-icon-picker-search'), search);
      await tester.pumpAndSettle();
      await tester.tap(key('website-icon-option-$id'));
      await tester.pumpAndSettle();
      await tester.tap(key('website-icon-picker-choose'));
      await tester.pumpAndSettle();
    }

    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
    Future<List<Map<String, dynamic>>> stored(WidgetTester tester, String id) async =>
        [for (final b in ((await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()))!.data()!['blocks'] as List)) Map<String, dynamic>.from(b as Map)];

    testWidgets('1–2, 4, 9. add an Icon block, choose its icon, size and alignment; saved, reopened, edited and published', (tester) async {
      late String id;
      await tester.runAsync(() async => id = await pageWith([_textMap()]));
      await open(tester, id);
      await tap(tester, key('website-blocks-add'));
      await tester.tap(key('website-blocks-add-icon'));
      await tester.pumpAndSettle();
      final added = blocks(tester).last as StructuredBlock;
      expect([added.type, added.string('icon')], ['icon', 'star']);
      final p = 'website-block-${added.id}';
      expect(tester.widget<Text>(key('$p-icon-status')).data, 'Star');

      await pick(tester, '$p-icon-choose', 'grad', 'school');
      expect((blocks(tester).last as StructuredBlock).string('icon'), 'school');
      expect(tester.widget<Text>(key('$p-icon-status')).data, 'Graduation cap');
      expect(find.byIcon(Icons.school_outlined), findsWidgets, reason: 'previewed on the canvas at once');

      await tap(tester, key('$p-group-size'));
      await tester.enterText(key('$p-size'), '96');
      await tester.pumpAndSettle();
      await tap(tester, key('$p-style-align'));
      await tester.tap(key('$p-style-align-center').last);
      await tester.pumpAndSettle();
      await tap(tester, key('$p-group-accessibility'));
      await tester.enterText(find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('$p-label-en') == true), 'Our graduates');
      await tester.pumpAndSettle();

      await tap(tester, key('website-custom-save-draft'));
      var saved = (await stored(tester, id)).last;
      expect([saved['type'], saved['icon'], saved['size'], (saved['style'] as Map)['align'], (saved['label'] as Map)['en']], ['icon', 'school', 96, 'center', 'Our graduates']);
      expect((await stored(tester, id)).first, _textMap(), reason: 'the existing Text block is written back unchanged');

      // Reopened: the same settings, editable.
      await open(tester, id);
      final reopened = blocks(tester).last as StructuredBlock;
      expect([reopened.string('icon'), reopened.values['size']], ['school', 96]);
      await tap(tester, key('website-canvas-block-${reopened.id}'));
      await pick(tester, 'website-block-${reopened.id}-icon-choose', 'books', 'books');
      await tap(tester, key('website-custom-save-draft'));
      saved = (await stored(tester, id)).last;
      expect(saved['icon'], 'books');

      await tester.runAsync(() async {
        final page = (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
        await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      });
      final live = (await tester.runAsync(() => firestore.collection(WebsiteCollections.livePages).doc(id).get()))!.data()!['blocks'] as List;
      expect((live.last as Map)['icon'], 'books');
    });

    testWidgets('6–7, 9. turn on a Text block’s icon, choose it and its position; saved and reopened; the text untouched', (tester) async {
      late String id;
      await tester.runAsync(() async => id = await pageWith([_textMap()]));
      await open(tester, id);
      await tap(tester, find.text('Our classrooms').first);
      const p = 'website-block-b_text000001';
      await tap(tester, key('$p-group-icon'));
      expect(key('$p-icon-choose'), findsNothing, reason: 'the settings show once the icon is on');
      await tap(tester, key('$p-${TextIcon.show}'));
      await pick(tester, '$p-icon-choose', 'leaf', 'leaf');
      await tap(tester, key('$p-${TextIcon.position}'));
      await tester.tap(key('$p-${TextIcon.position}-above').last);
      await tester.pumpAndSettle();
      expect(key('public-block-b_text000001-icon'), findsOneWidget, reason: 'previewed on the canvas');

      await tap(tester, key('website-custom-save-draft'));
      final saved = (await stored(tester, id)).single;
      expect({for (final k in [TextIcon.show, TextIcon.icon, TextIcon.position]) k: saved[k]}, {TextIcon.show: true, TextIcon.icon: 'leaf', TextIcon.position: 'above'});
      expect([saved['heading'], saved['body']], [_textMap()['heading'], _textMap()['body']], reason: 'heading, text and Tamil kept');

      await open(tester, id);
      final reopened = blocks(tester).single as StructuredBlock;
      expect([TextIcon.showsIcon(reopened), reopened.string(TextIcon.position)], [true, 'above']);
      expect(key('public-block-b_text000001-icon'), findsOneWidget);
    });
  });
}
