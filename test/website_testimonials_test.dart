// The Testimonials block: quotes as cards, each with an avatar (a profile
// photo, else the person's initials, else none) and an optional star rating
// (0 to 5 in half stars; none unless the editor sets one), and every part of
// the presentation a setting. Initials, ratings, checks, saving, the page at
// each screen size (the editor's canvas is the same code), accessibility and
// the editor. Synthetic test data only.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_presets.dart';
import 'package:montessori_app/modules/public_website/content/blocks/testimonials.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_testimonials.dart' as public_testimonials;
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/public_website_image.dart';

const _desktop = Size(1400, 4000);
const _tablet = Size(820, 4000);
const _phone = Size(390, 4000);
const _narrow = Size(320, 4000);

WebsiteMedia _media(String id, {String alt = '', bool published = true}) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      width: 600,
      height: 600,
      alt: LocalizedText(en: alt),
      status: published ? WebsiteMediaStatus.published : WebsiteMediaStatus.draft,
      consentConfirmed: true,
    );

final _library = [
  _media('m_face000001', alt: 'Smiling parent in a garden'),
  _media('m_face000002'),
  _media('m_draft00001', alt: 'Not yet', published: false),
];
final _published = {for (final m in _library) if (m.isPublished) m.id: m};

const _blockId = 'b_testim00001';
String _iid(int i) => 'i_testim${i.toString().padLeft(5, '0')}';

Map<String, dynamic> _item(int i, {String? name, String quote = 'A lovely, calm place to learn.', Map<String, dynamic> extra = const {}}) => {
      'id': _iid(i),
      'name': {'en': name ?? 'Person Number$i', 'ta': ''},
      'quote': {'en': quote, 'ta': ''},
      ...extra,
    };

Map<String, dynamic> _raw({int count = 3, List<Map<String, dynamic>>? items, Map<String, dynamic> extra = const {}}) => {
      'id': _blockId,
      'type': 'testimonials',
      'v': 1,
      'testimonials': items ?? [for (var i = 1; i <= count; i++) _item(i)],
      ...extra,
    };

