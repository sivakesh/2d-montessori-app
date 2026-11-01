// Accreditations & Recognition: each card (and logo-strip slot) is one
// button that opens the accreditation's details, and each accreditation
// can have its own card background.
// - The whole card opens the details: image, text, empty space; Enter and
//   Space; Escape, Close or a click outside close it; focus returns; the
//   page behind can't be used meanwhile. In the editor nothing opens.
// - The details show only what was entered (images whole, the credential
//   as the title, the organisation under it, description, dates, a safe
//   link that opens without touching the card), on a white surface, full
//   screen on phones.
// - Backgrounds: automatic (white, as before), transparent (the section
//   shows), white, the presets, a custom colour; per item, stored only
//   when set; light text on a dark colour; cards and the logo strip.
// Synthetic test data only.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

const _desktop = Size(1400, 2400);
const _tablet = Size(820, 2400);
const _phone = Size(390, 2400);
const _narrow = Size(320, 2400);

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

const _long = 'Annual membership reviewed every spring by a visiting panel of experienced Montessori educators, '
    'covering the prepared environment, the work cycle, observation records and family partnership.';

Map<String, dynamic> _item(String id, {String name = '', String title = '', String? logo, String? certificate, String description = '', String issued = '', String expires = '', String? target, String? background}) => {
      'id': id,
      'name': {'en': name, 'ta': ''},
      if (title.isNotEmpty) 'title': {'en': title, 'ta': ''},
      'logoMediaId': ?logo,
      'certificateMediaId': ?certificate,
      if (description.isNotEmpty) 'description': {'en': description, 'ta': ''},
      if (issued.isNotEmpty) 'issued': {'en': issued},
      if (expires.isNotEmpty) 'expires': {'en': expires},
      'target': ?target,
      'background': ?background,
    };

/// 1: everything (logo only). 2: a credential and a certificate only.
/// 3: both images, an issue date. 4: a name only, an expiry date.
List<Map<String, dynamic>> _items() => [
      _item('i_accred0001',
          name: 'Synthetic Montessori Council', title: 'Member school', logo: 'm_logo1', description: _long, issued: '2024-03', expires: '2027-03', target: 'https://example.test/registry/123'),
      _item('i_accred0002', title: 'Quality mark', certificate: 'm_cert1'),
      _item('i_accred0003', name: 'Synthetic Teacher Board', logo: 'm_logo2', certificate: 'm_cert1', issued: '2023'),
      _item('i_accred0004', name: 'Synthetic Early Years Forum', expires: '2028-06-30'),
    ];

