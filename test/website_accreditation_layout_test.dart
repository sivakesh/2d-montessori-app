// Accreditations & Recognition: the layout inside each certificate card and
// logo (image position, text alignment, content position, image size,
// spacing and card padding). Blocks without the settings look and save
// exactly as before; each setting is applied on cards and in the logo
// strip, at desktop, tablet and phone widths, without overflow; the
// editor groups the settings and its canvas draws what visitors see.
// Synthetic test data only.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_accreditations.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/public_website_image.dart';

const _desktop = Size(1400, 3000);
const _tablet = Size(820, 3000);
const _phone = Size(390, 3000);
const _narrow = Size(320, 3000);

WebsiteMedia _media(String id, {int width = 400, int height = 200}) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      width: width,
      height: height,
      alt: const LocalizedText(en: ''),
      status: WebsiteMediaStatus.published,
      consentConfirmed: true,
    );

final _published = {for (final m in [_media('m_logo1'), _media('m_logo2'), _media('m_cert1', width: 800, height: 600)]) m.id: m};

/// Item 1: a logo, a credential, a description, dates and a link (the
/// tallest). Item 2: a logo and a name only. Item 3: a certificate image
/// and a logo. Item 4: no image (a badge).
List<Map<String, dynamic>> _items() => [
      {
        'id': 'i_accred0001',
        'name': {'en': 'Synthetic Montessori Council', 'ta': 'செயற்கை மாண்டிசோரி மன்றம்'},
        'title': {'en': 'Member school', 'ta': ''},
        'logoMediaId': 'm_logo1',
        'description': {'en': 'Annual membership reviewed every spring by a visiting panel.', 'ta': ''},
        'target': 'https://example.test/registry/123',
        'issued': {'en': '2024-03'},
        'expires': {'en': '2027-03'},
      },
      {'id': 'i_accred0002', 'name': {'en': 'Synthetic Teacher Board', 'ta': ''}, 'logoMediaId': 'm_logo2'},
      {'id': 'i_accred0003', 'name': {'en': 'Synthetic Early Years Forum', 'ta': ''}, 'certificateMediaId': 'm_cert1', 'logoMediaId': 'm_logo1'},
      {'id': 'i_accred0004', 'name': {'en': 'Synthetic Quality Mark', 'ta': ''}},
    ];

Map<String, dynamic> _raw({String display = 'cards', Map<String, Object?> layout = const {}, List<Map<String, dynamic>>? items}) => {
      'id': 'b_accred0001',
      'type': 'accreditations',
      'v': 1,
      'heading': {'en': 'Accreditations', 'ta': 'அங்கீகாரங்கள்'},
      'display': display,
      'items': items ?? _items(),
      ...layout,
    };

