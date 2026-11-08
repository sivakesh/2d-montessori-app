// The Cards block on phones: stacked one per row, every card the full width
// of the block whatever the length of its title and text (they wrap inside
// the card), sharing the same left and right edges, never wider than the
// screen; inside a section, the section's width (its padding respected), not
// the browser's. Tablet and desktop keep their layouts. Synthetic test data
// only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

const _phone = Size(400, 3000);
const _tablet = Size(820, 3000);
const _desktop = Size(1400, 3000);

// Different lengths on purpose: a short title with a long text, a long
// title with a short text, one with neither much, one with no icon.
const _cards = [
  ('c_card000001', 'Guided learning', 'Small groups.', 'school'),
  ('c_card000002', 'Material demonstrations', 'Hands-on presentations of every Montessori material, from the practical life shelf to the golden beads, with time to practise each one.', 'spa'),
  ('c_card000003', 'Classroom exposure', 'Observe.', 'family'),
  ('c_card000004', 'Mentor support throughout the whole training year', 'A mentor.', 'none'),
];
List<String> get _ids => [for (final c in _cards) c.$1];

Map<String, dynamic> _cardsJson(String id, {Map<String, String> options = const {}}) => {
      'id': id,
      'type': 'cards',
      'v': 1,
      'heading': {'en': 'What the course offers', 'ta': ''},
      ...options,
      'cards': [
        for (final (cid, title, body, icon) in _cards)
          {
            'id': cid,
            'icon': icon,
            'title': {'en': title, 'ta': ''},
            'body': {'en': body, 'ta': ''},
            'linkLabel': {'en': '', 'ta': ''},
            'accent': 'primary',
          },
      ],
    };

WebsiteBlock _cardsBlock({Map<String, String> options = const {}}) => BlockRegistry.parse(_cardsJson('b_cards00001', options: options));

WebsiteBlock _inSection() => BlockRegistry.parse({
      'id': 'b_sec0000001',
      'type': 'section',
      'v': 1,
      'layout': '1',
      'columns': [
        {'id': 'c_sec0000001', 'blocks': [_cardsJson('b_cards00002')]},
      ],
    });

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pump(WidgetTester tester, WebsiteBlock block, Size at) async {
    tester.view.physicalSize = at;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: [block], media: const {}, language: PublicLanguage.english, interactive: false),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  List<Rect> rects(WidgetTester tester) => [for (final id in _ids) tester.getRect(key('public-card-$id'))];

  void expectStackedFullWidth(WidgetTester tester, List<Rect> r, Rect container, double screen) {
    for (final c in r) {
      expect(c.width, moreOrLessEquals(r.first.width), reason: 'equal widths');
      expect(c.left, moreOrLessEquals(r.first.left), reason: 'same left edge');
      expect(c.right, moreOrLessEquals(r.first.right), reason: 'same right edge');
      expect(c.left, greaterThanOrEqualTo(0));
      expect(c.right, lessThanOrEqualTo(screen), reason: 'no horizontal overflow');
    }
    // Each below the one before.
    for (var i = 1; i < r.length; i++) {
      expect(r[i].top, greaterThan(r[i - 1].bottom), reason: 'stacked');
    }
    // The full width of the block: its container, not each card's text.
    expect(r.first.left, moreOrLessEquals(container.left));
    expect(r.first.width, moreOrLessEquals(container.width));
    expect(tester.takeException(), isNull, reason: 'no overflow errors');
  }

  group('phones (400 px)', () {
    testWidgets('on the page: every card the same width, edges aligned, stacked, within the screen', (tester) async {
      await pump(tester, _cardsBlock(), _phone);
      final r = rects(tester);
      expectStackedFullWidth(tester, r, tester.getRect(key('public-cards-b_cards00001-stack')), _phone.width);
      // As wide as the block (here the whole test screen: no section or
      // page padding around it), not each card's own text.
      expect(r.first.width, moreOrLessEquals(_phone.width));
    });

    testWidgets('inside a section: the section column’s width, its padding respected', (tester) async {
      await pump(tester, _inSection(), _phone);
      final r = rects(tester);
      final column = tester.getRect(key('public-block-column-c_sec0000001'));
      expectStackedFullWidth(tester, r, tester.getRect(key('public-cards-b_cards00002-stack')), _phone.width);
      expect(r.first.left, greaterThanOrEqualTo(column.left - 0.01));
      expect(r.first.right, lessThanOrEqualTo(column.right + 0.01));
      expect(r.first.width, moreOrLessEquals(column.width));
    });

    testWidgets('text wraps inside the card; icons keep their size and place', (tester) async {
      await pump(tester, _cardsBlock(), _phone);
      final long = tester.getRect(find.text(_cards[1].$3));
      final card = tester.getRect(key('public-card-${_cards[1].$1}'));
      expect(long.height, greaterThan(40), reason: 'the long text wraps');
      expect(long.right, lessThanOrEqualTo(card.right));
      // The icon tiles: 52 px (the default 24 px glyph), at the same inset
      // in every card that has one.
      final tiles = [
        for (final (id, _, _, icon) in _cards)
          if (icon != 'none') (tester.getRect(find.descendant(of: key('public-card-$id'), matching: find.byType(Icon)).first), tester.getRect(key('public-card-$id'))),
      ];
      expect(tiles, hasLength(3));
      for (final (id, _, _, icon) in _cards) {
        if (icon != 'none') expect(tester.widget<Icon>(find.descendant(of: key('public-card-$id'), matching: find.byType(Icon)).first).size, isNull, reason: 'default size');
      }
      for (final (icon, c) in tiles) {
        expect(icon.left - c.left, moreOrLessEquals(tiles.first.$1.left - tiles.first.$2.left));
        expect(icon.width, 52);
      }
    });

    testWidgets('a configured phone layout (2 per row) is kept', (tester) async {
      await pump(tester, _cardsBlock(options: {'mobileColumns': '2'}), _phone);
      final r = rects(tester);
      expect(r[0].top, moreOrLessEquals(r[1].top), reason: 'two in the first row');
      expect(r[0].width, moreOrLessEquals(r[1].width));
      expect(r[2].top, greaterThan(r[0].bottom));
      expect(tester.takeException(), isNull);
    });
  });

  group('tablet and desktop unchanged', () {
    for (final (name, size) in [('tablet', _tablet), ('desktop', _desktop)]) {
      testWidgets('$name: all in one row, equal widths, equal heights', (tester) async {
        await pump(tester, _cardsBlock(), size);
        expect(find.byKey(const Key('public-cards-b_cards00001-stack')), findsNothing);
        final r = rects(tester);
        for (final c in r) {
          expect(c.top, moreOrLessEquals(r.first.top));
          expect(c.width, moreOrLessEquals(r.first.width));
          expect(c.height, moreOrLessEquals(r.first.height));
        }
        for (var i = 1; i < r.length; i++) {
          expect(r[i].left - r[i - 1].right, moreOrLessEquals(24), reason: '24 px apart');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tablet: a configured 2 per row is kept', (tester) async {
      await pump(tester, _cardsBlock(options: {'tabletColumns': '2'}), _tablet);
      final r = rects(tester);
      expect(r[0].top, moreOrLessEquals(r[1].top));
      expect(r[2].top, greaterThan(r[0].bottom));
      expect(r[2].left, moreOrLessEquals(r[0].left));
      expect(r[0].width, moreOrLessEquals(r[2].width));
    });
  });
}