StructuredBlock _block({int count = 3, List<Map<String, dynamic>>? items, Map<String, dynamic> extra = const {}}) =>
    BlockRegistry.parse(_raw(count: count, items: items, extra: extra)) as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));
  String card(int i) => 'public-testimonial-${_iid(i)}';

  Future<void> pump(WidgetTester tester, WebsiteBlock block, {Size at = _desktop, PublicLanguage language = PublicLanguage.english}) async {
    tester.view.physicalSize = at;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: [block], media: _published, language: language, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  int stars(String kind) => find.byWidgetPredicate((w) => w is Icon && (w.key as ValueKey?)?.value.toString().endsWith('-$kind') == true).evaluate().length;

  BoxDecoration cardDecoration(WidgetTester tester, int i) => tester.widget<Container>(key(card(i))).decoration! as BoxDecoration;

  // ------------------------------------------------------------ rules
  group('initials and ratings', () {
    test('initials: the first letter of the first two words; one word, one letter', () {
      expect(Testimonials.initialsOf('Tanveer Razi'), 'TR');
      expect(Testimonials.initialsOf('Jisha Joseph'), 'JJ');
      expect(Testimonials.initialsOf('Yasmeen'), 'Y');
      expect(Testimonials.initialsOf('mary ann  smith'), 'MA', reason: 'more words: the first two, upper case');
      expect(Testimonials.initialsOf('  (Anu)   priya '), 'AP', reason: 'leading punctuation skipped');
      expect(Testimonials.initialsOf('— Ravi'), 'R', reason: 'a word without a letter is skipped');
      expect(Testimonials.initialsOf('கமலா தேவி'), 'கதே', reason: 'a Tamil letter with its vowel sign is one letter');
      expect(Testimonials.initialsOf(''), '');
      expect(Testimonials.initialsOf('  …  '), '');
    });

    test('ratings: none unless set; 0 to 5 in half stars', () {
      expect(Testimonials.ratings, ['none', '0', '0.5', '1', '1.5', '2', '2.5', '3', '3.5', '4', '4.5', '5']);
      final unrated = _block().items('testimonials').first;
      expect(Testimonials.ratingOf(unrated), isNull, reason: 'no rating is invented');
      for (final r in Testimonials.ratings.skip(1)) {
        final item = _block(items: [_item(1, extra: {'rating': r})]).items('testimonials').single;
        expect(Testimonials.ratingOf(item), double.parse(r));
      }
      expect(Testimonials.ratingText(4), '4');
      expect(Testimonials.ratingText(4.5), '4.5');
      expect(Testimonials.ratingText(0), '0');
    });
  });

  group('checks and saving', () {
    test('1 to 12 testimonials, each with text; a name, photo and rating are optional', () {
      expect(BlockRegistry.blockProblems(_block(count: 1)), isEmpty);
      expect(BlockRegistry.blockProblems(_block(count: 12)), isEmpty);
      expect(BlockRegistry.blockProblems(_block(items: [])), ['add at least 1 testimonial']);
      expect(BlockRegistry.blockProblems(_block(count: 13)), ['at most 12 testimonials']);
      expect(BlockRegistry.blockProblems(_block(items: [_item(1, quote: ' ')])), ['Testimonial 1: enter testimonial text in English']);
      expect(BlockRegistry.blockProblems(_block(items: [{'id': _iid(1), 'quote': {'en': 'Only words.'}}])), isEmpty, reason: 'no name needed');
    });

    test('invalid settings are reported; Automatic and in-range values are not', () {
      List<String> p(Map<String, dynamic> extra, [List<Map<String, dynamic>>? items]) => BlockRegistry.blockProblems(_block(extra: extra, items: items));
      expect(p({}, [_item(1, extra: {'rating': '10'})]).single, contains('Testimonial 1: “10” is not a rating option'));
      expect(p({'layout': 'carousel'}).single, contains('“carousel” is not a card layout option'));
      expect(p({'avatarSize': 200}).single, contains('avatar size must be from 24 to 120 px'));
      expect(p({'starSize': 4}).single, contains('star size must be from 12 to 40 px'));
      expect(p({'cardRadius': 60}).single, contains('card corner radius must be from 0 to 48 px'));
      expect(p({'starColor': 'pink'}).single, contains('“pink” is not a star colour option'));
      expect(
        p({
          'layout': 'horizontal',
          'desktopColumns': '2',
          'tabletColumns': '1',
          'mobileColumns': '2',
          'avatarSize': 72,
          'avatarBackground': '#20302A',
          'avatarBorderWidth': '2',
          'starColor': 'token:gold',
          'ratingNumber': 'outOf',
          'cardShadow': 'strong',
          'maxWidth': 900,
        }),
        isEmpty,
      );
    });

    test('a new block stores only what is set; everything survives saving and reloading; Tamil kept', () {
      final fresh = BlockRegistry.create(BlockRegistry.testimonials).toMap();
      expect(fresh.keys.toSet(), {'id', 'type', 'v', 'testimonials'}, reason: 'no settings until set');
      expect(((fresh['testimonials'] as List).single as Map).keys.toSet(), {'id', 'name', 'quote'}, reason: 'no rating, role, photo, date or label invented');

      final raw = _raw(items: [
        _item(1, name: 'Tanveer Razi', extra: {
          'quote': {'en': 'Our son loves it.', 'ta': 'எங்கள் மகனுக்கு மிகவும் பிடிக்கும்.'},
          'role': {'en': 'Parent', 'ta': 'பெற்றோர்'},
          'rating': '4.5',
          'photoMediaId': 'm_face000001',
          'date': {'en': 'March 2025', 'ta': ''},
          'verification': {'en': 'Verified parent', 'ta': ''},
        }),
        _item(2, extra: {'hideRating': true, 'rating': '3'}),
      ], extra: {
        'heading': {'en': 'What families say', 'ta': 'குடும்பங்கள் சொல்வது'},
        'layout': 'compact',
        'showRatings': false,
        'gap': 20,
        'futureSetting': {'kept': true},
      });
      final block = BlockRegistry.parse(raw) as StructuredBlock;
      expect(BlockRegistry.blockProblems(block), isEmpty);
      expect(block.toMap(), raw, reason: 'written back exactly as stored');
      final again = BlockRegistry.parse(block.toMap()) as StructuredBlock;
      expect([for (final i in again.items('testimonials')) i.id], [_iid(1), _iid(2)]);
      expect(again.items('testimonials').first.text('quote').textFor('ta'), 'எங்கள் மகனுக்கு மிகவும் பிடிக்கும்.');
      expect(again.text('heading').textFor('ta'), 'குடும்பங்கள் சொல்வது');
      expect(BlockRegistry.referencedMedia([again]), ['m_face000001'], reason: 'publishing checks the photo');
    });

    test('a saved testimonial without a rating or photo stays so; offered once in Add block; the preset and other blocks unchanged', () {
      final old = {'id': _iid(1), 'name': {'en': 'Jisha Joseph', 'ta': ''}, 'quote': {'en': 'Wonderful teachers.', 'ta': ''}};
      final block = _block(items: [old]);
      expect(block.toMap()['testimonials'], [old], reason: 'nothing added on save');
      expect(Testimonials.ratingOf(block.items('testimonials').single), isNull);
      expect([for (final d in BlockRegistry.all) if (d.label == 'Testimonials') d.type], ['testimonials'], reason: 'one Testimonials block');
      expect(BlockRegistry.nestable, contains(BlockRegistry.testimonials));
      final preset = SectionPreset.all.firstWhere((p) => p.id == 'testimonials').create();
      final inside = [for (final c in preset.columns('columns')) for (final b in c.blocks) b.type];
      expect(inside, ['text', 'text', 'text'], reason: 'the section preset and pages built with it are untouched');
    });
  });

  // ------------------------------------------------------------ page
  group('on the page', () {
    testWidgets('avatars: the photo, else initials; none without either; unpublished photos fall back', (tester) async {
      await pump(
        tester,
        _block(items: [
          _item(1, name: 'Tanveer Razi', extra: {'photoMediaId': 'm_face000001'}),
          _item(2, name: 'Jisha Joseph'),
          _item(3, name: 'Yasmeen', extra: {'photoMediaId': 'm_draft00001'}),
          {'id': _iid(4), 'quote': {'en': 'No name given.'}},
          _item(5, name: ' ', extra: {'photoMediaId': 'm_face000002'}),
        ]),
      );
      expect(key('${card(1)}-photo'), findsOneWidget);
      expect(key('${card(1)}-initials'), findsNothing);
      expect(tester.widget<PublicWebsiteImage>(find.descendant(of: key('${card(1)}-photo'), matching: find.byType(PublicWebsiteImage))).borderRadius, greaterThan(20), reason: 'circular');
      expect(find.descendant(of: key('${card(2)}-initials'), matching: find.text('JJ')), findsOneWidget);
      expect(find.descendant(of: key('${card(3)}-initials'), matching: find.text('Y')), findsOneWidget, reason: 'an unpublished photo isn’t shown');
      expect(key('${card(4)}-avatar'), findsNothing, reason: 'no empty avatar');
      expect(key('${card(4)}-name'), findsNothing);
      expect(key('${card(5)}-photo'), findsOneWidget, reason: 'a photo without a name');
      expect(tester.takeException(), isNull);

      await pump(tester, _block(extra: {'showAvatars': false}));
      expect(find.byKey(const Key('public-testimonial-i_testim00001-avatar')), findsNothing);
    });

    testWidgets('ratings 0 to 5 in half stars; no rating, no stars; the global and per-testimonial switches', (tester) async {
      for (final r in Testimonials.ratings.skip(1)) {
        await pump(tester, _block(items: [_item(1, extra: {'rating': r})]));
        final v = double.parse(r);
        expect(stars('full'), v.floor(), reason: r);
        expect(stars('half'), v == v.floorToDouble() ? 0 : 1, reason: r);
        expect(stars('empty'), 5 - v.ceil(), reason: r);
      }
      await pump(tester, _block(items: [_item(1), _item(2, extra: {'rating': '5', 'hideRating': true}), _item(3, extra: {'rating': '4'})]));
      expect(key('${card(1)}-rating'), findsNothing, reason: 'unrated: no empty stars, no space');
      expect(key('${card(2)}-rating'), findsNothing, reason: 'hidden for this one');
      expect(key('${card(3)}-rating'), findsOneWidget);
      expect(key('${card(3)}-rating-number'), findsNothing, reason: 'stars only by default');

      await pump(tester, _block(items: [_item(3, extra: {'rating': '4'})], extra: {'showRatings': false}));
      expect(key('${card(3)}-rating'), findsNothing, reason: 'ratings off for the block');

      await pump(tester, _block(items: [_item(1, extra: {'rating': '4.5'})], extra: {'ratingNumber': 'number'}));
      expect(tester.widget<Text>(key('${card(1)}-rating-number')).data, '4.5');
      await pump(tester, _block(items: [_item(1, extra: {'rating': '5'})], extra: {'ratingNumber': 'outOf'}));
      expect(find.text('5.0 / 5'), findsOneWidget);
    });

    testWidgets('every layout at every screen size, long text and many cards: no overflow', (tester) async {
      final long = List.filled(16, 'Our children grew in confidence and independence every single week.').join(' ');
      for (final layout in Testimonials.layouts) {
        for (final size in [_desktop, _tablet, _phone, _narrow]) {
          await pump(
            tester,
            _block(
              items: [
                for (var i = 1; i <= 12; i++)
                  _item(i, name: 'Averyveryverylongfirstname Averyveryverylonglastname', quote: i == 1 ? long : 'Short.', extra: {'rating': '3.5', 'role': {'en': 'Parent of two children in Primary'}, 'location': {'en': 'Chennai'}, 'verification': {'en': 'Verified parent'}}),
              ],
              extra: {'layout': layout, 'ratingNumber': 'outOf', 'desktopColumns': '4', 'mobileColumns': '2'},
            ),
            at: size,
          );
          expect(tester.takeException(), isNull, reason: '$layout at $size');
          final width = size.width;
          for (var i = 1; i <= 12; i++) {
            final r = tester.getRect(key(card(i)));
            expect(r.left, greaterThanOrEqualTo(0), reason: '$layout $size $i');
            expect(r.right, lessThanOrEqualTo(width + 0.01), reason: '$layout $size $i');
          }
        }
      }
    });

    testWidgets('cards per row: 3 on desktop, 2 on tablets, 1 on phones; each overridable; fewer when too narrow', (tester) async {
      int firstRow(WidgetTester tester) {
        final top = tester.getRect(key(card(1))).top;
        return [for (var i = 1; i <= 6; i++) if (key(card(i)).evaluate().isNotEmpty) tester.getRect(key(card(i))).top].where((t) => (t - top).abs() < 0.5).length;
      }

      await pump(tester, _block(count: 6));
      expect(firstRow(tester), 3);
      expect(tester.getRect(key(card(1))).height, tester.getRect(key(card(2))).height, reason: 'a row’s cards share its height');
      await pump(tester, _block(count: 6), at: _tablet);
      expect(firstRow(tester), 2);
      await pump(tester, _block(count: 6), at: _phone);
      expect(firstRow(tester), 1);
      await pump(tester, _block(count: 2));
      expect(firstRow(tester), 2, reason: 'Automatic: no more than there are');

      final set = {'desktopColumns': '4', 'tabletColumns': '3', 'mobileColumns': '2'};
      await pump(tester, _block(count: 6, extra: set));
      expect(firstRow(tester), 4);
      await pump(tester, _block(count: 6, extra: set), at: _tablet);
      expect(firstRow(tester), 3);
      await pump(tester, _block(count: 6, extra: set), at: _phone);
      expect(firstRow(tester), 1, reason: 'two cards of 220 px don’t fit on a 390 px phone');
      await pump(tester, _block(count: 6, extra: {...set, 'gap': 0, 'cardPadding': 8}), at: const Size(500, 4000));
      expect(firstRow(tester), 2);
    });

    testWidgets('vertical, horizontal and compact place the avatar, name, rating and text', (tester) async {
      final items = [_item(1, name: 'Tanveer Razi', extra: {'rating': '4'})];
      await pump(tester, _block(items: items));
      final avatar = tester.getRect(key('${card(1)}-avatar'));
      final name = tester.getRect(key('${card(1)}-name'));
      final rating = tester.getRect(key('${card(1)}-rating'));
      final quote = tester.getRect(key('${card(1)}-quote'));
      expect(avatar.bottom, lessThanOrEqualTo(name.top), reason: 'vertical: avatar, name, rating, text');
      expect(name.bottom, lessThanOrEqualTo(rating.top));
      expect(rating.bottom, lessThanOrEqualTo(quote.top));
      expect(avatar.center.dx, closeTo(tester.getRect(key(card(1))).center.dx, 1), reason: 'centred by default');

      await pump(tester, _block(items: items, extra: {'layout': 'horizontal'}));
      expect(tester.getRect(key('${card(1)}-avatar')).right, lessThan(tester.getRect(key('${card(1)}-name')).left), reason: 'beside');

      await pump(tester, _block(items: items, extra: {'layout': 'compact'}));
      expect(tester.getRect(key('${card(1)}-quote')).bottom, lessThanOrEqualTo(tester.getRect(key('${card(1)}-name')).top), reason: 'the person below the text');
      expect(tester.getSize(key('${card(1)}-avatar')).width, 40, reason: 'a smaller avatar');

      await pump(tester, _block(items: items, extra: {'contentAlign': 'start', 'avatarAlign': 'end', 'ratingAlign': 'center'}));
      final box = tester.getRect(key(card(1)));
      expect(tester.getRect(key('${card(1)}-avatar')).right, closeTo(box.right - 28, 1));
      expect(tester.getRect(key('${card(1)}-rating')).center.dx, closeTo(box.center.dx, 1));
      expect(tester.widget<Text>(key('${card(1)}-quote')).textAlign, TextAlign.start);
    });

    testWidgets('appearance: card colour, border, corners, padding, shadow; avatar and star settings; spacing', (tester) async {
      await pump(tester, _block(items: [_item(1, name: 'Jisha Joseph', extra: {'rating': '5'})]));
      var d = cardDecoration(tester, 1);
      expect(d.color, SiteDesign.defaults.colorOf('surface'));
      expect((d.border! as Border).top.width, 1);
      expect(d.borderRadius, BorderRadius.circular(16));
      expect(d.boxShadow, isNotEmpty, reason: 'soft by default');
      expect(tester.getSize(key('${card(1)}-avatar')).width, 56);

      await pump(
        tester,
        _block(items: [_item(1, name: 'Jisha Joseph', extra: {'rating': '5'})], extra: {
          'cardBackground': '#F2F2F0',
          'cardBorderWidth': '0',
          'cardRadius': 4,
          'cardPadding': 40,
          'cardShadow': 'none',
          'avatarSize': 80,
          'avatarBackground': '#20302A',
          'avatarTextColor': '#FFFFFF',
          'avatarBorderWidth': '2',
          'avatarBorderColor': '#B7791F',
          'starColor': '#123456',
          'starSize': 30,
          'elementGap': 24,
        }),
      );
      d = cardDecoration(tester, 1);
      expect(d.color, const Color(0xFFF2F2F0));
      expect(d.border, isNull);
      expect(d.borderRadius, BorderRadius.circular(4));
      expect(d.boxShadow, isNull);
      expect(tester.getRect(key('${card(1)}-avatar')).top - tester.getRect(key(card(1))).top, 40, reason: 'padding');
      expect(tester.getSize(key('${card(1)}-avatar')).width, 80);
      final ring = tester.widget<Container>(key('${card(1)}-avatar')).decoration! as BoxDecoration;
      expect((ring.border! as Border).top, const BorderSide(color: Color(0xFFB7791F), width: 2));
      final initials = tester.widget<Text>(find.descendant(of: key('${card(1)}-initials'), matching: find.text('JJ')));
      expect(initials.style!.color, const Color(0xFFFFFFFF));
      final star = tester.widget<Icon>(key('${card(1)}-star-0-full'));
      expect(star.color, const Color(0xFF123456));
      expect(star.size, 30);
      expect(tester.getRect(key('${card(1)}-name')).top - tester.getRect(key('${card(1)}-avatar')).bottom, 24, reason: 'space between parts');
    });

    testWidgets('section: eyebrow, heading and description optional; maximum width, alignment and space', (tester) async {
      await pump(tester, _block(count: 1));
      expect(key('public-testimonials-$_blockId-heading'), findsNothing, reason: 'nothing above the cards unless entered');

      await pump(
        tester,
        _block(count: 2, extra: {
          'eyebrow': {'en': 'KIND WORDS'},
          'heading': {'en': 'What families say'},
          'description': {'en': 'In their own words.'},
          'maxWidth': 700,
          'align': 'start',
          'paddingTop': 40,
          'paddingBottom': 30,
        }),
      );
      expect(find.text('KIND WORDS'), findsOneWidget);
      expect(find.text('What families say'), findsOneWidget);
      expect(find.text('In their own words.'), findsOneWidget);
      final cards = tester.getRect(key(card(1))).expandToInclude(tester.getRect(key(card(2))));
      expect(cards.width, closeTo(700, 0.5));
      final section = tester.getRect(key('public-testimonials-$_blockId'));
      expect(tester.getRect(key('public-testimonials-$_blockId-eyebrow')).top - section.top, 40);
      expect(section.bottom - cards.bottom, 30);
      expect(tester.getRect(key('public-testimonials-$_blockId-heading')).left, closeTo(cards.left, 0.5), reason: 'left aligned');
    });

    testWidgets('only what is entered: details, verification label; nothing to show, no block', (tester) async {
      await pump(tester, _block(items: [_item(1), _item(2, extra: {'date': {'en': 'March 2025'}, 'location': {'en': 'Chennai'}, 'verification': {'en': 'Verified parent'}})]));
      expect(key('${card(1)}-details'), findsNothing);
      expect(key('${card(1)}-verification'), findsNothing, reason: 'never claimed unless entered');
      expect(key('${card(1)}-role'), findsNothing);
      expect(find.text('March 2025 · Chennai'), findsOneWidget);
      expect(find.text('Verified parent'), findsOneWidget);

      // Text only in Tamil: English visitors have nothing to see.
      final tamilOnly = _block(items: [_item(1, extra: {'quote': {'en': '', 'ta': 'தமிழில் மட்டும்.'}})]);
      expect(public_testimonials.PublicTestimonials.hasContent(tamilOnly, PublicLanguage.english), isFalse);
      expect(public_testimonials.PublicTestimonials.hasContent(tamilOnly, PublicLanguage.tamil), isTrue);
      await pump(tester, _block(items: [_item(1, quote: '')]));
      expect(key('public-block-$_blockId'), findsNothing, reason: 'a testimonial needs its text');
    });

    testWidgets('saved, reloaded and published: the same; Tamil shown in Tamil, English where none', (tester) async {
      final raw = _raw(items: [
        _item(1, name: 'Tanveer Razi', extra: {'quote': {'en': 'Calm and kind.', 'ta': 'அமைதியும் அன்பும்.'}, 'rating': '4.5'}),
        _item(2, name: 'Jisha Joseph'),
      ]);
      final published = BlockRegistry.withoutHidden([BlockRegistry.parse(BlockRegistry.parse(raw).toMap())]).single;
      await pump(tester, published, language: PublicLanguage.tamil);
      expect(find.text('அமைதியும் அன்பும்.'), findsOneWidget);
      expect(find.text('A lovely, calm place to learn.'), findsOneWidget, reason: 'falls back to English');
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(PublicStrings.of(PublicLanguage.tamil).ratingOutOfFive('4.5')), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('screen readers: the rating in words, initials named after the person, photos described', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        _block(items: [
          _item(1, name: 'Tanveer Razi', extra: {'rating': '4.5'}),
          _item(2, name: 'Jisha Joseph', extra: {'photoMediaId': 'm_face000001'}),
          _item(3, name: 'Yasmeen', extra: {'photoMediaId': 'm_face000002'}),
          _item(4, name: 'Anu', extra: {'photoMediaId': 'm_face000002', 'photoAlt': {'en': 'Anu at sports day'}}),
          _item(5, name: 'Ravi', extra: {'rating': '0'}),
        ]),
      );
      expect(find.bySemanticsLabel('4.5 out of 5 stars'), findsOneWidget);
      expect(find.bySemanticsLabel('0 out of 5 stars'), findsOneWidget);
      expect(find.bySemanticsLabel('Initials of Tanveer Razi'), findsOneWidget);
      expect(find.bySemanticsLabel('TR'), findsNothing, reason: 'the letters themselves aren’t read');
      PublicWebsiteImage photo(int i) => tester.widget<PublicWebsiteImage>(find.descendant(of: key('${card(i)}-photo'), matching: find.byType(PublicWebsiteImage)));
      expect(photo(2).semanticLabel, 'Smiling parent in a garden', reason: 'the library’s alt text');
      expect(photo(3).semanticLabel, 'Photo of Yasmeen', reason: 'none in the library: named after the person');
      expect(photo(4).semanticLabel, 'Anu at sports day', reason: 'its own description first');
      semantics.dispose();
    });
  });

  // ------------------------------------------------------------ editor
  group('the editor', () {
    Future<StructuredBlock Function()> edit(WidgetTester tester, StructuredBlock start) async {
      var block = start;
      tester.view.physicalSize = const Size(1000, 8000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteBlockForm(block: block, library: _library, generation: 0, onChanged: (b) => setState(() => block = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => block;
    }

    const prefix = 'website-block-$_blockId';
    String item(int i) => '$prefix-testimonials-item-${_iid(i)}';

    Future<void> open(WidgetTester tester, String group) async {
      await tester.ensureVisible(key(group));
      await tester.tap(key(group));
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String dropdown, String option) async {
      await tester.ensureVisible(key(dropdown));
      await tester.tap(key(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$dropdown-$option')).last);
      await tester.pumpAndSettle();
    }

    testWidgets('settings grouped and closed at first; settings of a feature that is off aren’t offered; Reset to Automatic', (tester) async {
      final block = await edit(tester, _block());
      for (final g in ['layout', 'avatars', 'ratings', 'card-appearance', 'section-size-and-spacing']) {
        expect(key('$prefix-group-$g'), findsOneWidget, reason: g);
      }
      expect(key('$prefix-avatarSize'), findsNothing, reason: 'closed');
      await open(tester, '$prefix-group-avatars');
      expect(key('$prefix-avatarSize'), findsOneWidget);
      expect(key('$prefix-avatarBorderColor'), findsNothing, reason: 'no border yet');
      await pick(tester, '$prefix-avatarBorderWidth', '2');
      expect(key('$prefix-avatarBorderColor'), findsOneWidget);
      await tester.enterText(key('$prefix-avatarSize'), '72');
      await tester.pump();
      expect(block().values['avatarSize'], 72);
      await tester.tap(key('$prefix-avatarSize-reset'));
      await tester.pump();
      expect(block().toMap().containsKey('avatarSize'), isFalse, reason: 'Automatic is not stored');
      await tester.tap(key('$prefix-showAvatars'));
      await tester.pumpAndSettle();
      expect(block().toggle('showAvatars'), isFalse);
      expect(key('$prefix-avatarSize'), findsNothing, reason: 'avatars off: their settings hidden');

      await open(tester, '$prefix-group-ratings');
      expect(key('$prefix-starColor'), findsOneWidget);
      await tester.tap(key('$prefix-showRatings'));
      await tester.pumpAndSettle();
      expect(key('$prefix-starColor'), findsNothing);
      expect(key('$prefix-ratingNumber'), findsNothing);
      expect(block().toMap()['showRatings'], isFalse);

      await open(tester, '$prefix-group-layout');
      await pick(tester, '$prefix-layout', 'compact');
      await pick(tester, '$prefix-tabletColumns', '3');
      expect(block().string('layout'), 'compact');
      expect(block().string('tabletColumns'), '3');
    });

    testWidgets('each testimonial: rating, photo and details easy to find; the avatar and rating previewed as they change', (tester) async {
      final block = await edit(tester, _block(items: [_item(1, name: 'Tanveer Razi')]));
      expect(key('${item(1)}-rating'), findsOneWidget, reason: 'not tucked away in a group');
      expect(key('${item(1)}-photoMediaId-choose'), findsOneWidget);
      expect(find.descendant(of: key('${item(1)}-preview-initials'), matching: find.text('TR')), findsOneWidget);
      expect(tester.widget<Text>(key('${item(1)}-preview-rating')).data, 'No rating');
      expect(key('${item(1)}-hideRating'), findsNothing, reason: 'nothing to hide yet');
      expect(key('${item(1)}-photoAlt'), findsNothing, reason: 'no photo yet');
      expect(key('$prefix-testimonials-item-${_iid(1)}-group-more-details-optional'), findsOneWidget);

      await pick(tester, '${item(1)}-rating', '4.5');
      expect(block().items('testimonials').single.string('rating'), '4.5');
      expect(find.text('★★★★½  4.5 / 5'), findsOneWidget);
      expect(key('${item(1)}-hideRating'), findsOneWidget);
      await tester.tap(key('${item(1)}-hideRating'));
      await tester.pumpAndSettle();
      expect(find.text('Rating hidden (4.5 / 5)'), findsOneWidget);

      await tester.enterText(key('${item(1)}-name-en-0'), 'Yasmeen');
      await tester.pump();
      expect(find.descendant(of: key('${item(1)}-preview-initials'), matching: find.text('Y')), findsOneWidget);
      await tester.enterText(key('${item(1)}-name-en-0'), '');
      await tester.pump();
      expect(key('${item(1)}-preview-initials'), findsNothing);
      expect(find.text('No name or photo: no avatar is shown'), findsOneWidget);
      expect(blockSummary(block()), '1 testimonial(s)');
    });

    testWidgets('a profile photo from the media library: chosen, previewed, described, removed', (tester) async {
      final block = await edit(tester, _block(items: [_item(1, name: 'Tanveer Razi', extra: {'photoMediaId': 'm_face000001'})]));
      expect(key('${item(1)}-preview-photo'), findsOneWidget);
      expect(key('${item(1)}-photoAlt-en-0'), findsOneWidget);
      await tester.tap(key('${item(1)}-photoMediaId-remove'));
      await tester.pumpAndSettle();
      expect(block().items('testimonials').single.string('photoMediaId'), '');
      expect(block().toMap()['testimonials'][0].containsKey('photoMediaId'), isFalse);
      expect(key('${item(1)}-preview-initials'), findsOneWidget, reason: 'initials instead');
      expect(key('${item(1)}-photoAlt-en-0'), findsNothing);
    });
  });
}