StructuredBlock _block({String display = 'cards', Map<String, Object?> layout = const {}, List<Map<String, dynamic>>? items}) =>
    BlockRegistry.parse(_raw(display: display, layout: layout, items: items)) as StructuredBlock;

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

  Rect rect(WidgetTester tester, String k) => tester.getRect(key(k));
  Rect card(WidgetTester tester, String id) => rect(tester, 'public-accreditation-$id');

  /// The drawn picture (logo, certificate or badge) inside an item.
  Rect picture(WidgetTester tester, String id) {
    final visual = key('public-accreditation-$id-visual');
    final drawn = find.descendant(of: visual, matching: find.byWidgetPredicate((w) => w is AspectRatio || (w is Container && w.constraints?.maxWidth == 48)));
    return tester.getRect(drawn.first);
  }

  TextAlign? textAlignOf(WidgetTester tester, String id, String text) =>
      tester.renderObject<RenderParagraph>(find.descendant(of: key('public-accreditation-$id-text'), matching: find.text(text))).textAlign;

  group('saved settings', () {
    test('a block without the settings saves exactly as stored; each setting is stored only when changed', () {
      final old = _raw();
      final block = BlockRegistry.parse(old) as StructuredBlock;
      for (final k in ['imageAlign', 'textAlign', 'verticalAlign', 'imageSize', 'imageSpacing', 'cardPadding']) {
        expect(block.toMap().containsKey(k), isFalse, reason: '$k is not added to an existing block');
      }
      expect(AccreditationLayout.of(block), const AccreditationLayout());
      expect(BlockRegistry.blockProblems(block), isEmpty);

      const settings = {'imageAlign': 'center', 'textAlign': 'right', 'verticalAlign': 'center', 'imageSize': 'large', 'imageSpacing': '24', 'cardPadding': '32'};
      final set = _block(layout: settings);
      expect({for (final k in settings.keys) k: set.toMap()[k]}, settings);
      expect(AccreditationLayout.of(set), const AccreditationLayout(imageAlign: 'center', textAlign: 'right', verticalAlign: 'center', imageSize: 'large', imageSpacing: '24', cardPadding: '32'));
      expect(BlockRegistry.blockProblems(set), isEmpty);
      // Items, their images, links and Tamil text are untouched.
      expect(set.toMap()['items'], _block().toMap()['items']);
      expect(set.items('items').first.text('name').textFor('ta'), 'செயற்கை மாண்டிசோரி மன்றம்');

      expect(BlockRegistry.blockProblems(_block(layout: {'imageAlign': 'diagonal'})), isNotEmpty);
      expect(BlockRegistry.blockProblems(_block(layout: {'cardPadding': '200'})), isNotEmpty);
    });
  });

  group('cards', () {
    testWidgets('without settings: only the image, as before (left, 64 px logo, 20 px padding, at the top); no text or link on the card', (tester) async {
      await pump(tester, _block());
      final c = card(tester, 'i_accred0001');
      final logo = picture(tester, 'i_accred0001');
      expect(logo.left, closeTo(c.left + 21, 0.01), reason: '20 px padding inside a 1 px border');
      expect(logo.top, closeTo(c.top + 21, 0.01));
      expect(logo.height, 64);
      expect(c.height, closeTo(64 + 42, 0.01), reason: 'the card holds the image only');
      for (final id in ['i_accred0001', 'i_accred0002', 'i_accred0003', 'i_accred0004']) {
        expect(key('public-accreditation-$id-text'), findsNothing, reason: id);
        expect(key('public-accreditation-$id-link'), findsNothing, reason: id);
        expect(find.descendant(of: key('public-accreditation-$id'), matching: find.byType(Text)), findsNothing, reason: '$id: no title, organisation, dates or description');
      }
      expect(rect(tester, 'public-accreditation-i_accred0003-visual').width, closeTo(c.width - 42, 0.01), reason: 'the certificate fills the card');
    });

    for (final (side, expectedAt) in [('left', 0.0), ('center', 0.5), ('right', 1.0)]) {
      testWidgets('image position: $side (logo, certificate and badge)', (tester) async {
        await pump(tester, _block(layout: {'imageAlign': side, 'imageSize': 'small'}));
        for (final id in ['i_accred0001', 'i_accred0003', 'i_accred0004']) {
          final area = rect(tester, 'public-accreditation-$id-visual');
          final p = picture(tester, id);
          final free = area.width - p.width;
          expect(free, greaterThan(10), reason: '$id has room to move');
          expect(p.left - area.left, closeTo(free * expectedAt, 0.5), reason: '$id $side');
        }
        expect(picture(tester, 'i_accred0003').width, closeTo(rect(tester, 'public-accreditation-i_accred0003-visual').width * 0.5, 0.5), reason: 'a small certificate is half the width');
      });
    }

    testWidgets('text alignment and spacing apply to the logo strip; cards (image only) look the same with any of them', (tester) async {
      await pump(tester, _block());
      final before = {for (final id in ['i_accred0001', 'i_accred0003', 'i_accred0004']) id: (card(tester, id), picture(tester, id))};
      await pump(tester, _block(layout: {'textAlign': 'right', 'imageSpacing': '32'}));
      for (final e in before.entries) {
        expect((card(tester, e.key), picture(tester, e.key)), e.value, reason: e.key);
      }
    });

    testWidgets('content position: top keeps cards to their image; centre makes a row one height with the image in the middle', (tester) async {
      await pump(tester, _block(layout: {'verticalAlign': 'top'}));
      expect(card(tester, 'i_accred0002').height, lessThan(card(tester, 'i_accred0003').height));
      expect(picture(tester, 'i_accred0002').top, closeTo(card(tester, 'i_accred0002').top + 21, 0.01));

      await pump(tester, _block(layout: {'verticalAlign': 'center'}));
      expect(tester.takeException(), isNull);
      final tall = card(tester, 'i_accred0003');
      final short = card(tester, 'i_accred0002');
      expect(short.height, closeTo(tall.height, 0.01), reason: 'the same row, the same height');
      final above = picture(tester, 'i_accred0002').top - short.top;
      final below = short.bottom - picture(tester, 'i_accred0002').bottom;
      expect(above, closeTo(below, 0.5), reason: 'as much space above as below');
      expect(above, greaterThan(40));
    });

    testWidgets('image sizes and padding', (tester) async {
      for (final (size, height) in [('small', 48.0), ('medium', 72.0), ('large', 104.0)]) {
        await pump(tester, _block(layout: {'imageSize': size, 'cardPadding': '32'}));
        final c = card(tester, 'i_accred0002');
        final logo = picture(tester, 'i_accred0002');
        expect(logo.height, height, reason: size);
        expect(logo.left, closeTo(c.left + 33, 0.01), reason: '32 px padding');
        expect(c.height, closeTo(height + 66, 0.01), reason: '32 px padding above and below');
      }
      await pump(tester, _block(layout: {'cardPadding': '12', 'imageSize': 'medium'}));
      final c = card(tester, 'i_accred0003');
      expect(rect(tester, 'public-accreditation-i_accred0003-visual').width, closeTo(c.width - 26, 0.5), reason: 'the area spans the card (12 px padding, 1 px border)');
      expect(picture(tester, 'i_accred0003').width, closeTo((c.width - 26) * 0.75, 0.5), reason: 'a medium certificate is three quarters');
    });

    testWidgets('desktop, tablet and phone: every combination stays inside its card and the screen', (tester) async {
      const settings = [
        {'imageAlign': 'right', 'textAlign': 'center', 'verticalAlign': 'center', 'imageSize': 'large', 'imageSpacing': '32', 'cardPadding': '32'},
        {'imageAlign': 'center', 'textAlign': 'right', 'imageSize': 'small', 'cardPadding': '12'},
      ];
      for (final layout in settings) {
        for (final at in [_desktop, _tablet, _phone, _narrow]) {
          await pump(tester, _block(layout: layout), at: at);
          expect(tester.takeException(), isNull, reason: '$layout at ${at.width}');
          for (final id in ['i_accred0001', 'i_accred0002', 'i_accred0003', 'i_accred0004']) {
            final c = card(tester, id);
            expect(c.right, lessThanOrEqualTo(at.width), reason: '$id at ${at.width}');
            final r = picture(tester, id);
            expect(r.left >= c.left - 0.01 && r.right <= c.right + 0.01 && r.bottom <= c.bottom + 0.01, isTrue, reason: '$id at ${at.width}');
          }
        }
      }
    });

    testWidgets('several cards per row keep the settings (2 per row on phones)', (tester) async {
      await pump(tester, _block(layout: {'mobileColumns': '2', 'imageAlign': 'center', 'textAlign': 'center', 'verticalAlign': 'center'}), at: _phone);
      expect(tester.takeException(), isNull);
      expect(card(tester, 'i_accred0002').top, card(tester, 'i_accred0001').top);
      expect(card(tester, 'i_accred0002').height, closeTo(card(tester, 'i_accred0001').height, 0.01));
      final area = rect(tester, 'public-accreditation-i_accred0002-visual');
      expect(picture(tester, 'i_accred0002').center.dx, closeTo(area.center.dx, 0.5));
    });
  });

  group('logo strip', () {
    testWidgets('without settings: as before (centred 72 px logo, centred text 8 px below, tops aligned)', (tester) async {
      await pump(tester, _block(display: 'logos'));
      final slot = card(tester, 'i_accred0001');
      final logo = picture(tester, 'i_accred0001');
      expect(slot.width, PublicAccreditationLogo.width);
      expect(logo.center.dx, closeTo(slot.center.dx, 0.5));
      expect(logo.height, 72);
      expect(rect(tester, 'public-accreditation-i_accred0001-text').top, closeTo(slot.top + 72 + 8, 0.01));
      expect(textAlignOf(tester, 'i_accred0001', 'Synthetic Montessori Council'), TextAlign.center);
      expect(card(tester, 'i_accred0002').top, slot.top);
    });

    for (final (side, align, at) in [('left', TextAlign.left, 0.0), ('center', TextAlign.center, 0.5), ('right', TextAlign.right, 1.0)]) {
      testWidgets('image and text: $side', (tester) async {
        await pump(tester, _block(display: 'logos', layout: {'imageAlign': side, 'textAlign': side, 'imageSize': 'small'}));
        final slot = card(tester, 'i_accred0002');
        final logo = picture(tester, 'i_accred0002');
        expect(logo.left - slot.left, closeTo((slot.width - logo.width) * at, 0.5));
        expect(textAlignOf(tester, 'i_accred0002', 'Synthetic Teacher Board'), align);
      });
    }

    testWidgets('sizes, spacing and centre: logos in a row centred on each other; no overflow at any width', (tester) async {
      for (final (size, height) in [('small', 48.0), ('medium', 72.0), ('large', 104.0)]) {
        await pump(tester, _block(display: 'logos', layout: {'imageSize': size, 'imageSpacing': '24'}));
        // A 2:1 logo in a 160 px slot is at most 80 px tall.
        final drawn = height > 80 ? 80.0 : height;
        expect(picture(tester, 'i_accred0002').height, drawn, reason: size);
        expect(picture(tester, 'i_accred0002').width, lessThanOrEqualTo(PublicAccreditationLogo.width));
        expect(rect(tester, 'public-accreditation-i_accred0002-text').top, closeTo(card(tester, 'i_accred0002').top + height + 24, 0.01));
      }
      await pump(tester, _block(display: 'logos', layout: {'verticalAlign': 'center'}));
      expect(card(tester, 'i_accred0001').center.dy, closeTo(card(tester, 'i_accred0002').center.dy, 0.5), reason: 'a taller item (two lines) and a shorter one share a middle');
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pump(tester, _block(display: 'logos', layout: {'imageAlign': 'right', 'textAlign': 'left', 'verticalAlign': 'center', 'imageSize': 'large', 'imageSpacing': '32'}), at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        for (final id in ['i_accred0001', 'i_accred0002', 'i_accred0003', 'i_accred0004']) {
          expect(card(tester, id).right, lessThanOrEqualTo(at.width), reason: '$id at ${at.width}');
        }
      }
    });
  });

  group('organisation optional', () {
    Map<String, dynamic> item(String id, {String name = '', String title = '', String? logo, String? certificate, String? target}) => {
          'id': id,
          'name': {'en': name, 'ta': ''},
          if (title.isNotEmpty) 'title': {'en': title, 'ta': ''},
          'logoMediaId': ?logo,
          'certificateMediaId': ?certificate,
          'target': ?target,
        };

    test('an accreditation needs an organisation, a credential or an image, not all three; other checks unchanged', () {
      for (final ok in [
        item('i_a', title: 'Quality mark'),
        item('i_a', logo: 'm_logo1'),
        item('i_a', certificate: 'm_cert1'),
        item('i_a', name: 'Synthetic Council'),
      ]) {
        expect(BlockRegistry.blockProblems(_block(items: [ok])), isEmpty, reason: '$ok');
      }
      expect(BlockRegistry.blockProblems(_block(items: [item('i_a')])).single, 'Accreditation 1: add an organisation, a credential or an image');
      final tamilOnly = {
        'id': 'i_a',
        'name': {'en': '', 'ta': 'மன்றம்'},
        'logoMediaId': 'm_logo1',
      };
      expect(BlockRegistry.blockProblems(_block(items: [tamilOnly])).join(), contains('English'), reason: 'Tamil still needs the English');
      expect(BlockRegistry.blockProblems(_block(items: [item('i_a', name: 'x' * 121)])).join(), contains('120 characters'));
      expect(BlockRegistry.blockProblems(_block(items: [item('i_a', logo: 'm_logo1', target: 'javascript:alert(1)')])), isNotEmpty);
    });

    testWidgets('cards and the logo strip: no empty text or gap; screen readers get the credential, else “Accreditation”', (tester) async {
      final items = [
        item('i_accred0001', title: 'Quality mark', logo: 'm_logo1', target: 'https://example.test/q'),
        item('i_accred0002', logo: 'm_logo2'),
        item('i_accred0003', name: 'Synthetic Council', logo: 'm_logo1'),
      ];
      final semantics = tester.ensureSemantics();
      for (final display in ['cards', 'logos']) {
        await pump(tester, _block(display: display, items: items));
        expect(tester.takeException(), isNull);
        final empty = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').trim().isEmpty);
        expect(find.descendant(of: key('public-accreditations-b_accred0001-$display'), matching: empty), findsNothing, reason: display);
        // Only a logo: no text area and no gap under it.
        expect(key('public-accreditation-i_accred0002-text'), findsNothing, reason: display);
        if (display == 'cards') {
          final c = card(tester, 'i_accred0002');
          expect(c.height, closeTo(picture(tester, 'i_accred0002').height + 42, 0.01), reason: 'padding only');
          // Cards hold the image only; screen readers name the card.
          expect(tester.getSemantics(key('public-accreditation-i_accred0001')).label, startsWith('Quality mark: show details'));
          expect(tester.getSemantics(key('public-accreditation-i_accred0002')).label, startsWith('Accreditation: show details'));
        } else {
          expect(find.descendant(of: key('public-accreditation-i_accred0001-text'), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data), ['Quality mark']);
        }
        final labels = [for (final i in tester.widgetList<PublicWebsiteImage>(find.byType(PublicWebsiteImage))) i.semanticLabel];
        expect(labels, ['Quality mark logo', 'Accreditation logo', 'Synthetic Council logo'], reason: display);
      }
      semantics.dispose();
    });
  });

  group('the editor', () {
    testWidgets('the settings are grouped; a change shows at once; the canvas matches the website; only the website opens the details', (tester) async {
      tester.view.physicalSize = const Size(900, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var block = _block();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: Column(children: [
                WebsiteBlockForm(block: block, library: const [], generation: 0, onChanged: (b) => setState(() => block = b as StructuredBlock)),
                WebsiteDesignScope(
                  design: SiteDesign.defaults,
                  child: WebsiteBlocksView(blocks: [block], media: _published, language: PublicLanguage.english, interactive: false, fullBleed: true),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      const prefix = 'website-block-b_accred0001';
      expect(key('$prefix-layout-heading'), findsOneWidget);
      final fields = ['imageAlign', 'textAlign', 'verticalAlign', 'imageSize', 'imageSpacing', 'cardPadding'];
      final tops = [for (final f in fields) tester.getRect(key('$prefix-$f')).top];
      expect(tops, orderedEquals([...tops]..sort()), reason: 'one after another');
      expect(tester.getRect(key('$prefix-layout-heading')).top, lessThan(tops.first));

      await tester.ensureVisible(key('$prefix-imageAlign'));
      await tester.tap(key('$prefix-imageAlign'));
      await tester.pumpAndSettle();
      await tester.tap(key('$prefix-imageAlign-center').last);
      await tester.pumpAndSettle();
      expect(block.toMap()['imageAlign'], 'center');
      final area = rect(tester, 'public-accreditation-i_accred0002-visual');
      expect(picture(tester, 'i_accred0002').center.dx, closeTo(area.center.dx, 0.5), reason: 'the canvas shows it at once');
      final canvasCards = {for (final id in ['i_accred0001', 'i_accred0002']) id: card(tester, id).size};
      expect(key('public-accreditation-i_accred0001-open'), findsNothing, reason: 'the canvas doesn’t open the details');

      // The website, at the same width, with the same block.
      await pump(tester, block, at: const Size(900, 4000));
      for (final e in canvasCards.entries) {
        expect(card(tester, e.key).size, e.value, reason: e.key);
      }
      expect(picture(tester, 'i_accred0002').center.dx, closeTo(rect(tester, 'public-accreditation-i_accred0002-visual').center.dx, 0.5));
      expect(key('public-accreditation-i_accred0001-open'), findsOneWidget, reason: 'the website does');
    });
  });
}
