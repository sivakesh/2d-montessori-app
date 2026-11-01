// A block's own spacing, for every block type: padding (inside its surface)
// and margin (outside it), top, right, bottom and left, on desktop, tablets
// and phones (tablets inherit desktop; phones the tablet, then desktop).
// Stored in the block's style only when set; blocks without it are drawn
// exactly as before. The model, checks, saving, the page (the editor's canvas
// is the same code), nesting, narrow screens and the editor. Synthetic test
// data only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_spacing.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/block_spacing_box.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

const _desktop = Size(1400, 4000);
const _tablet = Size(820, 4000);
const _phone = Size(390, 4000);
const _narrow = Size(320, 4000);

WebsiteMedia _media(String id) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      width: 1200,
      height: 800,
      alt: LocalizedText(en: 'Photograph $id'),
      status: WebsiteMediaStatus.published,
      consentConfirmed: true,
    );

final _published = {for (final id in ['m_photo00001', 'm_photo00002', 'm_photo00003']) id: _media(id)};

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parse(raw) as StructuredBlock;

Map<String, dynamic> _text(String id, {String body = 'Some words about the school.', Map<String, dynamic> style = const {}}) =>
    {'id': id, 'type': 'text', 'v': 1, 'heading': {'en': 'Heading $id', 'ta': ''}, 'body': {'en': body, 'ta': ''}, if (style.isNotEmpty) 'style': style};

/// One block of (nearly) every kind that draws something, with [style].
Map<String, Map<String, dynamic>> _samples(Map<String, dynamic> style) {
  Map<String, dynamic> b(String id, String type, Map<String, dynamic> values) => {'id': id, 'type': type, 'v': 1, ...values, if (style.isNotEmpty) 'style': style};
  return {
    'text': _text('b_sample0text', style: style),
    'buttons': b('b_sample0btns', 'buttons', {
      'buttons': [
        {'id': 'i_button00001', 'label': {'en': 'Visit us'}, 'target': '/contact', 'variant': 'primary'},
      ],
    }),
    'image': b('b_sample0imge', 'image', {'mediaId': 'm_photo00001'}),
    'gallery': b('b_sample0gall', 'gallery', {
      'images': [for (final id in _published.keys) {'id': 'i_$id', 'mediaId': id}],
    }),
    'asymmetric_gallery': b('b_sample0asym', 'asymmetric_gallery', {
      'images': [for (final id in _published.keys) {'id': 'i_a$id', 'mediaId': id}],
    }),
    'cards': b('b_sample0crds', 'cards', {
      'cards': [
        {'id': 'i_card0000001', 'title': {'en': 'For families'}, 'icon': 'family'},
      ],
    }),
    'testimonials': b('b_sample0test', 'testimonials', {
      'testimonials': [
        {'id': 'i_testim00001', 'name': {'en': 'Jisha Joseph'}, 'quote': {'en': 'Wonderful.'}, 'rating': '5'},
      ],
    }),
    'features': b('b_sample0feat', 'features', {
      'items': [
        {'id': 'i_point000001', 'title': {'en': 'Independence'}},
      ],
    }),
    'cta': b('b_sample00cta', 'cta', {
      'heading': {'en': 'Come and see'},
      'body': {'en': 'Book a visit.'},
      'buttons': [
        {'id': 'i_button00002', 'label': {'en': 'Book'}, 'target': '/contact', 'variant': 'primary'},
      ],
    }),
    'notice': b('b_sample0note', 'notice', {'title': {'en': 'Closed on Monday'}}),
    'hero': b('b_sample0hero', 'hero', {'heading': {'en': 'A calm place to grow'}}),
    'html': b('b_sample0html', 'html', {'html': {'en': '<p>Plain <strong>words</strong>.</p>'}}),
    'divider': b('b_sample0divd', 'divider', const {}),
    'map': b('b_sample00map', 'map', {'address': {'en': '12 Synthetic Street, Testville 600001'}}),
    'embed': b('b_sample0embd', 'embed', {'source': {'en': 'https://youtu.be/dQw4w9WgXcQ'}, 'title': {'en': 'A morning in class'}}),
    'columns': b('b_sample0cols', 'columns', {
      'layout': '1:1',
      'columns': [
        {'id': 'c_sample0col1', 'blocks': [_text('b_sample0inn1')]},
        {'id': 'c_sample0col2', 'blocks': [_text('b_sample0inn2')]},
      ],
    }),
    'section': b('b_sample0sect', 'section', {
      'layout': '1',
      'columns': [
        {'id': 'c_sample0col3', 'blocks': [_text('b_sample0inn3')]},
      ],
    }),
  };
}

