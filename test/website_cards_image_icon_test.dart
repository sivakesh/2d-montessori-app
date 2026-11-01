// The Cards block: each card may have an image and/or an icon, both
// optional. On the page: the image as a banner across the top of the card
// (edge to edge, half as tall as the card is wide, covered: never stretched),
// then, padded, the icon, the title, the text and the link; nothing is drawn
// (and no space kept) for what isn't there. New cards start with no icon;
// saved cards are unchanged (an absent icon is still the star; an image size
// saved by an earlier version is kept and ignored). Every part is optional
// (the title too): a card needs an image, an icon, a title or some text, and
// a link alone isn't enough. Synthetic test data only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/public_website_image.dart';

const _desktop = Size(1400, 2400);
const _tablet = Size(820, 2400);
const _phone = Size(390, 2400);
const _narrow = Size(320, 2400);

WebsiteMedia _media(String id, {String alt = '', int width = 1200, int height = 600}) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      width: width,
      height: height,
      alt: LocalizedText(en: alt),
      status: WebsiteMediaStatus.published,
      consentConfirmed: true,
    );

// Landscape (2:1), a portrait certificate (2:3), and one without alt text.
final _library = [
  _media('m_class1', alt: 'Children at work'),
  _media('m_garden1', alt: 'The garden'),
  _media('m_cert01', alt: 'Certificate', width: 600, height: 900),
  _media('m_noalt1'),
];
final _published = {for (final m in _library) m.id: m};

Map<String, dynamic> _card(String id,
        {String title = 'Primary', String body = 'Ages 3 to 6, in a prepared environment.', String? icon, String? image, String? size, Object? height, String? target = '/programs'}) =>
    {
      'id': id,
      'icon': ?icon,
      'imageMediaId': ?image,
      'imageSize': ?size,
      'imageHeight': ?height,
      'title': {'en': title, 'ta': title.isEmpty ? '' : 'முதன்மை'},
      'body': {'en': body, 'ta': ''},
      'linkLabel': {'en': 'Learn more', 'ta': ''},
      'target': ?target,
      'accent': 'primary',
    };

