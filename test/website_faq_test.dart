// The FAQ accordion block (`faq`): questions that open to show their
// answers, one at a time or several; all closed at first or the first
// open; optional category headings; every presentation setting optional
// (stored only when set) and sizes and spacing per screen. The question row
// is the only button: it announces whether it is expanded and works with
// the keyboard; the plus / minus icons (from the shared icon library) are
// decorative. Existing blocks are unchanged. Synthetic test data only.
import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/block_list_ops.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/faq_accordion.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_icons.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_icon_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

const _long = 'Our Montessori teacher training programme runs over a full academic year, with weekend classes, supervised '
    'classroom practice and a final assessment; can I join part-way through if I already hold an early years qualification?';

Map<String, dynamic> _q(String id, String q, String a, {String ta = '', String taAnswer = '', String? category}) => {
      'id': id,
      if (category != null) 'category': {'en': category, 'ta': ''},
      'question': {'en': q, 'ta': ta},
      'answer': {'en': a, 'ta': taAnswer},
    };

final _items = [
  _q('i_faq0000001', 'What ages do you welcome?', 'Children from 2½ to 6 years.', ta: 'எந்த வயதினரை வரவேற்கிறீர்கள்?', taAnswer: '2½ முதல் 6 வயது வரை.', category: 'Admissions'),
  _q('i_faq0000002', 'How do admissions work?', 'Visit us, then apply.\nWe reply within a week.', category: 'Admissions'),
  _q('i_faq0000003', 'How long is the course?', 'One academic year.', category: 'Training programme'),
];