Map<String, dynamic> _sides(int top, int right, int bottom, int left) => {'top': top, 'right': right, 'bottom': bottom, 'left': left};

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pump(WidgetTester tester, List<WebsiteBlock> blocks, {Size at = _desktop, bool interactive = true, bool fullBleed = false}) async {
    tester.view.physicalSize = at;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteDesignScope(
              design: SiteDesign.defaults,
              child: WebsiteBlocksView(blocks: blocks, media: _published, language: PublicLanguage.english, interactive: interactive, fullBleed: fullBleed),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect block(WidgetTester tester, String id) => tester.getRect(key('public-block-$id'));
  Rect heading(WidgetTester tester, String id) => tester.getRect(find.text('Heading $id'));

  // ------------------------------------------------------------ model
  group('the model', () {
    test('inheritance: tablets from desktop, phones from the tablet then desktop, side by side', () {
      final stored = {
        'desktop': _sides(40, 30, 20, 10),
        'tablet': {'top': 24},
        'mobile': {'left': 0},
      };
      expect(BlockSpacing.sidesOn(stored, 'desktop'), const SpacingSides(top: 40, right: 30, bottom: 20, left: 10));
      expect(BlockSpacing.sidesOn(stored, 'tablet'), const SpacingSides(top: 24, right: 30, bottom: 20, left: 10));
      expect(BlockSpacing.sidesOn(stored, 'mobile'), const SpacingSides(top: 24, right: 30, bottom: 20, left: 0), reason: 'zero is a value');
      expect(BlockSpacing.inheritedFrom(stored, 'mobile', 'top'), 'tablet');
      expect(BlockSpacing.inheritedFrom(stored, 'mobile', 'right'), 'desktop');
      expect(BlockSpacing.inheritedFrom({'desktop': {'top': 1}}, 'desktop', 'top'), isNull, reason: 'desktop inherits nothing');
      expect(BlockSpacing.sidesOn(null, 'mobile').isAutomatic, isTrue);
      expect(BlockSpacing.sidesOn({'mobile': {'top': 8}}, 'desktop').isAutomatic, isTrue, reason: 'larger screens never take a smaller one’s');
    });

    test('setting and clearing: only what is set is kept; nothing set, nothing stored', () {
      var s = BlockSpacing.withValues(null, 'desktop', {'top': 16});
      expect(s, {'desktop': {'top': 16}});
      s = BlockSpacing.withValues(s, 'mobile', {for (final side in BlockSpacing.sides) side: 4});
      expect(s, {'desktop': {'top': 16}, 'mobile': _sides(4, 4, 4, 4)});
      s = BlockSpacing.withValues(s, 'desktop', {'top': null});
      expect(s, {'mobile': _sides(4, 4, 4, 4)});
      expect(BlockSpacing.withValues(s, 'mobile', {for (final side in BlockSpacing.sides) side: null}), isNull);
      expect(BlockSpacing.withValues({'unit': 'px', 'watch': {'top': 2}, 'desktop': {'top': 1}}, 'desktop', {'top': null}), {'unit': 'px', 'watch': {'top': 2}},
          reason: 'screens this version doesn’t know are kept');
    });

    test('checks: whole px from 0 to 200 per side; px the unit; unknown screens kept unused', () {
      List<String> p(Object? spacing, [String kind = BlockSpacing.padding]) => BlockRegistry.blockProblems(_parse(_text('b_check00001', style: {kind: spacing})));
      expect(p({'desktop': _sides(0, 200, 0, 0)}), isEmpty);
      expect(p({'desktop': {'top': 0}, 'tablet': {'left': 12}, 'mobile': {'right': 200}, 'unit': 'px'}), isEmpty);
      expect(p({'desktop': {'top': 201}}).single, contains('must be a whole number from 0 to 200 px'));
      expect(p({'mobile': {'left': -1}}, BlockSpacing.margin).single, contains('(phones, left)'));
      expect(p({'tablet': {'top': 1.5}}).single, contains('(tablets, top)'));
      expect(p({'unit': 'em'}).single, contains('“em” is not a spacing unit'));
      expect(p('24').single, contains('can’t be read'));
      expect(p({'watch': {'top': 999}}), isEmpty, reason: 'kept for a newer version');
    });

    test('saved and reloaded exactly; a block without it stores none; other settings and Tamil kept', () {
      final raw = _text('b_save000001', style: {
        'background': 'sage',
        BlockSpacing.padding: {'desktop': _sides(12, 0, 12, 0), 'mobile': {'top': 4}},
        BlockSpacing.margin: {'tablet': {'bottom': 40}},
        'futureStyle': 'kept',
      })
        ..['body'] = {'en': 'Words', 'ta': 'சொற்கள்'};
      final parsed = _parse(raw);
      expect(BlockRegistry.blockProblems(parsed), isEmpty);
      expect(parsed.toMap(), raw);
      expect(_parse(parsed.toMap()).text('body').textFor('ta'), 'சொற்கள்');
      for (final d in BlockRegistry.all) {
        expect(BlockRegistry.create(d).toMap().containsKey('style'), isFalse, reason: '${d.type}: nothing added to a new block');
      }
    });
  });

  // ------------------------------------------------------------ page
  group('on the page', () {
    testWidgets('no spacing: drawn exactly as before (nothing added to any block)', (tester) async {
      final blocks = [for (final raw in _samples(const {}).values) _parse(raw)];
      await pump(tester, blocks);
      expect(find.byType(FitPadding), findsNothing);
      // A block that sets nothing is laid out as one with only an unknown screen.
      await pump(tester, [_parse(_text('b_same000001'))]);
      final before = (block(tester, 'b_same000001'), heading(tester, 'b_same000001'));
      await pump(tester, [_parse(_text('b_same000001', style: {BlockSpacing.padding: {'watch': {'top': 50}}}))]);
      expect((block(tester, 'b_same000001'), heading(tester, 'b_same000001')), before);
    });

    testWidgets('padding: each side on its own, zero included, inside the block', (tester) async {
      await pump(tester, [_parse(_text('b_pad0000001'))]);
      final plain = heading(tester, 'b_pad0000001');
      final plainBlock = block(tester, 'b_pad0000001');
      await pump(tester, [_parse(_text('b_pad0000001', style: {BlockSpacing.padding: {'desktop': _sides(10, 20, 30, 40)}}))]);
      final h = heading(tester, 'b_pad0000001');
      final b = block(tester, 'b_pad0000001');
      expect(h.top - b.top, plain.top - plainBlock.top + 10);
      expect(h.left - b.left, plain.left - plainBlock.left + 40);
      expect(b.height, closeTo(plainBlock.height + 40, 0.01), reason: 'top and bottom');
      await pump(tester, [_parse(_text('b_pad0000001', style: {BlockSpacing.padding: {'desktop': _sides(0, 0, 0, 0)}}))]);
      expect(heading(tester, 'b_pad0000001').top - block(tester, 'b_pad0000001').top, plain.top - plainBlock.top);
    });

    testWidgets('with a background and border: padding inside the surface replaces its own; margin outside it', (tester) async {
      final style = {'background': 'sage', 'borderColor': '#20302A'};
      await pump(tester, [_parse(_text('b_surf000001', style: style))]);
      Container surface() => tester.widget<Container>(find.ancestor(of: find.text('Heading b_surf000001'), matching: find.byWidgetPredicate((w) => w is Container && w.decoration != null)).first);
      expect(surface().padding, const EdgeInsets.all(32), reason: 'unchanged without settings');

      await pump(tester, [
        _parse(_text('b_surf000001', style: {
          ...style,
          BlockSpacing.padding: {'desktop': {'top': 8, 'left': 60}},
          BlockSpacing.margin: {'desktop': _sides(16, 24, 16, 24)},
        })),
      ]);
      final surfaceRect = tester.getRect(find.byWidget(surface()));
      final outer = block(tester, 'b_surf000001');
      expect(surfaceRect.left - outer.left, 24, reason: 'margin outside the surface');
      expect(surfaceRect.top - outer.top, 16);
      expect(outer.right - surfaceRect.right, 24);
      final h = heading(tester, 'b_surf000001');
      expect(h.top - surfaceRect.top, closeTo(8 + 1, 0.01), reason: 'padding inside the border (1 px)');
      expect(h.left - surfaceRect.left, closeTo(60 + 1, 0.01));
      final decoration = surface().decoration! as BoxDecoration;
      expect(decoration.border, isNotNull, reason: 'its border and background kept');
      expect(decoration.color, isNotNull);
    });

    testWidgets('desktop, tablets and phones each use their own values, inheriting where unset', (tester) async {
      final raw = _text('b_screen0001', style: {
        BlockSpacing.padding: {'desktop': {'top': 40, 'left': 30}, 'mobile': {'top': 8}},
      });
      final offsets = <Size, (double, double)>{};
      for (final size in [_desktop, _tablet, _phone]) {
        await pump(tester, [_parse(_text('b_screen0001'))], at: size);
        final base = heading(tester, 'b_screen0001').topLeft - block(tester, 'b_screen0001').topLeft;
        await pump(tester, [_parse(raw)], at: size);
        final now = heading(tester, 'b_screen0001').topLeft - block(tester, 'b_screen0001').topLeft;
        offsets[size] = (now.dy - base.dy, now.dx - base.dx);
      }
      expect(offsets[_desktop], (40.0, 30.0));
      expect(offsets[_tablet], (40.0, 30.0), reason: 'from desktop');
      expect(offsets[_phone], (8.0, 30.0), reason: 'its own top; the left from desktop');
    });

    testWidgets('the editor’s canvas and the published page draw the same spacing', (tester) async {
      final raw = _text('b_canvas0001', style: {
        'background': 'gold',
        BlockSpacing.padding: {'desktop': _sides(12, 14, 16, 18)},
        BlockSpacing.margin: {'desktop': {'top': 20}},
      });
      final published = BlockRegistry.withoutHidden([BlockRegistry.parse(_parse(raw).toMap())]);
      await pump(tester, [_parse(raw)], interactive: false);
      final canvas = (block(tester, 'b_canvas0001'), heading(tester, 'b_canvas0001'));
      await pump(tester, published);
      expect((block(tester, 'b_canvas0001'), heading(tester, 'b_canvas0001')), canvas);
    });

    testWidgets('every kind of block with large spacing on narrow screens: no overflow, nothing off the page', (tester) async {
      final style = {
        'background': 'sage',
        BlockSpacing.padding: {'desktop': _sides(200, 200, 200, 200)},
        BlockSpacing.margin: {'desktop': _sides(200, 200, 200, 200)},
      };
      final moderate = {
        'background': 'sage',
        BlockSpacing.padding: {'desktop': _sides(48, 48, 48, 48)},
        BlockSpacing.margin: {'desktop': _sides(24, 24, 24, 24)},
      };
      for (final size in [_desktop, _tablet, _phone, _narrow]) {
        for (final entry in _samples(style).entries) {
          // The hero's side-by-side layout (desktop and tablets) needs about
          // 530 px, with or without spacing (it overflows in a narrower
          // column already); it gets moderate spacing there.
          final heroBeside = entry.key == 'hero' && size.width >= 700;
          final b = _parse(heroBeside ? _samples(moderate)['hero']! : entry.value);
          expect(BlockRegistry.blockProblems(b), isEmpty, reason: entry.key);
          await pump(tester, [b], at: size, fullBleed: true);
          expect(tester.takeException(), isNull, reason: '${entry.key} at $size');
          final r = block(tester, b.id);
          expect(r.left, greaterThanOrEqualTo(-0.01), reason: '${entry.key} at $size');
          expect(r.right, lessThanOrEqualTo(size.width + 0.01), reason: '${entry.key} at $size');
          for (final fit in tester.renderObjectList<RenderFitPadding>(find.byType(FitPadding))) {
            expect(fit.applied.horizontal, lessThanOrEqualTo(fit.constraints.maxWidth / 3 + 0.01), reason: '${entry.key} at $size');
          }
        }
      }
    });

    testWidgets('nested blocks: each block’s own spacing once; a section’s padding is its own', (tester) async {
      final section = _parse({
        'id': 'b_nest000001',
        'type': 'section',
        'v': 1,
        'layout': '1',
        'columns': [
          {
            'id': 'c_nest000001',
            'blocks': [
              _text('b_nestchild1', style: {BlockSpacing.padding: {'desktop': {'left': 20}}}),
              _text('b_nestchild2'),
            ],
          },
        ],
        'style': {BlockSpacing.padding: {'desktop': {'left': 50}}},
      });
      await pump(tester, [section]);
      expect(find.byType(FitPadding), findsNWidgets(2), reason: 'the section and its first block, no more');
      final one = heading(tester, 'b_nestchild1').left;
      final two = heading(tester, 'b_nestchild2').left;
      expect(one - two, 20, reason: 'the child’s padding once');
      final sectionRect = tester.getRect(key('public-section-b_nest000001'));
      expect(two - sectionRect.left, 50, reason: 'the section’s left padding (none at the sides of its own)');
      expect(heading(tester, 'b_nestchild1').top - sectionRect.top, 48, reason: 'its top is still the section’s own padding');
      await pump(tester, [_parse({...section.toMap(), 'style': {'padding': '24'}})]);
      expect(tester.widget<Container>(key('public-section-b_nest000001')).padding, const EdgeInsets.fromLTRB(0, 24, 0, 24), reason: 'section spacing unchanged');
    });

    testWidgets('buttons stay full size and tappable; images keep their shape; galleries and embeds still draw', (tester) async {
      final samples = _samples({BlockSpacing.padding: {'desktop': _sides(24, 40, 24, 40)}});
      await pump(tester, [_parse(_samples(const {})['buttons']!)]);
      final plainButton = tester.getSize(key('public-block-button-i_button00001'));
      await pump(tester, [_parse(samples['buttons']!)]);
      expect(tester.getSize(key('public-block-button-i_button00001')), plainButton);
      expect(tester.widget<FilledButton>(key('public-block-button-i_button00001')).onPressed, isNotNull, reason: 'still a button');
      expect(tester.hitTestOnBinding(tester.getCenter(key('public-block-button-i_button00001'))).path.any((e) => e.target is RenderObject), isTrue);

      await pump(tester, [_parse(samples['image']!)]);
      final image = tester.getSize(find.byType(AspectRatio).first);
      expect(image.width / image.height, closeTo(tester.widget<AspectRatio>(find.byType(AspectRatio).first).aspectRatio, 0.01), reason: 'not stretched or cropped differently');
      for (final type in ['gallery', 'asymmetric_gallery', 'embed', 'map', 'testimonials', 'cards']) {
        await pump(tester, [_parse(samples[type]!)]);
        expect(key('public-block-${samples[type]!['id']}'), findsOneWidget, reason: type);
        expect(find.byType(FitPadding), findsOneWidget, reason: '$type: its padding once');
        expect(tester.takeException(), isNull, reason: type);
      }
    });
  });

  // ------------------------------------------------------------ editor
  group('the editor', () {
    Future<StructuredBlock Function()> edit(WidgetTester tester, StructuredBlock start) async {
      var current = start;
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteStyleEditor(block: current, design: SiteDesign.defaults, onChanged: (b) => setState(() => current = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => current;
    }

    testWidgets('every registered block type has the same Padding and Margin groups', (tester) async {
      for (final d in BlockRegistry.all) {
        final b = BlockRegistry.create(d);
        await edit(tester, b);
        final prefix = 'website-block-${b.id}-style';
        expect(key('$prefix-${BlockSpacing.padding}-group'), findsOneWidget, reason: d.type);
        expect(key('$prefix-${BlockSpacing.margin}-group'), findsOneWidget, reason: d.type);
        expect(tester.widget<Text>(key('$prefix-${BlockSpacing.padding}-group-summary')).data, 'Automatic', reason: d.type);
      }
    });

    testWidgets('four sides, linked and unlinked, zero, Reset; each screen size; values shown', (tester) async {
      final block = await edit(tester, _parse(_text('b_edit000001')));
      const k = 'website-block-b_edit000001-style-blockPadding';
      await tester.tap(key('$k-group'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('$k-top-status')).data, 'Automatic');

      await tester.enterText(key('$k-top'), '24');
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': {'top': 24}});
      expect(tester.widget<Text>(key('$k-top-status')).data, 'Set');
      await tester.enterText(key('$k-left'), '0');
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': {'top': 24, 'left': 0}}, reason: 'zero is a value; the others untouched');
      await tester.enterText(key('$k-right'), '250');
      await tester.pump();
      expect(find.text('0–200'), findsOneWidget);
      expect(block().style[BlockSpacing.padding], {'desktop': {'top': 24, 'left': 0}}, reason: 'out of range not stored');
      await tester.enterText(key('$k-right'), '');
      await tester.pump();

      await tester.tap(key('$k-link'));
      await tester.pump();
      await tester.enterText(key('$k-bottom'), '16');
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': _sides(16, 16, 16, 16)}, reason: 'linked: all four');
      expect(tester.widget<Text>(key('$k-summary')).data, 'Desktop: all 16 px');
      await tester.tap(key('$k-link'));
      await tester.pump();
      await tester.enterText(key('$k-top'), '4');
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': _sides(4, 16, 16, 16)}, reason: 'unlinked: one side');

      await tester.tap(key('$k-screen-tablet'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('$k-top-status')).data, 'From desktop: 4');
      await tester.enterText(key('$k-top'), '2');
      await tester.pump();
      await tester.tap(key('$k-screen-mobile'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('$k-top-status')).data, 'From tablet: 2');
      expect(tester.widget<Text>(key('$k-left-status')).data, 'From desktop: 16');
      await tester.tap(key('$k-screen-tablet'));
      await tester.pumpAndSettle();
      await tester.tap(key('$k-top-reset'));
      await tester.pump();
      expect(block().style[BlockSpacing.padding], {'desktop': _sides(4, 16, 16, 16)}, reason: 'the tablet override removed');

      await tester.tap(key('$k-screen-desktop'));
      await tester.pumpAndSettle();
      await tester.tap(key('$k-reset'));
      await tester.pump();
      expect(block().style.containsKey(BlockSpacing.padding), isFalse, reason: 'Automatic again: nothing stored');
      expect(block().toMap().containsKey('style'), isFalse);
    });

    testWidgets('margin is its own group, beside padding', (tester) async {
      final block = await edit(tester, _parse(_text('b_edit000002')));
      const k = 'website-block-b_edit000002-style-blockMargin';
      await tester.ensureVisible(key('$k-group'));
      await tester.tap(key('$k-group'));
      await tester.pumpAndSettle();
      await tester.enterText(key('$k-bottom'), '48');
      await tester.pump();
      expect(block().style[BlockSpacing.margin], {'desktop': {'bottom': 48}});
      expect(block().style.containsKey(BlockSpacing.padding), isFalse);
      expect(tester.widget<Text>(key('$k-group-summary')).data, 'Desktop: bottom 48');
    });
  });
}
