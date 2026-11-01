// Button labels (Buttons, Call to action and Hero blocks share one button
// and one renderer): a label is never shortened. A long one is kept in
// full when typed, saved and validated, and on the page wraps onto more
// lines inside a button that grows, centred, without clipping, ellipsis
// or overflow, at desktop, tablet and phone widths, alone or beside other
// buttons; the editor's canvas draws the same buttons, inert; links still
// open on the website. Synthetic test data only.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

const _long = 'Interested in becoming a Montessori educator? Explore our Teacher Training programmes';
const _punctuated = 'Fees, forms & FAQs — 2026/27: “Apply now!” (see page 3)… ok?';
const _desktop = Size(1400, 2000);
const _tablet = Size(820, 2000);
const _phone = Size(390, 2000);
const _narrow = Size(320, 2000);

Map<String, dynamic> _button(String id, String label, {String target = 'https://example.test/training', String variant = 'primary'}) =>
    {'id': id, 'label': {'en': label, 'ta': ''}, 'target': target, 'variant': variant};

StructuredBlock _buttons(List<Map<String, dynamic>> buttons, {String align = 'start'}) =>
    BlockRegistry.parse({'id': 'b_buttons001', 'type': 'buttons', 'v': 1, 'align': align, 'buttons': buttons}) as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));

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
            child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, interactive: interactive, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  RenderParagraph paragraph(WidgetTester tester, String id) => tester.renderObject<RenderParagraph>(find.descendant(of: key('public-block-button-$id-label'), matching: find.byType(RichText)));

  /// What the label draws: its full text, its lines, and whether anything
  /// was cut off.
  ({String text, int lines, bool cut}) drawn(WidgetTester tester, String id) {
    final p = paragraph(tester, id);
    final line = p.getFullHeightForCaret(const TextPosition(offset: 0));
    return (text: p.text.toPlainText(), lines: (p.size.height / line).round(), cut: p.didExceedMaxLines);
  }

  /// The label fits inside its button, and the button inside the screen.
  void fits(WidgetTester tester, String id, Size at) {
    final button = tester.getRect(key('public-block-button-$id'));
    final label = tester.getRect(key('public-block-button-$id-label'));
    expect(button.left, greaterThanOrEqualTo(0), reason: '$id at ${at.width}');
    expect(button.right, lessThanOrEqualTo(at.width), reason: '$id at ${at.width}');
    expect(label.left, greaterThanOrEqualTo(button.left - 0.01), reason: '$id label at ${at.width}');
    expect(label.right, lessThanOrEqualTo(button.right + 0.01), reason: '$id label at ${at.width}');
    expect(label.top, greaterThanOrEqualTo(button.top - 0.01), reason: '$id label at ${at.width}');
    expect(label.bottom, lessThanOrEqualTo(button.bottom + 0.01), reason: '$id label at ${at.width}');
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

  group('the label is kept in full', () {
    test('a long label (a whole sentence) and punctuation are valid and saved exactly; the limit is 120 characters', () {
      for (final label in [_long, _punctuated, 'Book']) {
        final block = _buttons([_button('i_btn0000001', label)]);
        expect(BlockRegistry.blockProblems(block), isEmpty, reason: label);
        expect(((block.toMap()['buttons'] as List).single as Map)['label'], {'en': label, 'ta': ''});
      }
      expect(BlockRegistry.blockProblems(_buttons([_button('i_btn0000001', 'x' * 120)])), isEmpty);
      expect(BlockRegistry.blockProblems(_buttons([_button('i_btn0000001', 'x' * 121)])).single, contains('Button label must be 120 characters or fewer'));
      // The same button in a Call to action and a Hero.
      for (final type in ['cta', 'hero']) {
        final block = BlockRegistry.parse({
          'id': 'b_${type}_00001',
          'type': type,
          'v': 1,
          'heading': {'en': 'Teacher training'},
          'buttons': [_button('i_btn0000001', _long)],
        }) as StructuredBlock;
        expect(BlockRegistry.blockProblems(block), isEmpty, reason: type);
      }
    });

    testWidgets('typed in the editor: the whole label is kept, not cut at 40 characters', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      StructuredBlock? changed;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteBlockForm(block: _buttons([_button('i_btn0000001', 'Book')]), library: const [], generation: 0, onChanged: (b) => changed = b as StructuredBlock),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(key('website-block-b_buttons001-buttons-item-i_btn0000001-label-en-0'), _long);
      await tester.pumpAndSettle();
      expect(changed!.items('buttons').single.text('label').en, _long);
      expect(find.text('${_long.length}/120'), findsOneWidget, reason: 'the counter shows the new limit');
    });
  });

  group('drawn', () {
    testWidgets('a short label stays on one line, as before', (tester) async {
      await pump(tester, [_buttons([_button('i_btn0000001', 'Book a visit')])]);
      expect(drawn(tester, 'i_btn0000001'), (text: 'Book a visit', lines: 1, cut: false));
      expect(tester.getSize(key('public-block-button-i_btn0000001')).height, lessThan(64));
    });

    testWidgets('a long label: never cut; one line where it fits, wrapped on narrow screens with the button growing; no overflow', (tester) async {
      final heights = <double, double>{};
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pump(tester, [_buttons([_button('i_btn0000001', _long)])], at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        final d = drawn(tester, 'i_btn0000001');
        expect(d.text, _long, reason: 'at ${at.width}');
        expect(d.cut, isFalse, reason: 'at ${at.width}');
        if (at.width <= _phone.width) expect(d.lines, greaterThan(1), reason: 'wraps at ${at.width}');
        fits(tester, 'i_btn0000001', at);
        heights[at.width] = tester.getSize(key('public-block-button-i_btn0000001')).height;
      }
      expect(heights[_narrow.width], greaterThan(heights[_desktop.width]!), reason: 'the button grows to hold the wrapped lines');
    });

    testWidgets('punctuation is drawn exactly, wrapped where needed', (tester) async {
      for (final at in [_desktop, _narrow]) {
        await pump(tester, [_buttons([_button('i_btn0000001', _punctuated)])], at: at);
        expect(tester.takeException(), isNull);
        expect(drawn(tester, 'i_btn0000001').text, _punctuated);
        expect(drawn(tester, 'i_btn0000001').cut, isFalse);
        fits(tester, 'i_btn0000001', at);
      }
    });

    testWidgets('a wrapped label is centred in filled and outlined buttons; link buttons keep their arrow and start alignment', (tester) async {
      await pump(tester, [
        _buttons([
          _button('i_btn0000001', _long),
          _button('i_btn0000002', _long, variant: 'secondary'),
          _button('i_btn0000003', _long, variant: 'link'),
          _button('i_btn0000004', _long, variant: 'back', target: '/'),
        ]),
      ], at: _narrow);
      expect(tester.takeException(), isNull);
      for (final id in ['i_btn0000001', 'i_btn0000002', 'i_btn0000003', 'i_btn0000004']) {
        expect(drawn(tester, id).text, _long, reason: id);
        expect(drawn(tester, id).lines, greaterThan(1), reason: id);
        fits(tester, id, _narrow);
      }
      expect(paragraph(tester, 'i_btn0000001').textAlign, TextAlign.center);
      expect(paragraph(tester, 'i_btn0000002').textAlign, TextAlign.center);
      expect(paragraph(tester, 'i_btn0000003').textAlign, TextAlign.start);
      expect(find.descendant(of: key('public-block-button-i_btn0000003'), matching: find.byIcon(Icons.arrow_forward_rounded)), findsOneWidget);
      expect(find.descendant(of: key('public-block-button-i_btn0000004'), matching: find.byIcon(Icons.arrow_back_rounded)), findsOneWidget);
    });

    testWidgets('side by side: short buttons share a row; a long one takes its own row and wraps on phones; centred alignment kept', (tester) async {
      final block = _buttons([
        _button('i_btn0000001', 'Apply'),
        _button('i_btn0000002', 'Visit', variant: 'secondary'),
        _button('i_btn0000003', _long),
        _button('i_btn0000004', 'Contact us', variant: 'link'),
      ], align: 'center');
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pump(tester, [block], at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        final apply = tester.getRect(key('public-block-button-i_btn0000001'));
        final visit = tester.getRect(key('public-block-button-i_btn0000002'));
        expect(visit.top, apply.top, reason: 'short buttons side by side at ${at.width}');
        expect(visit.left, greaterThan(apply.right), reason: 'no overlap at ${at.width}');
        for (final id in ['i_btn0000001', 'i_btn0000002', 'i_btn0000003', 'i_btn0000004']) {
          expect(drawn(tester, id).cut, isFalse, reason: '$id at ${at.width}');
          fits(tester, id, at);
        }
        expect(drawn(tester, 'i_btn0000003').text, _long);
        expect(drawn(tester, 'i_btn0000001').lines, 1, reason: 'short labels stay on one line at ${at.width}');
      }
      // Centred: the long button's middle is the screen's middle.
      expect(tester.getRect(key('public-block-button-i_btn0000003')).center.dx, closeTo(_narrow.width / 2, 1));
    });

    testWidgets('in a Call to action and a Hero the same button wraps the same way', (tester) async {
      final blocks = [
        for (final type in ['cta', 'hero'])
          BlockRegistry.parse({
            'id': 'b_${type}_00001',
            'type': type,
            'v': 1,
            'heading': {'en': 'Teacher training'},
            'buttons': [_button('i_${type}_btn001', _long)],
          }),
      ];
      await pump(tester, blocks, at: _narrow);
      expect(tester.takeException(), isNull);
      for (final id in ['i_cta_btn001', 'i_hero_btn001']) {
        expect(drawn(tester, id), (text: _long, lines: drawn(tester, id).lines, cut: false));
        expect(drawn(tester, id).lines, greaterThan(1), reason: id);
        fits(tester, id, _narrow);
      }
    });
  });

  group('the editor’s canvas and the website', () {
    testWidgets('draw the same label, lines and size; only the website opens the link', (tester) async {
      final block = _buttons([_button('i_btn0000001', _long), _button('i_btn0000002', 'Book')]);
      final opened = launches();
      final published = <String, (({String text, int lines, bool cut}), Size)>{};
      for (final interactive in [true, false]) {
        await pump(tester, [block], at: _phone, interactive: interactive);
        for (final id in ['i_btn0000001', 'i_btn0000002']) {
          final now = (drawn(tester, id), tester.getSize(key('public-block-button-$id')));
          if (interactive) {
            published[id] = now;
          } else {
            expect(now, published[id], reason: '$id: the canvas matches the website');
          }
        }
        await tester.tap(key('public-block-button-i_btn0000001'));
        await tester.pumpAndSettle();
        // Opened once, by the website; tapping on the canvas adds nothing.
        expect(opened, ['https://example.test/training']);
        final button = tester.widget<ButtonStyleButton>(key('public-block-button-i_btn0000001'));
        expect(button.onPressed == null, !interactive);
      }
    });

    testWidgets('a wrapped button is still one button for screen readers, named by its full label', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, [_buttons([_button('i_btn0000001', _long)])], at: _narrow);
      expect(tester.getSemantics(key('public-block-button-i_btn0000001')), isSemantics(isButton: true, label: _long));
      semantics.dispose();
    });
  });
}