StructuredBlock _block({String display = 'cards', List<Map<String, dynamic>>? items, Map<String, Object?> style = const {}}) => BlockRegistry.parse({
      'id': 'b_accred0001',
      'type': 'accreditations',
      'v': 1,
      'heading': {'en': 'Accreditations', 'ta': 'அங்கீகாரங்கள்'},
      'display': display,
      'items': items ?? _items(),
      if (style.isNotEmpty) 'style': style,
    }) as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));
  final dialog = find.byType(PublicAccreditationDetails);
  const d = 'public-accreditation-details';

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

  Rect card(WidgetTester tester, String id) => tester.getRect(key('public-accreditation-$id'));
  String? shownTitle(WidgetTester tester) => dialog.evaluate().isEmpty ? null : tester.widget<Text>(key('$d-title')).data;

  Future<void> close(WidgetTester tester) async {
    await tester.tap(key('$d-close'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  }

  /// Records what url_launcher is asked to open.
  List<String> launches() {
    final opened = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') opened.add((call.arguments as Map)['url'] as String);
      return call.method == 'canLaunch' || call.method == 'launch';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return opened;
  }

  /// Whether keyboard focus is inside [finder].
  bool focusedIn(WidgetTester tester, Finder finder) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    final target = tester.element(finder);
    var found = identical(focused, target);
    focused.visitAncestorElements((e) {
      if (identical(e, target)) found = true;
      return !found;
    });
    return found;
  }

  Color? cardColor(WidgetTester tester, String id) => tester.widget<Material>(key('public-accreditation-$id')).color;

  group('the whole card opens the details', () {
    testWidgets('the card shows only its image; the image and the empty space around it open that card’s details', (tester) async {
      await pump(tester, _block());
      for (final id in ['i_accred0001', 'i_accred0002', 'i_accred0003', 'i_accred0004']) {
        expect(find.descendant(of: key('public-accreditation-$id'), matching: find.byType(Text)), findsNothing, reason: '$id: no text on the card');
        expect(find.descendant(of: key('public-accreditation-$id'), matching: find.byType(ButtonStyleButton)), findsNothing, reason: '$id: no link on the card');
      }
      expect(find.text('Member school'), findsNothing);
      expect(find.text('More information'), findsNothing);
      final c = card(tester, 'i_accred0001');
      final targets = <String, Future<void> Function()>{
        'image': () => tester.tap(find.descendant(of: key('public-accreditation-i_accred0001-visual'), matching: find.byType(PublicWebsiteImage))),
        'empty space': () => tester.tapAt(c.bottomRight - const Offset(8, 8)),
        'padding at the top': () => tester.tapAt(c.topRight + const Offset(-8, 8)),
      };
      for (final MapEntry(key: name, value: tap) in targets.entries) {
        await tap();
        await tester.pumpAndSettle();
        expect(shownTitle(tester), 'Member school', reason: name);
        await close(tester);
      }
      await tester.tapAt(card(tester, 'i_accred0004').center);
      await tester.pumpAndSettle();
      expect(shownTitle(tester), 'Synthetic Early Years Forum', reason: 'each card its own');
      await close(tester);
    });

    testWidgets('logo strip: anywhere in a slot opens that accreditation', (tester) async {
      await pump(tester, _block(display: 'logos'));
      for (final (id, title) in [('i_accred0001', 'Member school'), ('i_accred0002', 'Quality mark'), ('i_accred0004', 'Synthetic Early Years Forum')]) {
        final slot = card(tester, id);
        for (final at in [slot.center, slot.topLeft + const Offset(4, 4), slot.bottomRight - const Offset(4, 4)]) {
          await tester.tapAt(at);
          await tester.pumpAndSettle();
          expect(shownTitle(tester), title, reason: '$id at $at');
          await close(tester);
        }
      }
      expect(tester.widget<SizedBox>(key('public-accreditation-i_accred0001')).width, PublicAccreditationLogo.width, reason: 'the slot keeps its size');
    });

    testWidgets('keyboard: Tab reaches the card; Enter and Space open; focus moves to Close; Escape closes and focus returns', (tester) async {
      await pump(tester, _block());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(focusedIn(tester, key('public-accreditation-i_accred0001-open')), isTrue);
      for (final activate in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        await tester.sendKeyEvent(activate);
        await tester.pumpAndSettle();
        expect(shownTitle(tester), 'Member school', reason: '$activate');
        expect(focusedIn(tester, key('$d-close')), isTrue, reason: 'focus moves into the details');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(focusedIn(tester, key('public-accreditation-i_accred0001-open')), isTrue, reason: 'focus returns to the card');
      }
      // No link on the card: the next stop is the next card.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(focusedIn(tester, key('public-accreditation-i_accred0002-open')), isTrue);
    });

    testWidgets('while open the page can’t be used: a click outside closes the details and opens nothing else', (tester) async {
      await pump(tester, _block());
      await tester.tap(key('public-accreditation-i_accred0001-open'));
      await tester.pumpAndSettle();
      expect(find.byType(ModalBarrier), findsWidgets);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.byType(PublicAccreditationDetails), findsNothing);
    });

    testWidgets('screen readers: each card is a button named by its organisation (else credential); the details are a named dialog', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, _block());
      // A button with a tap action, named first, then what it shows.
      for (final (id, name) in [('i_accred0001', 'Synthetic Montessori Council: show details'), ('i_accred0002', 'Quality mark: show details')]) {
        final node = tester.getSemantics(key('public-accreditation-$id'));
        expect(node, isSemantics(isButton: true, hasTapAction: true, isFocusable: true), reason: id);
        expect(node.label, startsWith(name), reason: id);
      }
      await tester.tap(key('public-accreditation-i_accred0001-open'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(key('$d-content')), isSemantics(label: 'Member school', scopesRoute: true, namesRoute: true));
      expect(tester.getSemantics(key('$d-title')), isSemantics(isHeader: true, label: 'Member school'));
      expect(tester.getSemantics(key('$d-close')), isSemantics(isButton: true, tooltip: 'Close'));
      semantics.dispose();
    });

    testWidgets('in the editor (the canvas) nothing opens: no button, no pointer; it looks the same', (tester) async {
      await pump(tester, _block());
      final published = {for (final id in ['i_accred0001', 'i_accred0002']) id: card(tester, id)};
      await pump(tester, _block(), interactive: false);
      expect(key('public-accreditation-i_accred0001-open'), findsNothing);
      for (final e in published.entries) {
        expect(card(tester, e.key), e.value, reason: 'the canvas matches the website');
      }
      await tester.tapAt(card(tester, 'i_accred0001').center);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      await pump(tester, _block(display: 'logos'), interactive: false);
      await tester.tapAt(card(tester, 'i_accred0001').center);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
    });

    testWidgets('“Verify” opens exactly the address entered, once, without reopening the details', (tester) async {
      final opened = launches();
      const address = 'https://www.iao.org/India-TamilNadu/2D-Montessori?ref=Card#Seal';
      await pump(tester, _block(items: [_item('i_accred0001', title: 'Member school', logo: 'm_logo1', target: address)]));
      await tester.tap(key('public-accreditation-i_accred0001-open'));
      await tester.pumpAndSettle();
      final verify = key('$d-link');
      expect(find.descendant(of: verify, matching: find.text('Verify')), findsOneWidget, reason: 'the label is exactly “Verify”');
      expect(find.text('More information'), findsNothing);
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(opened, [address], reason: 'the exact address: no other host, no relative address');
      expect(dialog, findsOneWidget, reason: 'one details view, still open; the card isn’t triggered again');
      await tester.tap(verify);
      await tester.pumpAndSettle();
      expect(opened, [address, address]);
      expect(dialog, findsOneWidget);
    });
  });

  group('what the details show', () {
    Future<void> open(WidgetTester tester, String id, {Size at = _desktop, List<Map<String, dynamic>>? items}) async {
      await pump(tester, _block(items: items), at: at);
      await tester.ensureVisible(key('public-accreditation-$id-open'));
      await tester.pumpAndSettle();
      await tester.tap(key('public-accreditation-$id-open'));
      await tester.pumpAndSettle();
    }

    List<String> keys(WidgetTester tester) => [
          for (final k in ['title', 'organisation', 'logo', 'certificate', 'description', 'issued', 'expires', 'link'])
            if (key('$d-$k').evaluate().isNotEmpty) k,
        ];

    void noEmptyText(WidgetTester tester) {
      expect(find.descendant(of: dialog, matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').trim().isEmpty)), findsNothing);
    }

    testWidgets('organisation and credential, a logo, a description, both dates and a link', (tester) async {
      await open(tester, 'i_accred0001');
      expect(keys(tester), ['title', 'organisation', 'logo', 'description', 'issued', 'expires', 'link']);
      expect(tester.widget<Text>(key('$d-title')).data, 'Member school', reason: 'the credential is the title');
      expect(tester.widget<Text>(key('$d-organisation')).data, 'Synthetic Montessori Council');
      expect(tester.widget<Text>(key('$d-description')).data, _long);
      expect(tester.widget<Text>(key('$d-issued')).data, 'Issued March 2024');
      expect(tester.widget<Text>(key('$d-expires')).data, 'Expires March 2027');
      expect(tester.getSize(find.descendant(of: key('$d-logo'), matching: find.byType(PublicWebsiteImage))).height, closeTo(120, 0.5), reason: 'logo only: shown large');
      noEmptyText(tester);
    });

    testWidgets('no organisation; a certificate only; nothing else', (tester) async {
      await open(tester, 'i_accred0002');
      expect(keys(tester), ['title', 'certificate']);
      expect(tester.widget<Text>(key('$d-title')).data, 'Quality mark');
      final image = tester.getSize(find.descendant(of: key('$d-certificate'), matching: find.byType(PublicWebsiteImage)));
      expect(image.width / image.height, closeTo(800 / 600, 0.01), reason: 'whole, uncropped: its own shape');
      expect(tester.widget<PublicWebsiteImage>(find.descendant(of: key('$d-certificate'), matching: find.byType(PublicWebsiteImage))).fit, BoxFit.contain);
      noEmptyText(tester);
    });

    testWidgets('both images: the certificate, and the logo small beside the title (each once); an issue date only', (tester) async {
      await open(tester, 'i_accred0003');
      expect(keys(tester), ['title', 'logo', 'certificate', 'issued']);
      expect(tester.widget<Text>(key('$d-title')).data, 'Synthetic Teacher Board', reason: 'no credential: the organisation is the title');
      expect(find.descendant(of: dialog, matching: find.byType(PublicWebsiteImage)), findsNWidgets(2));
      final logo = tester.getRect(key('$d-logo'));
      expect(logo.height, lessThanOrEqualTo(56));
      expect(logo.bottom, lessThanOrEqualTo(tester.getRect(key('$d-certificate')).top), reason: 'in the header, above the certificate');
      expect(tester.widget<Text>(key('$d-issued')).data, 'Issued 2023');
    });

    testWidgets('no images, an expiry date only; no credential or organisation: “Accreditation”', (tester) async {
      await open(tester, 'i_accred0004');
      expect(keys(tester), ['title', 'expires']);
      expect(tester.widget<Text>(key('$d-expires')).data, 'Expires 30 June 2028');
      await close(tester);
      await open(tester, 'i_x', items: [_item('i_x', logo: 'm_logo1')]);
      expect(keys(tester), ['title', 'logo']);
      expect(tester.widget<Text>(key('$d-title')).data, 'Accreditation');
    });

    testWidgets('an unsafe link is never offered (the block also reports it)', (tester) async {
      final unsafe = _block(items: [_item('i_x', title: 'Quality mark', target: 'javascript:alert(1)')]).items('items').single;
      final view = AccreditationView.of(unsafe, _published, PublicLanguage.english);
      expect(view.target, '');
      expect(BlockRegistry.blockProblems(_block(items: [_item('i_x', title: 'Quality mark', target: 'javascript:alert(1)')])), isNotEmpty);
      tester.view.physicalSize = _desktop;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const style = AccreditationStyle(title: TextStyle(fontSize: 18), body: TextStyle(), muted: TextStyle(), accent: Colors.green, line: Colors.grey, badge: Colors.white);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PublicAccreditationDetails(item: view, style: style, language: PublicLanguage.english, onOpen: (_) => fail('nothing to open')))));
      expect(key('$d-link'), findsNothing);
      expect(keys(tester), ['title']);
    });

    test('Verify is offered only for a real address: never one a browser would open as 0.0.0.2, a local machine or a relative address', () {
      for (final bad in [
        'https://2',
        'https://2/',
        'https://0.0.0.2',
        'https://0x2',
        'https://２',
        'https://127.0.0.1/cert',
        'https://localhost/cert',
        'https://intranet/cert',
        'https://example.123',
        'https://-bad.example.org',
        'http://www.example.org/cert',
        'www.example.org/cert',
        'example.org',
        'javascript:alert(1)',
        '',
      ]) {
        expect(AccreditationView.verifiable(bad), isFalse, reason: bad);
      }
      for (final good in [
        'https://www.iao.org/India-TamilNadu/2D-Montessori',
        'https://sub.example.co.uk/a/b?c=1&d=2#e',
        'https://xn--fiq228c.com/cert',
        'mailto:office@example.org',
        '/admissions',
      ]) {
        expect(AccreditationView.verifiable(good), isTrue, reason: good);
      }
    });

    testWidgets('a saved link like https://2: the block still shows (it was valid before), the details have no Verify, and the editor says why', (tester) async {
      final block = _block(items: [_item('i_accred0001', title: 'Member school', logo: 'm_logo1', target: 'https://2')]);
      expect(BlockRegistry.blockProblems(block), isEmpty, reason: 'unchanged validation: published blocks stay visible');
      await pump(tester, block);
      await tester.tap(key('public-accreditation-i_accred0001-open'));
      await tester.pumpAndSettle();
      expect(key('$d-link'), findsNothing);
      expect(find.text('Verify'), findsNothing);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WebsiteBlockForm(block: block, library: const [], generation: 0, onChanged: (_) {})))));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('website-block-b_accred0001-links'), matching: find.textContaining('Accreditation 1: https://2 is not a website address')), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WebsiteBlockForm(block: _block(), library: const [], generation: 0, onChanged: (_) {})))));
      await tester.pumpAndSettle();
      expect(key('website-block-b_accred0001-links'), findsNothing, reason: 'nothing to say for good links');
    });

    testWidgets('desktop: a centred dialog at most 640 px wide; phones: full screen, scrollable, nothing wider than the screen', (tester) async {
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await open(tester, 'i_accred0001', at: Size(at.width, 700));
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        // The dialog's surface (the Dialog widget itself fills the screen).
        final box = tester.getRect(key('$d-content'));
        if (at.width >= PublicAccreditationDetails.fullScreenBelow) {
          expect(box.width, lessThanOrEqualTo(PublicAccreditationDetails.maxWidth));
          expect(box.center.dx, closeTo(at.width / 2, 1));
        } else {
          expect(box.width, at.width, reason: 'full screen at ${at.width}');
        }
        for (final k in ['title', 'description', 'link', 'close']) {
          await tester.ensureVisible(key('$d-$k'));
          await tester.pumpAndSettle();
          final r = tester.getRect(key('$d-$k'));
          expect(r.left >= 0 && r.right <= at.width && r.bottom <= 700, isTrue, reason: '$k at ${at.width}');
        }
        expect(tester.getSize(key('$d-description')).height, greaterThan(40), reason: 'a long description wraps');
        await close(tester);
      }
      await open(tester, 'i_accred0002', at: const Size(320, 700));
      final image = tester.getSize(find.descendant(of: key('$d-certificate'), matching: find.byType(PublicWebsiteImage)));
      expect(image.width / image.height, closeTo(800 / 600, 0.01));
      expect(image.width, lessThanOrEqualTo(320));
    });

    testWidgets('the details are white whatever the card or section colour', (tester) async {
      await pump(tester, _block(items: [_item('i_accred0001', title: 'Member school', background: '#1F2A24')], style: {'background': 'token:forest', 'textColor': '#FFFFFF'}));
      await tester.tap(key('public-accreditation-i_accred0001-open'));
      await tester.pumpAndSettle();
      expect(tester.widget<Dialog>(key(d)).backgroundColor, Colors.white);
      final title = tester.renderObject<RenderParagraph>(find.descendant(of: key('$d-title'), matching: find.byType(RichText)));
      expect(title.text.style?.color, SiteDesign.defaults.colorOf('forestDark'));
    });
  });

  group('card backgrounds', () {
    testWidgets('automatic: the white card as before (border and radius kept); not stored', (tester) async {
      final block = _block();
      expect(((block.toMap()['items'] as List).first as Map).containsKey('background'), isFalse);
      await pump(tester, block);
      expect(cardColor(tester, 'i_accred0001'), Colors.white);
      final shape = tester.widget<Material>(key('public-accreditation-i_accred0001')).shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
      expect(shape.side.color, SiteDesign.defaults.colorOf('line'));
      expect(tester.widget<Material>(key('public-accreditation-i_accred0001')).elevation, 0, reason: 'no shadow');
    });

    testWidgets('transparent shows the section; white, every preset and a custom colour; each card its own', (tester) async {
      final values = ['transparent', 'token:surface', ...accreditationBackgrounds.keys, '#C0FFEE'];
      final items = [for (final (i, v) in values.indexed) _item('i_bg${i.toString().padLeft(8, '0')}', name: 'Body $i', background: v)];
      final block = _block(items: items, style: {'background': 'token:goldLight'});
      expect(BlockRegistry.blockProblems(block), isEmpty);
      expect([for (final i in block.toMap()['items'] as List) (i as Map)['background']], values, reason: 'stored per item');
      await pump(tester, block);
      for (final (i, v) in values.indexed) {
        final id = 'i_bg${i.toString().padLeft(8, '0')}';
        final expected = v == 'transparent' ? Colors.transparent : SiteDesign.defaults.resolve(v);
        expect(cardColor(tester, id), expected, reason: v);
      }
      // Transparent: nothing opaque inside the card covers the section.
      // (The plain badge of an item without images keeps its own small fill.)
      final inside = find.descendant(of: key('public-accreditation-i_bg00000000'), matching: find.byWidgetPredicate((w) => (w is Material && w.color != null && w.color!.a > 0) || (w is Ink && (w.decoration as BoxDecoration?)?.color != null)));
      expect(inside, findsNothing);
      // Changing one card leaves the others.
      final changed = block.withValue('items', [for (final (i, item) in block.items('items').indexed) i == 1 ? item.withValue('background', '#123456') : item]);
      expect([for (final i in changed.items('items')) i.string('background')], [values[0], '#123456', ...values.skip(2)]);
    });

    testWidgets('a dark colour gets light text (logo strip, where names show); a light one keeps the block’s text colours', (tester) async {
      await pump(tester, _block(display: 'logos', items: [_item('i_dark0001', title: 'Dark', background: '#1F2A24'), _item('i_lite0001', title: 'Light', background: 'token:sageLight')]));
      Color? colorOf(String text) => tester.renderObject<RenderParagraph>(find.descendant(of: find.text(text), matching: find.byType(RichText)).first).text.style?.color;
      expect(colorOf('Dark')!.withValues(alpha: 1), Colors.white, reason: 'light text');
      expect(colorOf('Light'), isNot(Colors.white));
    });

    testWidgets('logo strip: automatic and transparent have no fill (as before); a colour fills the 160 px slot', (tester) async {
      await pump(tester, _block(display: 'logos', items: [
        _item('i_auto0001', name: 'Auto', logo: 'm_logo1'),
        _item('i_none0001', name: 'None', logo: 'm_logo1', background: 'transparent'),
        _item('i_fill0001', name: 'Filled', logo: 'm_logo1', background: 'token:goldLight'),
      ]));
      Color? fill(String id) => (tester.widget<Ink>(find.descendant(of: key('public-accreditation-$id'), matching: find.byType(Ink))).decoration as BoxDecoration?)?.color;
      expect(fill('i_auto0001'), isNull);
      expect(fill('i_none0001'), isNull);
      expect(fill('i_fill0001'), SiteDesign.defaults.colorOf('goldLight'));
      for (final id in ['i_auto0001', 'i_none0001', 'i_fill0001']) {
        expect(card(tester, id).width, PublicAccreditationLogo.width, reason: id);
      }
    });

    test('invalid values are reported; a removed palette colour falls back to automatic', () {
      expect(BlockRegistry.blockProblems(_block(items: [_item('i_x', title: 'X', background: 'neon')])).single, contains('card background'));
      final item = _block(items: [_item('i_x', title: 'X', background: 'token:removedColour')]).items('items').single;
      expect(AccreditationView.of(item, _published, PublicLanguage.english).background, isNull);
    });

    testWidgets('every width: coloured and transparent cards and slots stay inside the screen', (tester) async {
      final items = [
        for (final (i, v) in ['transparent', 'token:goldLight', '#1F2A24', 'auto'].indexed) _item('i_w${i.toString().padLeft(8, '0')}', name: 'Synthetic body $i', title: 'Credential', logo: 'm_logo1', description: _long, background: v),
      ];
      for (final display in ['cards', 'logos']) {
        for (final at in [_desktop, _tablet, _phone, _narrow]) {
          await pump(tester, _block(display: display, items: items, style: {'background': 'token:sageLight'}), at: at);
          expect(tester.takeException(), isNull, reason: '$display at ${at.width}');
          for (var i = 0; i < 4; i++) {
            final r = card(tester, 'i_w${i.toString().padLeft(8, '0')}');
            expect(r.left >= 0 && r.right <= at.width, isTrue, reason: '$display $i at ${at.width}');
          }
        }
      }
    });
  });
}