StructuredBlock _block(List<Map<String, dynamic>> cards) =>
    BlockRegistry.parse({'id': 'b_cards00001', 'type': 'cards', 'v': 1, 'heading': {'en': 'Programmes', 'ta': ''}, 'cards': cards}) as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pump(WidgetTester tester, WebsiteBlock block, {Size at = _desktop, bool interactive = true}) async {
    tester.view.physicalSize = at;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: [block], media: _published, language: PublicLanguage.english, interactive: interactive, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder inCard(String id, Finder f) => find.descendant(of: key('public-card-$id'), matching: f);

  /// The icon's 52 px tile inside a card, if any.
  Finder iconTile(String id) => inCard(id, find.byWidgetPredicate((w) => w is Container && w.constraints == const BoxConstraints.tightFor(width: 52, height: 52)));

  group('saved cards', () {
    test('any one part makes a card; only an empty one (a link at most) is reported', () {
      List<String> problems(Map<String, dynamic> card) => BlockRegistry.blockProblems(_block([card]));
      final valid = {
        'title only': _card('i_card00001', icon: 'none', body: '', target: null),
        'text only': _card('i_card00001', title: '', icon: 'none', target: null),
        'image only': _card('i_card00001', title: '', body: '', icon: 'none', image: 'm_class1', target: null),
        'icon only': _card('i_card00001', title: '', body: '', icon: 'school', target: null),
        'image and text': _card('i_card00001', title: '', icon: 'none', image: 'm_class1'),
        'icon and text': _card('i_card00001', title: '', icon: 'school'),
        'image, title and text': _card('i_card00001', icon: 'none', image: 'm_class1'),
        'everything': _card('i_card00001', icon: 'school', image: 'm_class1', size: 'small'),
        'no description (as saved before)': _card('i_card00001', icon: 'family', body: ''),
        'an absent icon (the star)': {..._card('i_card00001', title: '', body: '')}..remove('icon'),
      };
      for (final e in valid.entries) {
        expect(problems(e.value), isEmpty, reason: e.key);
      }
      const empty = ['Card 1: add an image, an icon, a title or some text'];
      expect(problems(_card('i_card00001', title: '', body: '', icon: 'none', target: null)), empty, reason: 'nothing at all');
      expect(problems(_card('i_card00001', title: '', body: '', icon: 'none')), empty, reason: 'a link (with its text) alone isn’t content');
      expect(problems({..._card('i_card00001', title: '', body: '\n', icon: 'none', size: 'large'), 'title': {'en': '  ', 'ta': ' '}}), empty,
          reason: 'blank text and a size without an image');
      expect(problems({..._card('i_card00001', title: '', body: '', icon: 'none'), 'title': {'en': '', 'ta': 'முதன்மை'}}),
          ['Card 1: Title: enter the English text as well as the Tamil text.', ...empty],
          reason: 'English is every language’s fallback (the multilingual safeguard as before)');
      // Only the empty card is named.
      expect(
        BlockRegistry.blockProblems(_block([_card('i_card00001'), _card('i_card00002', title: '', body: '', icon: 'none')])),
        ['Card 2: add an image, an icon, a title or some text'],
      );
      expect(BlockRegistry.blockProblems(_block([_card('i_card00001', icon: 'rocket')])).single, contains('“rocket” is not a icon option'));
    });

    test('an existing card (no image) saves exactly as stored; an absent icon is still the star; the image is stored only when chosen', () {
      final old = _card('i_card00001', icon: 'family');
      final block = _block([old]);
      expect((block.toMap()['cards'] as List).single, old, reason: 'no imageMediaId added');
      final noIcon = _block([{..._card('i_card00002')}..remove('icon')]);
      expect(noIcon.items('cards').single.string('icon'), 'star', reason: 'an absent icon reads as the star it always showed');
      final withImage = _block([_card('i_card00001', icon: 'family', image: 'm_class1')]);
      expect(((withImage.toMap()['cards'] as List).single as Map)['imageMediaId'], 'm_class1');
      expect(BlockRegistry.referencedMedia([withImage]), ['m_class1'], reason: 'publishing checks the image like any other');
      expect(withImage.items('cards').single.text('title').textFor('ta'), 'முதன்மை', reason: 'Tamil kept');
      final unsized = _card('i_card00001', icon: 'none', image: 'm_class1');
      expect((_block([unsized]).toMap()['cards'] as List).single, unsized, reason: 'a card with an image, as stored');
    });

    test('a new card starts with no icon; a stored “none” stays none', () {
      final fresh = BlockRegistry.create(BlockRegistry.cards);
      final card = fresh.items('cards').single;
      expect(card.string('icon'), 'none');
      final stored = (fresh.toMap()['cards'] as List).single as Map;
      expect(stored['icon'], 'none', reason: 'stored, so it reads back as none (not the star)');
      expect(stored.containsKey('imageSize'), isFalse);
      expect(stored.containsKey('imageHeight'), isFalse);
      final again = BlockRegistry.parse(fresh.toMap()) as StructuredBlock;
      expect(again.items('cards').single.string('icon'), 'none');
    });

    test('image sizes saved by an earlier version: kept exactly as stored, never a problem', () {
      final saved = [
        _card('i_card00001', icon: 'school', image: 'm_class1', size: 'small'),
        _card('i_card00002', icon: 'none', image: 'm_class1', size: 'custom', height: 320),
        _card('i_card00003', icon: 'none', image: 'm_class1', size: 'custom', height: 9999),
        _card('i_card00004', icon: 'none', image: 'm_class1', size: 'huge', height: 'tall'),
        _card('i_card00005', icon: 'star', size: 'large', height: 20.5),
      ];
      final block = _block(saved);
      expect(BlockRegistry.blockProblems(block), isEmpty, reason: 'no longer settings: nothing to check');
      expect(block.toMap()['cards'], saved, reason: 'written back unchanged (no migration)');
      final again = BlockRegistry.parse(block.toMap()) as StructuredBlock;
      expect(again.toMap(), block.toMap());
      expect(again.items('cards')[1].text('title').textFor('ta'), 'முதன்மை', reason: 'Tamil kept');
    });
  });

  group('on the page', () {
    testWidgets('image, icon, title, text, link: in that order; each only when there', (tester) async {
      await pump(tester, _block([
        _card('i_card00001', title: 'Both', icon: 'school', image: 'm_class1'),
        _card('i_card00002', title: 'Image only', icon: 'none', image: 'm_garden1'),
        _card('i_card00003', title: 'Icon only', icon: 'nature'),
        _card('i_card00004', title: 'Neither', icon: 'none'),
      ]));
      expect(tester.takeException(), isNull);
      double top(Finder f) => tester.getRect(f).top;
      double bottom(Finder f) => tester.getRect(f).bottom;

      // Both: image, then icon, then title, text, link.
      final image1 = key('public-card-i_card00001-image');
      expect(top(image1), top(key('public-card-i_card00001')), reason: 'the banner at the very top');
      expect(top(iconTile('i_card00001')), closeTo(bottom(image1) + 28, 0.01), reason: 'the content padded below it');
      expect(bottom(iconTile('i_card00001')), lessThanOrEqualTo(top(inCard('i_card00001', find.text('Both')))));
      expect(bottom(inCard('i_card00001', find.text('Both'))), lessThanOrEqualTo(top(inCard('i_card00001', find.text('Ages 3 to 6, in a prepared environment.')))));
      expect(bottom(inCard('i_card00001', find.text('Ages 3 to 6, in a prepared environment.'))), lessThanOrEqualTo(top(inCard('i_card00001', find.text('Learn more')))));

      // Image only (no icon): no icon tile; the title right under the image.
      expect(iconTile('i_card00002'), findsNothing);
      expect(inCard('i_card00002', find.byIcon(Icons.star_outline)), findsNothing, reason: 'no placeholder star');
      expect(inCard('i_card00002', find.byIcon(Icons.arrow_forward_rounded)), findsOneWidget, reason: 'the link arrow only');
      expect(top(inCard('i_card00002', find.text('Image only'))), closeTo(bottom(key('public-card-i_card00002-image')) + 28, 0.01));

      // Icon only: the icon at the top, no image.
      final card3 = tester.getRect(key('public-card-i_card00003'));
      expect(key('public-card-i_card00003-image'), findsNothing);
      expect(top(iconTile('i_card00003')), closeTo(card3.top + 28, 0.01));
      expect(tester.widget<Icon>(inCard('i_card00003', find.byIcon(Icons.park_outlined))).icon, Icons.park_outlined);

      // Neither: the title first; no space kept.
      final card4 = tester.getRect(key('public-card-i_card00004'));
      expect(top(inCard('i_card00004', find.text('Neither'))), closeTo(card4.top + 28, 0.01));
      expect(iconTile('i_card00004'), findsNothing);
      expect(key('public-card-i_card00004-image'), findsNothing);
    });

    testWidgets('existing cards keep their icon (and an absent icon its star); an unpublished image takes no space', (tester) async {
      await pump(tester, _block([
        _card('i_card00001', icon: 'family'),
        {..._card('i_card00002')}..remove('icon'),
        _card('i_card00003', icon: 'none', image: 'm_not_published'),
      ]));
      expect(inCard('i_card00001', find.byIcon(Icons.family_restroom_outlined)), findsOneWidget);
      expect(inCard('i_card00002', find.byIcon(Icons.star_outline)), findsOneWidget, reason: 'as before');
      expect(key('public-card-i_card00003-image'), findsNothing);
      final card3 = tester.getRect(key('public-card-i_card00003'));
      expect(tester.getRect(inCard('i_card00003', find.text('Primary'))).top, closeTo(card3.top + 28, 0.01));
    });

    testWidgets('the banner: the card’s full width, half as tall, covered; every width', (tester) async {
      final block = _block([
        _card('i_card00001', title: 'One', icon: 'school', image: 'm_class1'),
        _card('i_card00002', title: 'Two', icon: 'none', image: 'm_cert01'),
        _card('i_card00003', title: '', body: '', icon: 'none', image: 'm_garden1', target: null),
        _card('i_card00004', title: 'Four', icon: 'none'),
      ]);
      final widths = <double>{};
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pump(tester, block, at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        for (final id in ['i_card00001', 'i_card00002', 'i_card00003']) {
          final card = tester.getRect(key('public-card-$id'));
          final image = tester.getRect(key('public-card-$id-image'));
          final why = '$id at ${at.width}';
          expect(card.right, lessThanOrEqualTo(at.width), reason: why);
          expect(image.left, card.left, reason: '$why: edge to edge');
          expect(image.width, closeTo(card.width, 0.01), reason: '$why: the full width');
          expect(image.height, closeTo(card.width / 2, 0.01), reason: '$why: half the width');
          expect(image.top, card.top, reason: '$why: at the top');
          widths.add(card.width);
        }
        // The rest padded below it; the portrait image is cropped, not squeezed.
        expect(tester.getRect(inCard('i_card00002', find.text('Two'))).top, closeTo(tester.getRect(key('public-card-i_card00002-image')).bottom + 28, 0.01));
        // No image: no banner, the card starts with its content.
        expect(key('public-card-i_card00004-image'), findsNothing);
        expect(tester.getRect(inCard('i_card00004', find.text('Four'))).top, closeTo(tester.getRect(key('public-card-i_card00004')).top + 28, 0.01), reason: 'at ${at.width}');
      }
      expect(widths.length, greaterThanOrEqualTo(3), reason: 'measured at several card widths');
      final images = tester.widgetList<PublicWebsiteImage>(find.byType(PublicWebsiteImage)).toList();
      expect({for (final i in images) (i.fit, i.aspectRatio, i.borderRadius)}, {(BoxFit.cover, 2.0, 0.0)},
          reason: 'covers its 2:1 frame (cropped, never stretched); the card’s corners round it');
    });

    testWidgets('the card’s rounded corners clip the banner; an image-only card is just the banner', (tester) async {
      await pump(tester, _block([_card('i_card00001', title: '', body: '', icon: 'none', image: 'm_class1', target: null)]), at: _phone);
      final material = tester.widget<Material>(find.descendant(of: key('public-card-i_card00001'), matching: find.byType(Material)).first);
      expect(material.clipBehavior, Clip.antiAlias);
      expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(20));
      expect(tester.getRect(key('public-card-i_card00001')).height, closeTo(tester.getRect(key('public-card-i_card00001-image')).height, 0.01), reason: 'no empty padding below');
    });

    testWidgets('screen readers: the image’s alt text once; without one, the title once (the image decorative)', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _block([
        _card('i_card00001', title: 'Garden', icon: 'none', image: 'm_garden1'),
        _card('i_card00002', title: 'Untitled photo', icon: 'none', image: 'm_noalt1'),
      ]), at: _tablet);
      // The alt text is the image's label (read when it loads; tests can't
      // load it, so the card reads "image unavailable" in its place).
      expect(tester.widget<PublicWebsiteImage>(key('public-card-i_card00001-image')).semanticLabel, 'The garden');
      bool excluded(String id) => tester.widget<ExcludeSemantics>(find.ancestor(of: key('public-card-$id-image'), matching: find.byType(ExcludeSemantics)).first).excluding;
      expect(excluded('i_card00001'), isFalse);
      expect(excluded('i_card00002'), isTrue, reason: 'no alt text: decorative');
      // Each card is one link: its parts read together, the title once.
      expect(find.bySemanticsLabel(RegExp('Garden')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Untitled photo\n')), findsOneWidget, reason: 'the title first, the image adding nothing');
      expect(find.bySemanticsLabel(RegExp('Untitled photo[\\s\\S]*Untitled photo')), findsNothing, reason: 'read once');
      expect(find.descendant(of: key('public-card-i_card00002-image'), matching: find.byType(Image)), findsOneWidget, reason: 'drawn all the same');
      handle.dispose();
    });

    testWidgets('the editor’s canvas draws the same cards; only the website follows the link', (tester) async {
      final block = _block([_card('i_card00001', title: 'One', icon: 'school', image: 'm_class1'), _card('i_card00002', title: 'Two', icon: 'none')]);
      await pump(tester, block);
      final published = {for (final id in ['i_card00001', 'i_card00002']) id: tester.getRect(key('public-card-$id'))};
      final enabled = tester.widget<InkWell>(inCard('i_card00001', find.byType(InkWell)).first).onTap;
      expect(enabled, isNotNull);
      await pump(tester, block, interactive: false);
      for (final e in published.entries) {
        expect(tester.getRect(key('public-card-${e.key}')), e.value);
      }
      expect(tester.widget<InkWell>(inCard('i_card00001', find.byType(InkWell)).first).onTap, isNull);
    });
  });

  group('without a title', () {
    testWidgets('each combination: only its parts, in order, with no gap for the title', (tester) async {
      await pump(tester, _block([
        _card('i_card00001', title: '', icon: 'none', target: null),
        _card('i_card00002', title: '', body: '', icon: 'none', image: 'm_class1', target: null),
        _card('i_card00003', title: '', body: '', icon: 'school', target: null),
        _card('i_card00004', title: '', icon: 'none', image: 'm_class1', target: null),
        _card('i_card00005', title: '', icon: 'school', target: null),
        _card('i_card00006', title: 'Title only', body: '', icon: 'none', target: null),
      ]), at: _tablet);
      expect(tester.takeException(), isNull);
      const body = 'Ages 3 to 6, in a prepared environment.';
      Rect rect(Finder f) => tester.getRect(f);
      Rect card(String id) => rect(key('public-card-$id'));
      // No title anywhere: nothing but the parts given.
      for (final id in ['i_card00001', 'i_card00002', 'i_card00003', 'i_card00004', 'i_card00005']) {
        expect(inCard(id, find.text('Primary')), findsNothing, reason: id);
        expect(inCard(id, find.byWidgetPredicate((w) => w is Text && (w.data ?? '').isEmpty)), findsNothing, reason: '$id: no empty title');
      }
      // Text only: the text at the top.
      expect(rect(inCard('i_card00001', find.text(body))).top, closeTo(card('i_card00001').top + 28, 0.01));
      // Image only / icon only: the card ends with it.
      expect(rect(key('public-card-i_card00002-image')).top, card('i_card00002').top);
      expect(rect(iconTile('i_card00003')).top, closeTo(card('i_card00003').top + 28, 0.01));
      // Image and text: the text padded under the banner; icon and text: 20 px under the icon.
      expect(rect(inCard('i_card00004', find.text(body))).top, closeTo(rect(key('public-card-i_card00004-image')).bottom + 28, 0.01));
      expect(rect(inCard('i_card00005', find.text(body))).top, closeTo(rect(iconTile('i_card00005')).bottom + 20, 0.01));
      // Title only.
      expect(rect(inCard('i_card00006', find.text('Title only'))).top, closeTo(card('i_card00006').top + 28, 0.01));
    });

    testWidgets('a card’s natural height: no blank space where the title would be', (tester) async {
      // Alone in a column (phones), so each card is as tall as its content.
      await pump(tester, _block([
        _card('i_card00001', title: '', icon: 'school', target: null),
        _card('i_card00002', icon: 'school', target: null),
      ]), at: _phone);
      final without = tester.getRect(key('public-card-i_card00001'));
      final withTitle = tester.getRect(key('public-card-i_card00002'));
      final title = tester.getRect(inCard('i_card00002', find.text('Primary')));
      expect(without.height, closeTo(withTitle.height - title.height - 8, 0.01), reason: 'only the title and its 8 px go');
      final text = tester.getRect(inCard('i_card00001', find.text('Ages 3 to 6, in a prepared environment.')));
      expect(without.bottom, closeTo(text.bottom + 28, 0.01));
    });

    testWidgets('a card with content and a link still shows and follows it', (tester) async {
      final opened = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') opened.add((call.arguments as Map)['url'] as String);
        return call.method == 'canLaunch' || call.method == 'launch';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await pump(tester, _block([
        _card('i_card00001', title: '', icon: 'none', image: 'm_class1', target: 'https://example.test/visit'),
      ]), at: _tablet);
      final text = tester.getRect(inCard('i_card00001', find.text('Ages 3 to 6, in a prepared environment.')));
      expect(tester.getRect(inCard('i_card00001', find.text('Learn more'))).top, closeTo(text.bottom + 20, 0.01));
      await tester.tap(inCard('i_card00001', find.text('Learn more')));
      await tester.pumpAndSettle();
      expect(opened, ['https://example.test/visit']);
      // An unsafe link is still refused, as before (and such a block isn't shown).
      expect(BlockRegistry.blockProblems(_block([_card('i_card00001', title: '', target: 'javascript:alert(1)')])).single, startsWith('Card 1: '));
    });
  });

  group('the editor', () {
    testWidgets('each card has an optional image (choose, replace, remove) and an icon with “None”', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var block = _block([_card('i_card00001', icon: 'family')]);
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
      const field = 'website-block-b_cards00001-cards-item-i_card00001-imageMediaId';
      expect(find.text('Image (optional)'), findsOneWidget);
      expect(key('$field-remove'), findsNothing, reason: 'nothing to remove yet');
      String image() => block.items('cards').single.string('imageMediaId');

      Future<void> choose(String id) async {
        await tester.tap(key('$field-choose'));
        await tester.pumpAndSettle();
        await tester.tap(key('website-choose-$id'));
        await tester.pumpAndSettle();
      }

      await choose('m_class1');
      expect(image(), 'm_class1');
      expect(find.descendant(of: key('$field-choose'), matching: find.text('Change')), findsOneWidget);
      await choose('m_garden1');
      expect(image(), 'm_garden1', reason: 'replaced');
      await tester.tap(key('$field-remove'));
      await tester.pumpAndSettle();
      expect(image(), isEmpty);
      expect(((block.toMap()['cards'] as List).single as Map).containsKey('imageMediaId'), isFalse, reason: 'removed: stored as before');
      expect(BlockRegistry.blockProblems(block), isEmpty);

      // Icon: "None" is offered, and chosen.
      const icon = 'website-block-b_cards00001-cards-item-i_card00001-icon';
      await tester.tap(key(icon));
      await tester.pumpAndSettle();
      expect(key('$icon-none'), findsWidgets);
      await tester.tap(key('$icon-none').last);
      await tester.pumpAndSettle();
      expect(block.items('cards').single.string('icon'), 'none');
      expect(find.text('None (no icon)'), findsOneWidget);
      expect(BlockRegistry.blockProblems(block), isEmpty, reason: 'a title alone is enough');
    });

    Future<void> pumpEditor(WidgetTester tester, StructuredBlock Function() current, void Function(StructuredBlock) update, {int generation = 0}) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteBlockForm(block: current(), library: _library, generation: generation, onChanged: (b) => setState(() => update(b as StructuredBlock))),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> pick(WidgetTester tester, String dropdown, String option) async {
      await tester.ensureVisible(find.byKey(Key(dropdown)));
      await tester.tap(find.byKey(Key(dropdown)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('$dropdown-$option')).last);
      await tester.pumpAndSettle();
    }

    testWidgets('an added card starts with no icon; an icon chosen and then None is gone from the card', (tester) async {
      var block = _block([_card('i_card00001', icon: 'family')]);
      await pumpEditor(tester, () => block, (b) => block = b);
      await tester.tap(key('website-block-b_cards00001-cards-add'));
      await tester.pumpAndSettle();
      final added = block.items('cards').last;
      expect(added.string('icon'), 'none');
      expect(block.items('cards').first.string('icon'), 'family', reason: 'the saved card keeps its icon');
      expect(((block.toMap()['cards'] as List).last as Map)['icon'], 'none');

      final icon = 'website-block-b_cards00001-cards-item-${added.id}-icon';
      await pick(tester, icon, 'school');
      expect(block.items('cards').last.string('icon'), 'school');
      await pick(tester, icon, 'none');
      expect(block.items('cards').last.string('icon'), 'none');

      // On the page: the first card's icon, none on the added one.
      final shown = block.withValue('cards', [block.items('cards').first, block.items('cards').last.withValue('title', const LocalizedText(en: 'Added'))]);
      await pump(tester, shown);
      expect(inCard('i_card00001', find.byIcon(Icons.family_restroom_outlined)), findsOneWidget);
      expect(iconTile(added.id), findsNothing);
      expect(tester.getRect(inCard(added.id, find.text('Added'))).top, closeTo(tester.getRect(key('public-card-${added.id}')).top + 28, 0.01));
    });

    testWidgets('no image-size settings; a size saved earlier is kept as stored', (tester) async {
      var block = _block([_card('i_card00001', icon: 'none', image: 'm_class1', size: 'custom', height: 320)]);
      await pumpEditor(tester, () => block, (b) => block = b);
      const item = 'website-block-b_cards00001-cards-item-i_card00001';
      expect(key('$item-imageMediaId-choose'), findsOneWidget);
      expect(key('$item-imageSize'), findsNothing);
      expect(find.text('Image size'), findsNothing);
      expect(find.textContaining('height'), findsNothing);
      // Another image chosen: the old values are carried along untouched.
      await tester.tap(key('$item-imageMediaId-choose'));
      await tester.pumpAndSettle();
      await tester.tap(key('website-choose-m_garden1'));
      await tester.pumpAndSettle();
      final stored = (block.toMap()['cards'] as List).single as Map;
      expect([stored['imageMediaId'], stored['imageSize'], stored['imageHeight']], ['m_garden1', 'custom', 320]);
      expect(BlockRegistry.blockProblems(block), isEmpty);
    });

    testWidgets('the Features block’s icons are unchanged (no “None” there)', (tester) async {
      final features = BlockRegistry.parse({
        'id': 'b_feat000001',
        'type': 'features',
        'v': 1,
        'items': [
          {'id': 'i_feat000001', 'icon': 'none', 'title': {'en': 'Point'}},
        ],
      });
      expect(BlockRegistry.blockProblems(features).single, contains('“none” is not a icon option'));
    });
  });
}