Map<String, dynamic> _faq({String id = 'b_faq0000001', List<Map<String, dynamic>>? items, Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'type': 'faq',
      'v': 1,
      'heading': {'en': 'Frequently asked questions', 'ta': 'அடிக்கடி கேட்கப்படும் கேள்விகள்'},
      'items': items ?? _items,
      ...extra,
    };

StructuredBlock _parse(Map<String, dynamic> m) => BlockRegistry.parse(m) as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));
  const q1 = 'public-faq-i_faq0000001', q2 = 'public-faq-i_faq0000002', q3 = 'public-faq-i_faq0000003';

  Future<void> pump(WidgetTester tester, List<WebsiteBlock> blocks, {Size size = const Size(1400, 2400), PublicLanguage language = PublicLanguage.english}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: blocks, media: const {}, language: language, interactive: true, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  List<bool> open(WidgetTester tester) => [for (final q in [q1, q2, q3]) key('$q-answer').evaluate().isNotEmpty];
  String iconOf(WidgetTester tester, String q) => tester.widget<WebsiteIconView>(key('$q-icon')).id;
  TextStyle style(WidgetTester tester, Finder f) => tester.widget<Text>(f).style!;
  BoxDecoration card(WidgetTester tester, String q) => tester.widget<AnimatedContainer>(key(q)).decoration! as BoxDecoration;

  // ------------------------------------------------------------ the block
  group('registration and data', () {
    test('1. in the Add menus: at page level and in sections, columns and rows; a new block has one empty question', () {
      expect(BlockRegistry.faq.label, 'FAQ');
      expect(BlockRegistry.topLevel, contains(BlockRegistry.faq));
      for (final container in ['section', 'columns', rowType]) {
        expect(BlockRegistry.nestableIn(container), contains(BlockRegistry.faq), reason: container);
      }
      final created = BlockRegistry.create(BlockRegistry.faq);
      expect(created.items('items'), hasLength(1));
      expect(created.toMap().keys.toSet(), {'id', 'type', 'v', 'items'}, reason: 'no settings stored until changed');
      expect(BlockRegistry.blockProblems(created), containsAll(['Question 1: enter question in English', 'Question 1: enter answer (line breaks are kept) in English']));
      final section = BlockRegistry.parse({'id': 'b_sec0000001', 'type': 'section', 'v': 1, 'layout': '1', 'columns': [{'id': 'c_sec0000001', 'blocks': []}]});
      final (inside, at) = BlockListOps.insertInColumn([section], BlockPath(0), 0, created);
      expect((BlockListOps.at(inside, at) as StructuredBlock).type, 'faq');
    });

    test('10, 11. stored as structured data: saved and read back exactly, Tamil, line breaks, every setting and unknown keys kept', () {
      final raw = _faq(extra: {
        'mode': 'multiple',
        'initiallyOpen': 'first',
        'questionSize': 22,
        'mobileQuestionSize': 17,
        'questionWeight': '700',
        'questionColor': 'token:forest',
        'answerLineHeight': '1.8',
        'itemGap': 20,
        'expandIcon': 'chevron_down',
        'collapseIcon': 'tick',
        'iconCircle': false,
        'futureSetting': {'kept': true},
      });
      (raw['items'] as List).first['futureItemField'] = 'kept';
      final block = _parse(raw);
      expect(BlockRegistry.blockProblems(block), isEmpty);
      expect(block.toMap(), raw);
      expect(block.items('items')[0].text('question').textFor('ta'), 'எந்த வயதினரை வரவேற்கிறீர்கள்?');
      expect(block.items('items')[1].text('answer').en, contains('\n'));
      expect(_parse(block.toMap()).toMap(), raw, reason: 'stable');
    });

    test('unknown or missing values fall back safely; out-of-range ones are flagged', () {
      final b = _parse(_faq(extra: {'questionSize': 999, 'mode': 'sideways', 'expandIcon': 'not_in_this_version'}));
      expect(FaqAccordion.questionSize(b, 'desktop'), 40, reason: 'clamped');
      expect(FaqAccordion.multipleOpen(b), isFalse, reason: 'unknown mode: one at a time');
      expect(BlockRegistry.blockProblems(b), containsAll([contains('question size on desktop must be from 12 to 40'), contains('“sideways” is not')]));
      final bare = _parse({'id': 'b_faq0000009', 'type': 'faq', 'v': 1, 'items': [_q('i_faq0000009', 'Q?', 'A.')]});
      expect([FaqAccordion.questionSize(bare, 'mobile'), FaqAccordion.answerSize(bare, 'desktop'), FaqAccordion.padding(bare, 'tablet'), FaqAccordion.gap(bare, 'mobile')], [16, 16, 22, 12]);
      expect([FaqAccordion.expandIconOf(bare), FaqAccordion.collapseIconOf(bare)], ['plus', 'minus']);
      expect(WebsiteIcons.lookup('plus'), isNotNull);
      expect(WebsiteIcons.lookup('minus'), isNotNull, reason: 'in the shared library');
    });

    test('14. existing blocks, pages and the FAQ section preset are unchanged', () {
      final text = {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Hello', 'ta': 'வணக்கம்'}, 'body': {'en': '', 'ta': ''}};
      expect(BlockRegistry.parse(text).toMap(), text);
      final preset = SectionPreset.all.firstWhere((p) => p.id == 'faq').create();
      final inner = BlockRegistry.flatten([preset]).skip(1).map((b) => b.type).toSet();
      expect(inner, {'text'}, reason: 'the preset still uses Text blocks');
      expect(BlockRegistry.all.map((d) => d.type).where((t) => t == 'faq'), hasLength(1));
    });
  });

  // ------------------------------------------------------------ on the page
  group('on the page', () {
    testWidgets('5, 6. all closed at first: plus icons, no answers', (tester) async {
      await pump(tester, [_parse(_faq())]);
      expect(open(tester), [false, false, false]);
      expect(iconOf(tester, q1), 'plus');
      expect(find.text('What ages do you welcome?'), findsOneWidget);
    });

    testWidgets('5, 6. the first open at first: its answer and a minus icon', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'initiallyOpen': 'first'}))]);
      expect(open(tester), [true, false, false]);
      expect([iconOf(tester, q1), iconOf(tester, q2)], ['minus', 'plus']);
    });

    testWidgets('3. one at a time: opening one closes the other; tapping it again closes it', (tester) async {
      await pump(tester, [_parse(_faq())]);
      await tap(tester, key('$q1-question'));
      expect(open(tester), [true, false, false]);
      await tap(tester, key('$q2-question'));
      expect(open(tester), [false, true, false]);
      expect([iconOf(tester, q1), iconOf(tester, q2)], ['plus', 'minus']);
      await tap(tester, key('$q2-question'));
      expect(open(tester), [false, false, false]);
    });

    testWidgets('4. several at once: each stays open until closed', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'mode': 'multiple', 'initiallyOpen': 'first'}))]);
      await tap(tester, key('$q2-question'));
      await tap(tester, key('$q3-question'));
      expect(open(tester), [true, true, true]);
      await tap(tester, key('$q1-question'));
      expect(open(tester), [false, true, true]);
    });

    testWidgets('only the question row opens it: tapping the answer changes nothing', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'initiallyOpen': 'first'}))]);
      await tap(tester, key('$q1-answer'));
      expect(open(tester), [true, false, false]);
    });

    testWidgets('7. the open card has the stronger border; the default look', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'initiallyOpen': 'first'}))]);
      final d = SiteDesign.defaults;
      expect(card(tester, q1).border, Border.all(color: d.colorOf('gold')));
      expect(card(tester, q2).border, Border.all(color: d.colorOf('line')));
      expect(card(tester, q2).color, d.colorOf('surface'));
      expect(card(tester, q2).borderRadius, BorderRadius.circular(16));
      expect(card(tester, q2).boxShadow, isNull, reason: 'no shadows');
      expect(_box(tester, 'public-faq-b_faq0000001').color, d.colorOf('background'), reason: 'warm white behind');
      final q = style(tester, find.text('What ages do you welcome?'));
      expect([q.fontSize, q.fontWeight, q.color], [18, FontWeight.w600, d.colorOf('forestDark')]);
      final a = style(tester, key('$q1-answer'));
      expect([a.fontSize, a.fontWeight, a.color, a.height], [16, FontWeight.w400, d.colorOf('muted'), 1.6]);
      // Readable: the answer text against white.
      expect(_contrast(a.color!, d.colorOf('surface')), greaterThan(4.5));
      expect(_contrast(q.color!, d.colorOf('surface')), greaterThan(4.5));
    });

    testWidgets('7. every setting: question, answer, cards, spacing and icons', (tester) async {
      await pump(tester, [
        _parse(_faq(extra: {
          'initiallyOpen': 'first',
          'questionSize': 24, 'questionWeight': '800', 'questionColor': 'token:gold', 'questionAlign': 'center',
          'answerSize': 18, 'answerWeight': '500', 'answerColor': 'token:ink', 'answerLineHeight': '2.0',
          'sectionBackground': 'token:sageLight', 'itemBackground': 'token:goldLight', 'borderColor': 'token:sage', 'openBorderColor': 'token:forest', 'borderWidth': '2',
          'radius': 4, 'itemGap': 30, 'itemPadding': 40,
          'expandIcon': 'chevron_down', 'collapseIcon': 'arrow_down', 'iconColor': 'token:gold', 'iconSize': 30, 'iconCircle': false,
        })),
      ]);
      final d = SiteDesign.defaults;
      final q = tester.widget<Text>(find.text('What ages do you welcome?'));
      expect([q.style!.fontSize, q.style!.fontWeight, q.style!.color, q.textAlign], [24, FontWeight.w800, d.colorOf('gold'), TextAlign.center]);
      final a = style(tester, key('$q1-answer'));
      expect([a.fontSize, a.fontWeight, a.color, a.height], [18, FontWeight.w500, d.colorOf('ink'), 2.0]);
      expect(_box(tester, 'public-faq-b_faq0000001').color, d.colorOf('sageLight'));
      expect([card(tester, q2).color, card(tester, q2).border, card(tester, q1).border, card(tester, q2).borderRadius],
          [d.colorOf('goldLight'), Border.all(color: d.colorOf('sage'), width: 2), Border.all(color: d.colorOf('forest'), width: 2), BorderRadius.circular(4)]);
      // Within a category, 30 px apart.
      expect(tester.getRect(key(q2)).top - tester.getRect(key(q1)).bottom, moreOrLessEquals(30));
      expect(tester.getRect(find.text('What ages do you welcome?')).left - tester.getRect(key(q1)).left, greaterThanOrEqualTo(40), reason: 'padding');
      final icon = tester.widget<WebsiteIconView>(key('$q2-icon'));
      expect([icon.id, icon.size, icon.color], ['chevron_down', 30, d.colorOf('gold')]);
      expect(iconOf(tester, q1), 'arrow_down');
      expect(find.ancestor(of: key('$q2-icon'), matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle)), findsNothing, reason: 'no circle');
    });

    testWidgets('categories: a heading where each group starts, never repeated', (tester) async {
      await pump(tester, [_parse(_faq())]);
      expect(key('$q1-category'), findsOneWidget);
      expect(key('$q2-category'), findsNothing, reason: 'same group');
      expect(key('$q3-category'), findsOneWidget);
      expect(find.text('Admissions'), findsOneWidget);
      expect(find.text('Training programme'), findsOneWidget);
      expect(tester.getRect(key('$q3-category')).top, greaterThan(tester.getRect(key(q2)).bottom));
    });

    testWidgets('categories are optional', (tester) async {
      await pump(tester, [_parse(_faq(items: [_q('i_faq0000001', 'One?', 'A.'), _q('i_faq0000002', 'Two?', 'B.')]))]);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.endsWith('-category')), findsNothing);
    });

    for (final (name, size, qSize, aSize) in [('desktop', const Size(1400, 2400), 22.0, 17.0), ('tablet', const Size(820, 2400), 20.0, 17.0), ('mobile', const Size(390, 2400), 15.0, 13.0)]) {
      testWidgets('8. $name: its own sizes (a screen without one follows the larger)', (tester) async {
        await pump(tester, [
          _parse(_faq(extra: {'initiallyOpen': 'first', 'questionSize': 22, 'tabletQuestionSize': 20, 'mobileQuestionSize': 15, 'answerSize': 17, 'mobileAnswerSize': 13, 'itemPadding': 30, 'mobileItemPadding': 12})),
        ], size: size);
        expect(style(tester, find.text('What ages do you welcome?')).fontSize, qSize);
        expect(style(tester, key('$q1-answer')).fontSize, aSize);
        final inset = tester.getRect(find.text('What ages do you welcome?')).left - tester.getRect(key(q1)).left;
        expect(inset, moreOrLessEquals((name == 'mobile' ? 12 : 30) + 1), reason: 'its padding inside the 1 px border');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('9. long questions and answers wrap inside the card: no overflow on a 320 px phone, the icon kept', (tester) async {
      await pump(tester, [_parse(_faq(items: [_q('i_faq0000001', _long, '$_long $_long'), _q('i_faq0000002', 'Short?', 'Yes.')], extra: {'initiallyOpen': 'first'}))], size: const Size(320, 3000));
      expect(tester.takeException(), isNull);
      final cardRect = tester.getRect(key(q1));
      final question = tester.getRect(find.text(_long));
      expect(question.height, greaterThan(60), reason: 'wraps over several lines');
      expect(question.right, lessThan(cardRect.right));
      expect(tester.getRect(key('$q1-answer')).right, lessThanOrEqualTo(cardRect.right));
      expect(cardRect.right, lessThanOrEqualTo(320));
      expect(tester.getRect(key('$q1-icon')).width, 18, reason: 'the icon keeps its size');
      expect(tester.getRect(key(q1)).width, moreOrLessEquals(tester.getRect(key(q2)).width), reason: 'every card the same width');
    });

    testWidgets('11. Tamil: the Tamil text, else the English', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'initiallyOpen': 'first'}))], language: PublicLanguage.tamil);
      expect(find.text('அடிக்கடி கேட்கப்படும் கேள்விகள்'), findsOneWidget);
      expect(find.text('எந்த வயதினரை வரவேற்கிறீர்கள்?'), findsOneWidget);
      expect(find.text('2½ முதல் 6 வயது வரை.'), findsOneWidget);
      expect(find.text('How do admissions work?'), findsOneWidget, reason: 'no Tamil yet: the English');
    });

    testWidgets('left out when it has no question and no heading; hidden like any block', (tester) async {
      await pump(tester, [
        _parse({'id': 'b_faq0000002', 'type': 'faq', 'v': 1, 'items': [_q('i_faq0000008', '', '')]}),
        _parse(_faq()).copyWith(hidden: true),
      ]);
      expect(key('public-faq-b_faq0000002'), findsNothing);
      expect(key('public-faq-b_faq0000001'), findsNothing);
    });

    testWidgets('13. accessibility: a button per question with its expanded state; icons silent; Tab, Enter and Space', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, [_parse(_faq())]);
      expect(tester.getSemantics(key('$q1-question')), isSemantics(isButton: true, hasExpandedState: true, isExpanded: false, label: 'What ages do you welcome?'));
      expect(find.bySemanticsLabel(RegExp('^(Plus|Minus)\$')), findsNothing, reason: 'decorative icons');
      expect(find.bySemanticsLabel('Admissions'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(open(tester), [true, false, false]);
      expect(tester.getSemantics(key('$q1-question')), isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
      // The answer is plain text, not a button.
      expect(tester.getSemantics(key('$q1-answer')), isNot(isSemantics(isButton: true)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(open(tester), [false, true, false], reason: 'the next question, with Space');
      handle.dispose();
    });

    testWidgets('12. inside a section column, as published', (tester) async {
      final section = BlockRegistry.parse({
        'id': 'b_sec0000001', 'type': 'section', 'v': 1, 'layout': '1',
        'columns': [{'id': 'c_sec0000001', 'blocks': [_faq()]}],
      });
      await pump(tester, BlockRegistry.forVisitors([section]), size: const Size(820, 2400));
      expect(key('public-faq-b_faq0000001'), findsOneWidget);
      await tap(tester, key('$q2-question'));
      expect(open(tester), [false, true, false]);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------ editor
  group('in the editor', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    Future<void> openEditor(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1400, 3200);
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

    StructuredBlock faq(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.last as StructuredBlock;

    test('2. duplicate, move, hide and delete the block', () {
      final blocks = [_parse(_faq()), _parse(_faq(id: 'b_faq0000002'))];
      final (copied, at) = BlockListOps.duplicate(blocks, BlockPath(0));
      final copy = BlockListOps.at(copied, at) as StructuredBlock;
      expect(copy.id, isNot('b_faq0000001'));
      expect(copy.items('items').map((i) => i.id), isNot(contains('i_faq0000001')), reason: 'fresh item ids');
      expect(copy.items('items').first.text('question').textFor('ta'), 'எந்த வயதினரை வரவேற்கிறீர்கள்?');
      expect(BlockListOps.remove(blocks, BlockPath(0)).map((b) => b.id), ['b_faq0000002']);
    });

    testWidgets('1, 2, 10, 12. added from the menu; questions added, edited, duplicated, moved and deleted; behaviour tried; saved, reopened and published', (tester) async {
      late String id;
      await tester.runAsync(() async {
        final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Questions', ta: ''), slug: 'questions');
        await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
          'blocks': [
            {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Above', 'ta': 'மேலே'}, 'body': {'en': '', 'ta': ''}},
          ],
        });
        id = created.id;
      });
      await openEditor(tester, id);
      await tap(tester, key('website-blocks-add'));
      expect(find.descendant(of: key('website-blocks-add-faq'), matching: find.text('FAQ')), findsOneWidget);
      await tester.tap(key('website-blocks-add-faq'));
      await tester.pumpAndSettle();
      final added = faq(tester);
      expect(added.type, 'faq');
      final p = 'website-block-${added.id}';
      String item(int i) => '$p-items-item-${faq(tester).items('items')[i].id}';
      // A text field's English box (its key ends with the editor's generation).
      Finder en(String prefix) => find.byWidgetPredicate((w) => w is TextFormField && w.key is ValueKey<String> && RegExp('^${RegExp.escape(prefix)}-en-[0-9]+\$').hasMatch((w.key as ValueKey<String>).value));

      await tester.enterText(en('${item(0)}-question'), 'Can we visit?');
      await tester.pumpAndSettle();
      await tester.enterText(en('${item(0)}-answer'), 'Yes, on weekdays.');
      await tester.pumpAndSettle();
      await tap(tester, key('$p-items-add'));
      await tester.enterText(en('${item(1)}-question'), 'What do you charge?');
      await tester.pumpAndSettle();
      await tester.enterText(en('${item(1)}-answer'), 'See the fees page.');
      await tester.pumpAndSettle();
      await tester.enterText(en('${item(1)}-category'), 'Fees');
      await tester.pumpAndSettle();
      // Duplicate the first (a copy just below it), then delete the copy.
      await tap(tester, key('${item(0)}-duplicate'));
      expect(faq(tester).items('items').map((i) => i.text('question').en), ['Can we visit?', 'Can we visit?', 'What do you charge?']);
      expect(faq(tester).items('items').map((i) => i.id).toSet(), hasLength(3), reason: 'its own id');
      await tap(tester, key('${item(1)}-remove'));
      // Move the fees question up.
      await tap(tester, key('${item(1)}-up'));
      expect(faq(tester).items('items').map((i) => i.text('question').en), ['What do you charge?', 'Can we visit?']);
      expect(BlockRegistry.blockProblems(faq(tester)), isEmpty);

      // Behaviour: several at once, the first open; tried in the panel.
      await tap(tester, key('$p-group-behaviour'));
      await tap(tester, key('$p-mode'));
      await tester.tap(key('$p-mode-multiple').last);
      await tester.pumpAndSettle();
      await tap(tester, key('$p-initiallyOpen'));
      await tester.tap(key('$p-initiallyOpen-first').last);
      await tester.pumpAndSettle();
      final tryPrefix = '$p-items-try';
      final ids = faq(tester).items('items').map((i) => i.id).toList();
      expect(text(tester, '$tryPrefix-summary'), contains('Several answers can be open at once.'));
      expect(key('$tryPrefix-${ids[0]}-answer'), findsOneWidget, reason: 'the initial state: the first open');
      await tap(tester, key('$tryPrefix-${ids[1]}-question'));
      expect([key('$tryPrefix-${ids[0]}-answer'), key('$tryPrefix-${ids[1]}-answer')].map((f) => f.evaluate().length), [1, 1], reason: 'both open');
      await tap(tester, key('$tryPrefix-reset'));
      expect(key('$tryPrefix-${ids[1]}-answer'), findsNothing, reason: 'back to the initial state');
      // The canvas shows the initial state.
      expect(key('public-faq-${ids[0]}-answer'), findsOneWidget);

      // A style setting, previewed at once.
      await tap(tester, key('$p-group-questions'));
      await tester.enterText(key('$p-questionSize'), '26');
      await tester.pumpAndSettle();
      expect(faq(tester).values['questionSize'], 26);

      await tap(tester, key('website-custom-save-draft'));
      final stored = ((await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()))!.data()!['blocks'] as List);
      final saved = Map<String, dynamic>.from(stored.last as Map);
      expect([saved['type'], saved['mode'], saved['initiallyOpen'], saved['questionSize']], ['faq', 'multiple', 'first', 26]);
      expect([for (final i in saved['items'] as List) (i as Map)['question']], [
        {'en': 'What do you charge?', 'ta': ''},
        {'en': 'Can we visit?', 'ta': ''},
      ]);
      expect((saved['items'] as List).first['category'], {'en': 'Fees', 'ta': ''});
      expect(saved.containsKey('radius'), isFalse, reason: 'unchanged settings aren’t stored');
      expect(stored.first, {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Above', 'ta': 'மேலே'}, 'body': {'en': '', 'ta': ''}}, reason: 'the rest unchanged');

      // Tamil added elsewhere (Tamil editing is off here): kept through
      // editing the English.
      (saved['items'] as List)[1] = {...(saved['items'] as List)[1] as Map, 'question': {'en': 'Can we visit?', 'ta': 'நாங்கள் வரலாமா?'}, 'answer': {'en': 'Yes, on weekdays.', 'ta': 'ஆம், வார நாட்களில்.'}};
      await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(id).update({'blocks': [stored.first, saved]}));
      await openEditor(tester, id);
      final reopened = faq(tester);
      expect(reopened.toMap(), saved);
      // Edit after reopening.
      await tap(tester, key('website-canvas-block-${reopened.id}'));
      await tester.enterText(en('$p-items-item-${reopened.items('items')[1].id}-answer'), 'Yes, on weekdays from 9 to 12.');
      await tester.pumpAndSettle();
      expect(faq(tester).items('items')[1].text('answer').en, 'Yes, on weekdays from 9 to 12.');
      expect(faq(tester).items('items')[1].text('question').textFor('ta'), 'நாங்கள் வரலாமா?');
      expect(faq(tester).items('items')[1].text('answer').textFor('ta'), 'ஆம், வார நாட்களில்.');
      await tap(tester, key('website-custom-save-draft'));

      await tester.runAsync(() async {
        final page = (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
        await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      });
      final live = (await tester.runAsync(() => firestore.collection(WebsiteCollections.livePages).doc(id).get()))!.data()!['blocks'] as List;
      expect((live.last as Map)['type'], 'faq');
      expect(((live.last as Map)['items'] as List), hasLength(2));
      expect(((live.last as Map)['items'] as List)[1]['answer'], {'en': 'Yes, on weekdays from 9 to 12.', 'ta': 'ஆம், வார நாட்களில்.'});
    });
  });

  // ------------------------------------------------------------ container background
  group('FAQ container background', () {
    Color? containerColor(WidgetTester tester, [String k = 'public-faq-b_faq0000001']) => _box(tester, k).color;

    test('a setting of its own, labelled as the container’s, separate from the cards and borders', () {
      final labels = {for (final f in FaqAccordion.fields) f.key: f.label};
      expect(labels['sectionBackground'], startsWith('FAQ container background'));
      expect(labels['itemBackground'], 'Question card background');
      expect([labels['borderColor'], labels['openBorderColor']], ['Question card border colour', 'Question card border colour when open']);
      expect(BlockRegistry.faq.styleKeys, isNot(contains('background')), reason: 'not a second control for the same thing');
    });

    testWidgets('default: warm white, exactly as before (nothing stored)', (tester) async {
      final block = _parse(_faq());
      expect(block.toMap().containsKey('sectionBackground'), isFalse);
      await pump(tester, [block]);
      expect(containerColor(tester), SiteDesign.defaults.colorOf('background'));
    });

    testWidgets('a custom colour: behind the heading and every question; the cards and borders unchanged', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'sectionBackground': '#123456', 'initiallyOpen': 'first'}))]);
      expect(containerColor(tester), const Color(0xFF123456));
      final container = tester.getRect(key('public-faq-b_faq0000001'));
      expect(container.contains(tester.getCenter(find.text('Frequently asked questions'))), isTrue, reason: 'the heading is inside it');
      expect(container.contains(tester.getRect(key(q3)).bottomCenter - const Offset(0, 1)), isTrue);
      final d = SiteDesign.defaults;
      expect(card(tester, q2).color, d.colorOf('surface'), reason: 'cards keep their own background');
      expect(card(tester, q2).border, Border.all(color: d.colorOf('line')));
      expect(card(tester, q1).border, Border.all(color: d.colorOf('gold')));
    });

    testWidgets('transparent: the section behind shows through', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'sectionBackground': 'transparent'}))]);
      expect(containerColor(tester), Colors.transparent);
      expect(card(tester, q1).color, SiteDesign.defaults.colorOf('surface'));
    });

    testWidgets('a card colour leaves the container alone', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'itemBackground': 'token:goldLight'}))]);
      expect(containerColor(tester), SiteDesign.defaults.colorOf('background'));
      expect(card(tester, q1).color, SiteDesign.defaults.colorOf('goldLight'));
    });

    testWidgets('the surrounding section keeps its own background, whatever the container’s', (tester) async {
      Color? colorOf(Widget w) => switch (w) {
            Container(:final color?) => color,
            Container(:final BoxDecoration decoration) => decoration.color,
            ColoredBox(:final color) => color,
            DecoratedBox(:final BoxDecoration decoration) => decoration.color,
            _ => null,
          };
      final forest = SiteDesign.defaults.colorOf('forest');
      Map<String, dynamic> section(Map<String, dynamic> faq) => {
            'id': 'b_sec0000001', 'type': 'section', 'v': 1, 'layout': '1', 'style': {'background': 'token:forest'},
            'columns': [{'id': 'c_sec0000001', 'blocks': [faq]}],
          };
      for (final (bg, expected) in [(null, SiteDesign.defaults.colorOf('background')), ('token:sageLight', SiteDesign.defaults.colorOf('sageLight')), ('transparent', Colors.transparent)]) {
        final raw = section(_faq(extra: {'sectionBackground': ?bg}));
        await pump(tester, [BlockRegistry.parse(raw)]);
        expect(containerColor(tester), expected, reason: '$bg');
        expect(find.ancestor(of: key('public-faq-b_faq0000001'), matching: find.byWidgetPredicate((w) => colorOf(w) == forest)), findsWidgets, reason: 'the section: $bg');
        expect(BlockRegistry.parse(raw).toMap()['style'], {'background': 'token:forest'}, reason: 'the section’s setting untouched');
      }
      // And the section's colour leaves the container's alone.
      await pump(tester, [BlockRegistry.parse(section(_faq()))]);
      expect(containerColor(tester), SiteDesign.defaults.colorOf('background'));
    });

    test('existing FAQ data and unknown settings are kept when it is set', () {
      final raw = _faq(extra: {'futureSetting': 1, 'itemBackground': 'token:goldLight'});
      final changed = _parse(raw).withValue('sectionBackground', 'token:sageLight');
      expect(changed.toMap(), {...raw, 'sectionBackground': 'token:sageLight'});
    });

    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    Future<void> openEditor(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1400, 3200);
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

    StructuredBlock faq(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.last as StructuredBlock;

    testWidgets('chosen in the panel with the colour picker; previewed at once; saved, reopened and published the same; transparent too', (tester) async {
      late String id;
      await tester.runAsync(() async {
        final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Questions', ta: ''), slug: 'questions');
        await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': [_faq()]});
        id = created.id;
      });
      await openEditor(tester, id);
      await tap(tester, key('website-canvas-block-b_faq0000001'));
      const p = 'website-block-b_faq0000001';
      final sage = SiteDesign.defaults.colorOf('sageLight');
      expect(containerColor(tester), SiteDesign.defaults.colorOf('background'), reason: 'the canvas, before');
      await tap(tester, key('$p-group-items-and-container'));
      expect(find.descendant(of: key('$p-sectionBackground'), matching: find.textContaining('FAQ container background')), findsOneWidget);
      await tap(tester, key('$p-sectionBackground-choose'));
      await tap(tester, key('$p-sectionBackground-token-sageLight'));
      expect(faq(tester).string('sectionBackground'), 'token:sageLight');
      expect(containerColor(tester), sage, reason: 'the canvas at once');
      expect(containerColor(tester, '$p-items-try-b_faq0000001'), sage, reason: 'Try it too');
      expect(card(tester, q1).color, SiteDesign.defaults.colorOf('surface'), reason: 'cards unchanged');

      await tap(tester, key('website-custom-save-draft'));
      final stored = ((await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()))!.data()!['blocks'] as List).single as Map;
      expect(stored['sectionBackground'], 'token:sageLight');
      expect(stored['items'], _faq()['items'], reason: 'questions unchanged');

      await openEditor(tester, id);
      expect(faq(tester).string('sectionBackground'), 'token:sageLight');
      expect(containerColor(tester), sage, reason: 'restored');

      await tester.runAsync(() async {
        final page = (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
        await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      });
      final live = (await tester.runAsync(() => firestore.collection(WebsiteCollections.livePages).doc(id).get()))!.data()!['blocks'] as List;
      await pump(tester, BlockRegistry.forVisitors(BlockRegistry.parseList(live)));
      expect(containerColor(tester), sage, reason: 'the published page agrees with the editor');

      // Transparent, from the picker.
      await openEditor(tester, id);
      await tap(tester, key('website-canvas-block-b_faq0000001'));
      await tap(tester, key('$p-group-items-and-container'));
      await tap(tester, key('$p-sectionBackground-choose'));
      await tap(tester, key('$p-sectionBackground-legacy-transparent'));
      expect(faq(tester).string('sectionBackground'), 'transparent');
      expect(containerColor(tester), Colors.transparent);
      // Reset: back to the warm white (nothing stored).
      await tap(tester, key('$p-sectionBackground-reset'));
      expect(faq(tester).toMap().containsKey('sectionBackground'), isFalse);
      expect(containerColor(tester), SiteDesign.defaults.colorOf('background'));
    });
  });

  // ------------------------------------------------------------ container corners
  group('FAQ container corner radius', () {
    BorderRadius? radius(WidgetTester tester, [String k = 'public-faq-b_faq0000001']) => _box(tester, k).borderRadius as BorderRadius?;
    Clip clip(WidgetTester tester, [String k = 'public-faq-b_faq0000001']) => tester.widget<Container>(find.byKey(Key(k))).clipBehavior;

    test('its own setting, apart from the cards’; 16 px unless set', () {
      final labels = {for (final f in FaqAccordion.fields) f.key: f.label};
      expect([labels['containerRadius'], labels['radius']], ['Corner radius of the FAQ container', 'Question card corner radius']);
      final old = _parse(_faq());
      expect(old.toMap().containsKey('containerRadius'), isFalse, reason: 'nothing added to saved blocks');
      expect(FaqAccordion.containerRadius(old), 16);
      expect(FaqAccordion.containerRadius(_parse(_faq(extra: {'containerRadius': 999}))), 48, reason: 'clamped');
      expect(BlockRegistry.blockProblems(_parse(_faq(extra: {'containerRadius': 999}))), contains('corner radius of the FAQ container must be from 0 to 48 px'));
    });

    testWidgets('an existing block without one: rounded 16 px, its background clipped to the corners', (tester) async {
      await pump(tester, [_parse(_faq())]);
      expect(radius(tester), BorderRadius.circular(16));
      expect(clip(tester), Clip.antiAlias);
      expect(_box(tester, 'public-faq-b_faq0000001').color, SiteDesign.defaults.colorOf('background'), reason: 'colour unchanged');
      expect(card(tester, q1).borderRadius, BorderRadius.circular(16), reason: 'cards unchanged');
    });

    testWidgets('independent of the cards’ radius, both ways', (tester) async {
      await pump(tester, [_parse(_faq(extra: {'containerRadius': 32, 'radius': 4}))]);
      expect(radius(tester), BorderRadius.circular(32));
      expect(card(tester, q1).borderRadius, BorderRadius.circular(4));
      await pump(tester, [_parse(_faq(extra: {'containerRadius': 0}))]);
      expect(radius(tester), BorderRadius.zero, reason: 'square when asked');
      expect(card(tester, q1).borderRadius, BorderRadius.circular(16));
    });

    for (final bg in ['#123456', 'transparent']) {
      testWidgets('a $bg background keeps the rounded shape', (tester) async {
        await pump(tester, [_parse(_faq(extra: {'sectionBackground': bg, 'containerRadius': 24}))]);
        expect(radius(tester), BorderRadius.circular(24));
        expect(clip(tester), Clip.antiAlias);
        expect(_box(tester, 'public-faq-b_faq0000001').color, bg == 'transparent' ? Colors.transparent : const Color(0xFF123456));
      });
    }

    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    Future<void> openEditor(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1400, 3200);
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

    StructuredBlock faq(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.last as StructuredBlock;

    testWidgets('set in the panel, previewed at once, saved, reopened and published the same; the card radius untouched', (tester) async {
      late String id;
      await tester.runAsync(() async {
        final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Questions', ta: ''), slug: 'questions');
        await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': [_faq(extra: {'radius': 8})]});
        id = created.id;
      });
      await openEditor(tester, id);
      await tap(tester, key('website-canvas-block-b_faq0000001'));
      const p = 'website-block-b_faq0000001';
      expect(radius(tester), BorderRadius.circular(16), reason: 'the canvas, before');
      await tap(tester, key('$p-group-items-and-container'));
      await tester.enterText(key('$p-containerRadius'), '28');
      await tester.pumpAndSettle();
      expect(faq(tester).values['containerRadius'], 28);
      expect(radius(tester), BorderRadius.circular(28), reason: 'the canvas at once');
      expect(radius(tester, '$p-items-try-b_faq0000001'), BorderRadius.circular(28), reason: 'Try it too');
      expect(card(tester, q1).borderRadius, BorderRadius.circular(8), reason: 'the cards keep theirs');

      await tap(tester, key('website-custom-save-draft'));
      final stored = ((await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()))!.data()!['blocks'] as List).single as Map;
      expect([stored['containerRadius'], stored['radius']], [28, 8]);

      await openEditor(tester, id);
      expect(faq(tester).values['containerRadius'], 28);
      expect(radius(tester), BorderRadius.circular(28), reason: 'restored');

      await tester.runAsync(() async {
        final page = (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
        await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      });
      final live = (await tester.runAsync(() => firestore.collection(WebsiteCollections.livePages).doc(id).get()))!.data()!['blocks'] as List;
      await pump(tester, BlockRegistry.forVisitors(BlockRegistry.parseList(live)));
      expect(radius(tester), BorderRadius.circular(28), reason: 'published as in the editor');
      expect(card(tester, q1).borderRadius, BorderRadius.circular(8));
    });
  });
}

/// The FAQ container's decoration (its background and corners).
BoxDecoration _box(WidgetTester tester, String k) => tester.widget<Container>(find.byKey(Key(k))).decoration! as BoxDecoration;

String text(WidgetTester tester, String k) => tester.widget<Text>(find.byKey(Key(k))).data!;

/// WCAG contrast ratio of [a] on [b].
double _contrast(Color a, Color b) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double l(Color c) => 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  final (x, y) = (l(a), l(b));
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}
