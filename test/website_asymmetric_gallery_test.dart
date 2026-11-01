// The Asymmetric gallery block: 1–12 photographs in an editorial
// composition, every part of it a setting (arrangement, feature image and its
// position, proportions, shapes, gaps, the images shown and their order)
// separately for desktop, tablets and phones; image appearance for the block
// and per image; captions; links and the larger view. The layout engine,
// settings, checks, saving, the page (the editor's canvas is the same code),
// accessibility and the editor. The Photo gallery is untouched (its own tests
// still pass). Synthetic test data only.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart' show WebsiteMediaThumb;
import 'package:montessori_app/modules/public_website/content/blocks/asymmetric_gallery.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/ui/public_gallery_page.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/public_website_image.dart';

const _desktop = Size(1400, 3000);
const _tablet = Size(820, 3000);
const _phone = Size(390, 3000);
const _narrow = Size(320, 3000);

WebsiteMedia _media(String id, {String alt = '', int width = 1200, int height = 800, bool published = true}) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      width: width,
      height: height,
      alt: LocalizedText(en: alt),
      status: published ? WebsiteMediaStatus.published : WebsiteMediaStatus.draft,
      consentConfirmed: true,
    );

// Twelve photographs of different shapes, all described.
final _library = [
  for (var i = 1; i <= 12; i++) _media('m_photo${i.toString().padLeft(2, '0')}', alt: 'Photograph $i', width: i.isEven ? 800 : 1200, height: i % 3 == 0 ? 1200 : 800),
  _media('m_noalt01'),
  _media('m_draft01', alt: 'Not yet', published: false),
];
final _published = {for (final m in _library) if (m.isPublished) m.id: m};

String _mid(int i) => 'm_photo${i.toString().padLeft(2, '0')}';
String _iid(int i) => 'i_asym${i.toString().padLeft(6, '0')}';

Map<String, dynamic> _image(int i, [Map<String, dynamic> extra = const {}]) => {'id': _iid(i), 'mediaId': _mid(i), ...extra};

Map<String, dynamic> _raw({int count = 4, List<Map<String, dynamic>>? images, Map<String, dynamic> extra = const {}}) => {
      'id': 'b_asym000001',
      'type': 'asymmetric_gallery',
      'v': 1,
      'images': images ?? [for (var i = 1; i <= count; i++) _image(i)],
      ...extra,
    };

StructuredBlock _block({int count = 4, List<Map<String, dynamic>>? images, Map<String, dynamic> extra = const {}}) =>
    BlockRegistry.parse(_raw(count: count, images: images, extra: extra)) as StructuredBlock;

List<AsymmetricTile> _tiles(int n, {int feature = 0}) => [
      for (var i = 0; i < n; i++) AsymmetricTile(id: 't$i', naturalRatio: i.isEven ? 1.5 : 0.75, feature: i == feature),
    ];

AsymmetricSettings _settings(String arrangement, {String position = 'left', String screen = 'desktop', int columns = 4, double gap = 20, double fraction = 0.6, String supporting = 'auto'}) =>
    AsymmetricSettings(
      screen: screen,
      arrangement: arrangement,
      position: position,
      featureFraction: fraction,
      featureHeight: null,
      featureRatio: null,
      supportingRatio: null,
      supportingLayout: supporting,
      columns: columns,
      gapX: gap,
      gapY: gap,
    );

/// Every rectangle inside 0..[width], not overlapping, sized; the height
/// is the lowest edge.
void _expectSound(AsymmetricLayoutResult r, double width, int count, String why) {
  expect(r.placements.length, count, reason: why);
  for (final p in r.placements) {
    expect(p.rect.left, greaterThanOrEqualTo(-0.01), reason: '$why ${p.id} $p');
    expect(p.rect.right, lessThanOrEqualTo(width + 0.01), reason: '$why ${p.id} $p');
    expect(p.rect.top, greaterThanOrEqualTo(-0.01), reason: '$why ${p.id} $p');
    expect(p.rect.width, greaterThan(0), reason: '$why ${p.id} $p');
    expect(p.rect.height, greaterThan(0), reason: '$why ${p.id} $p');
    expect(p.rect.bottom, lessThanOrEqualTo(r.height + 0.01), reason: '$why ${p.id} $p');
  }
  for (final a in r.placements) {
    for (final b in r.placements) {
      if (identical(a, b)) continue;
      final overlap = a.rect.intersect(b.rect);
      expect(overlap.width <= 0.01 || overlap.height <= 0.01, isTrue, reason: '$why: ${a.id} and ${b.id} overlap ($a, $b)');
    }
  }
}

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pump(WidgetTester tester, WebsiteBlock block, {Size at = _desktop, bool interactive = true, bool reduceMotion = false}) async {
    tester.view.physicalSize = at;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
            child: Scaffold(
              body: SingleChildScrollView(
                child: WebsiteDesignScope(
                  design: SiteDesign.defaults,
                  child: WebsiteBlocksView(blocks: [block], media: _published, language: PublicLanguage.english, interactive: interactive, fullBleed: true),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect tile(WidgetTester tester, int i) => tester.getRect(key('public-asymmetric-tile-${_iid(i)}'));

  // ------------------------------------------------------------ engine
  group('layout engine', () {
    test('every arrangement and feature position, 1–12 images, every width: within the width, no overlaps', () {
      for (final arrangement in AsymmetricGallery.arrangements) {
        for (final position in AsymmetricGallery.positions) {
          for (final (screen, width, columns) in [('desktop', 1160.0, 4), ('tablet', 740.0, 3), ('mobile', 350.0, 2), ('mobile', 280.0, 2)]) {
            for (var n = 1; n <= 12; n++) {
              final s = _settings(arrangement, position: position, screen: screen, columns: columns, gap: screen == 'mobile' ? 12 : 20);
              final r = AsymmetricLayout.compute(_tiles(n, feature: n > 2 ? 2 : 0), s, width);
              _expectSound(r, width, n, '$arrangement/$position/$screen@$width n=$n');
            }
          }
        }
      }
    });

    test('feature beside: its share of the width, on its side; the others the rest; gaps exact', () {
      for (final fraction in [0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.33]) {
        final r = AsymmetricLayout.compute(_tiles(3), _settings('feature', fraction: fraction, supporting: 'column'), 1000);
        final f = r.rectOf('t0');
        expect(f.left, 0);
        expect(f.width, closeTo(((1000 - 20) * fraction).floorToDouble(), 0.01), reason: '$fraction');
        expect(r.rectOf('t1').left, closeTo(f.right + 20, 0.01));
        expect(r.rectOf('t1').right, closeTo(1000, 0.01));
        expect(r.rectOf('t2').top, closeTo(r.rectOf('t1').bottom + 20, 0.01), reason: 'one above another, 20 px apart');
        expect(r.rectOf('t2').bottom, closeTo(f.bottom, 0.01), reason: 'the same height as the feature');
      }
      final right = AsymmetricLayout.compute(_tiles(3), _settings('editorial', position: 'right'), 1000);
      expect(right.rectOf('t0').right, closeTo(1000, 0.01));
      expect(right.rectOf('t1').left, 0);
    });

    test('feature on top or bottom: the full width, the others in a row', () {
      final top = AsymmetricLayout.compute(_tiles(4), _settings('feature', position: 'top'), 900);
      expect(top.rectOf('t0'), predicate<Rect>((r) => r.left == 0 && r.top == 0 && r.width == 900));
      for (final id in ['t1', 't2', 't3']) {
        expect(top.rectOf(id).top, closeTo(top.rectOf('t0').bottom + 20, 0.01));
      }
      final bottom = AsymmetricLayout.compute(_tiles(4), _settings('feature', position: 'bottom'), 900);
      expect(bottom.rectOf('t0').bottom, closeTo(bottom.height, 0.01));
      expect(bottom.rectOf('t1').top, 0);
    });

    test('the feature image is whichever is chosen; supporting weights set relative sizes', () {
      final r = AsymmetricLayout.compute(_tiles(4, feature: 3), _settings('feature', supporting: 'column'), 1000);
      expect(r.rectOf('t3').left, 0, reason: 'the chosen feature, not the first');
      expect(r.rectOf('t3').width, greaterThan(r.rectOf('t0').width));
      final weighted = [
        const AsymmetricTile(id: 'f', naturalRatio: 1, feature: true),
        const AsymmetricTile(id: 'a', naturalRatio: 1, weight: 2),
        const AsymmetricTile(id: 'b', naturalRatio: 1),
      ];
      final w = AsymmetricLayout.compute(weighted, _settings('feature', supporting: 'column'), 1000);
      expect(w.rectOf('a').height, closeTo((w.rectOf('a').height + w.rectOf('b').height) * 2 / 3, 1.5), reason: 'twice the other');
    });

    test('staggered keeps each image’s shape; every other column starts lower', () {
      final tiles = _tiles(6, feature: -1);
      final r = AsymmetricLayout.compute(tiles, _settings('staggered', columns: 3), 1000);
      for (final t in tiles) {
        final rect = r.rectOf(t.id);
        expect(rect.width / rect.height, closeTo(t.naturalRatio, 0.02), reason: t.id);
      }
      final firstInColumn2 = r.placements.where((p) => p.rect.left > 300 && p.rect.left < 400).map((p) => p.rect.top).reduce((a, b) => a < b ? a : b);
      expect(firstInColumn2, greaterThan(0), reason: 'staggered');
    });

    test('mosaic and custom: grid cells; custom spans honoured and clamped to the columns', () {
      final mosaic = AsymmetricLayout.compute(_tiles(5), _settings('mosaic', columns: 4), 1000);
      final cell = (1000 - 3 * 20) / 4;
      expect(mosaic.rectOf('t0').width, closeTo(2 * cell + 20, 1), reason: 'the feature two cells wide');
      expect(mosaic.rectOf('t1').width, closeTo(cell, 1));
      final custom = AsymmetricLayout.compute([
        const AsymmetricTile(id: 'a', naturalRatio: 1, colSpan: 3, rowSpan: 2),
        const AsymmetricTile(id: 'b', naturalRatio: 1, colSpan: 1, rowSpan: 1),
        const AsymmetricTile(id: 'c', naturalRatio: 1, colSpan: 9, rowSpan: 1),
      ], _settings('custom', columns: 4), 1000);
      expect(custom.rectOf('a').width, closeTo(3 * cell + 40, 1));
      expect(custom.rectOf('a').height, closeTo(2 * cell.floorToDouble() + 20, 1));
      expect(custom.rectOf('b').left, closeTo(3 * (cell + 20), 1), reason: 'packed beside it');
      expect(custom.rectOf('c').width, closeTo(1000, 1), reason: 'at most the columns');
    });

    test('custom shapes: W:H parsed and limited', () {
      expect(AsymmetricGallery.parseRatio('7:5'), closeTo(1.4, 1e-9));
      expect(AsymmetricGallery.parseRatio(' 16 : 9 '), closeTo(16 / 9, 1e-9));
      expect(AsymmetricGallery.parseRatio('1.5:1'), 1.5);
      for (final bad in ['', '5', '0:1', '1:0', '5:1', '1:5', 'a:b', '-1:2', '7;5']) {
        expect(AsymmetricGallery.parseRatio(bad), isNull, reason: bad);
      }
      expect(AsymmetricGallery.ratioOf('auto', ''), isNull);
      expect(AsymmetricGallery.ratioOf('4:5', ''), 0.8);
    });
  });

  // ---------------------------------------------------------- settings
  group('screen sizes', () {
    test('Automatic: editorial on desktop, the same on tablets, feature on top and two by two on phones', () {
      final b = _block();
      final d = AsymmetricGallery.settings(b, 'desktop');
      expect([d.arrangement, d.position, d.featureFraction, d.gapX], ['editorial', 'left', 0.6, 20]);
      final t = AsymmetricGallery.settings(b, 'tablet');
      expect([t.arrangement, t.position, t.gapX], ['editorial', 'left', 16]);
      final m = AsymmetricGallery.settings(b, 'mobile');
      expect([m.arrangement, m.position, m.supportingLayout, m.gapX, m.columns], ['feature', 'top', 'grid', 12, 2]);
    });

    test('each screen size set on its own (not copied from desktop)', () {
      final b = _block(extra: {
        'arrangement': 'feature',
        'featurePosition': 'right',
        'featureWidth': '45',
        'tabletArrangement': 'mosaic',
        'tabletColumns': '3',
        'mobileArrangement': 'staggered',
        'mobileFeaturePosition': 'bottom',
        'mobileGapX': 4,
        'mobileGapY': 30,
        'featureAspect': '16:9',
        'mobileFeatureAspect': 'custom',
        'mobileFeatureAspectCustom': {'en': '3:4'},
      });
      final d = AsymmetricGallery.settings(b, 'desktop');
      expect([d.arrangement, d.position, d.featureFraction, d.featureRatio], ['feature', 'right', 0.45, closeTo(16 / 9, 1e-9)]);
      final t = AsymmetricGallery.settings(b, 'tablet');
      expect([t.arrangement, t.columns, t.position, t.featureFraction], ['mosaic', 3, 'right', 0.45], reason: 'what isn’t set follows desktop');
      final m = AsymmetricGallery.settings(b, 'mobile');
      expect([m.arrangement, m.position, m.gapX, m.gapY, m.featureRatio], ['staggered', 'bottom', 4, 30, 0.75]);
    });

    test('order and visibility per screen size; spans inherited from larger screens', () {
      final b = _block(images: [
        _image(1, {'mobileOrder': 3}),
        _image(2, {'hideMobile': true}),
        _image(3, {'order': 1, 'tabletOrder': 4}),
        _image(4, {'visible': false}),
        _image(5, {'colSpan': '3', 'mobileColSpan': '1'}),
      ]);
      List<String> ids(String screen) => [
            for (final (i, item) in b.items('images').indexed)
              if (AsymmetricGallery.shownOn(item, screen)) (item.id, AsymmetricGallery.orderOf(item, screen, i)),
          ].map((e) => e).toList().sortedByOrder();
      expect(ids('desktop'), [_iid(1), _iid(3), _iid(2), _iid(5)]);
      expect(ids('mobile'), [_iid(3), _iid(1), _iid(5)]);
      final five = b.items('images')[4];
      expect([AsymmetricGallery.spanOf(five, 'desktop', 'colSpan'), AsymmetricGallery.spanOf(five, 'tablet', 'colSpan'), AsymmetricGallery.spanOf(five, 'mobile', 'colSpan')], [3, 3, 1]);
    });
  });

  // ---------------------------------------------------- checks, saving
  group('checks and saving', () {
    test('1 to 12 images; each must have an image', () {
      expect(BlockRegistry.blockProblems(_block(count: 1)), isEmpty);
      expect(BlockRegistry.blockProblems(_block(count: 12)), isEmpty);
      expect(BlockRegistry.blockProblems(_block(images: [])), ['add at least 1 image']);
      expect(BlockRegistry.blockProblems(_block(images: [for (var i = 1; i <= 13; i++) _image(i % 12 + 1, {'id': _iid(i)})])), ['at most 12 images']);
      expect(BlockRegistry.blockProblems(_block(images: [{'id': _iid(1), 'mediaId': ''}])), ['Image 1: choose an image']);
    });

    test('invalid settings are reported; Automatic and in-range values are not', () {
      List<String> p(Map<String, dynamic> extra, [List<Map<String, dynamic>>? images]) => BlockRegistry.blockProblems(_block(extra: extra, images: images));
      expect(p({}), isEmpty);
      expect(p({'arrangement': 'spiral'}).single, contains('“spiral” is not a arrangement option'));
      expect(p({'featureWidth': 'custom'}), ['Layout on desktop: enter the custom feature width']);
      expect(p({'featureWidth': 'custom', 'featureWidthCustom': 70}), isEmpty);
      expect(p({'featureWidth': 'custom', 'featureWidthCustom': 95}).single, contains('custom feature width must be from 25 to 80 %'));
      expect(p({'tabletFeatureHeight': 50}).single, contains('feature image height must be from 120 to 1000 px'));
      expect(p({'mobileGapY': 200}).single, contains('must be from 0 to 96 px'));
      expect(p({'gap': 12.5}).single, contains('“gap” has a value this app can’t read'));
      expect(p({'supportingAspect': 'custom', 'supportingAspectCustom': {'en': '9:1'}}), ['Layout on desktop, supporting image shape: enter a shape as width:height, such as 7:5 (from 4:1 to 1:4)']);
      expect(p({'mobileFeatureAspect': 'custom', 'mobileFeatureAspectCustom': {'en': '2:3'}}), isEmpty);
      expect(p({'overlayColor': 'pink'}).single, contains('“pink” is not a overlay colour option'));
      expect(p({'overlayColor': '#20302A', 'overlayOpacity': 40, 'radius': 0, 'maxWidth': 900}), isEmpty);
      expect(p({}, [_image(1, {'feature': true}), _image(2, {'feature': true})]), ['only one image can be the feature image']);
      expect(p({}, [_image(1, {'action': 'link'})]), ['Image 1: enter the link to follow, or choose another click action']);
      expect(p({}, [_image(1, {'target': 'javascript:alert(1)'})]).single, startsWith('Image 1: '));
      expect(p({}, [_image(1, {'aspect': 'custom', 'aspectCustom': {'en': 'wide'}})]).single, contains('Image 1: enter a shape'));
      expect(p({}, [_image(1, {'focalX': 101})]).single, contains('Image 1: focus across'));
    });

    test('a new block stores only what is set; settings, order and per-image settings survive saving and reloading; Tamil kept', () {
      final fresh = BlockRegistry.create(BlockRegistry.asymmetricGallery);
      final stored = fresh.toMap();
      expect(stored.keys.toSet(), {'id', 'type', 'v', 'images'}, reason: 'nothing else until set');
      expect(((stored['images'] as List).single as Map).keys.toSet(), {'id', 'mediaId'});

      final raw = _raw(images: [
        _image(3, {'feature': true, 'alt': {'en': 'Children in the garden', 'ta': 'தோட்டத்தில் குழந்தைகள்'}, 'focalX': 30, 'focalY': 70, 'mobileOrder': 2, 'hideTablet': true}),
        _image(1, {'caption': {'en': 'Painting', 'ta': 'ஓவியம்'}, 'captionPlacement': 'overlay', 'target': 'https://example.test/art', 'newTab': false}),
        _image(2, {'aspect': 'custom', 'aspectCustom': {'en': '7:5', 'ta': ''}, 'colSpan': '3'}),
      ], extra: {
        'heading': {'en': 'Our days', 'ta': 'எங்கள் நாட்கள்'},
        'arrangement': 'custom',
        'mobileArrangement': 'mosaic',
        'gap': 24,
        'lightbox': false,
        'captionColor': 'token:forest',
        'futureSetting': {'kept': true},
      });
      final block = BlockRegistry.parse(raw) as StructuredBlock;
      expect(BlockRegistry.blockProblems(block), isEmpty);
      expect(block.toMap(), raw, reason: 'written back exactly as stored');
      final again = BlockRegistry.parse(block.toMap()) as StructuredBlock;
      expect([for (final i in again.items('images')) i.id], [_iid(3), _iid(1), _iid(2)], reason: 'order and ids kept');
      expect(again.items('images').first.text('alt').textFor('ta'), 'தோட்டத்தில் குழந்தைகள்');
      expect(again.text('heading').textFor('ta'), 'எங்கள் நாட்கள்');
      expect(BlockRegistry.referencedMedia([again]), [_mid(3), _mid(1), _mid(2)], reason: 'publishing checks every image');
      expect(BlockRegistry.all, contains(BlockRegistry.asymmetricGallery), reason: 'offered in Add block');
      expect(BlockRegistry.nestable, contains(BlockRegistry.asymmetricGallery));
      expect(BlockRegistry.definition('gallery')!.label, 'Photo gallery', reason: 'the Photo gallery is its own block, unchanged');
    });
  });

  // ------------------------------------------------------------ page
  group('on the page', () {
    testWidgets('every arrangement at every screen size, 1 and 12 images: drawn as computed, no overflow', (tester) async {
      for (final arrangement in AsymmetricGallery.arrangements) {
        for (final count in [1, 3, 12]) {
          final block = _block(count: count, extra: {'arrangement': arrangement, 'tabletArrangement': arrangement, 'mobileArrangement': arrangement});
          for (final at in [_desktop, _tablet, _phone, _narrow]) {
            await pump(tester, block, at: at);
            final why = '$arrangement n=$count at ${at.width}';
            expect(tester.takeException(), isNull, reason: why);
            final box = tester.getRect(key('public-asymmetric-b_asym000001'));
            expect(box.left, greaterThanOrEqualTo(0), reason: why);
            expect(box.right, lessThanOrEqualTo(at.width), reason: why);
            for (var i = 1; i <= count; i++) {
              final r = tile(tester, i);
              expect(r.left, greaterThanOrEqualTo(box.left - 0.01), reason: '$why image $i');
              expect(r.right, lessThanOrEqualTo(box.right + 0.01), reason: '$why image $i');
              expect(r.bottom, lessThanOrEqualTo(box.bottom + 0.01), reason: '$why image $i');
            }
          }
        }
      }
    });

    testWidgets('the feature image chosen and placed; its proportion and height set', (tester) async {
      await pump(tester, _block(images: [_image(1), _image(2), _image(3, {'feature': true})], extra: {'arrangement': 'feature', 'featurePosition': 'right', 'featureWidth': '65', 'featureHeight': 500}));
      final box = tester.getRect(key('public-asymmetric-b_asym000001'));
      final f = tile(tester, 3);
      expect(f.right, closeTo(box.right, 0.01));
      expect(f.width, closeTo(((box.width - 20) * 0.65).floorToDouble(), 0.01));
      expect(f.height, closeTo(500, 0.01));
      expect(tile(tester, 1).right, lessThan(f.left));
    });

    testWidgets('desktop, tablet and phone each use their own settings; hidden images aren’t built or loaded', (tester) async {
      final block = _block(images: [
        _image(1, {'hideMobile': true}),
        _image(2, {'mobileOrder': 1}),
        _image(3, {'hideDesktop': true}),
        _image(4),
      ], extra: {'mobileArrangement': 'feature', 'mobileFeaturePosition': 'top'});
      await pump(tester, block);
      expect(key('public-asymmetric-tile-${_iid(3)}'), findsNothing);
      expect(find.byType(PublicWebsiteImage), findsNWidgets(3));
      await pump(tester, block, at: _tablet);
      expect(find.byType(PublicWebsiteImage), findsNWidgets(4));
      await pump(tester, block, at: _phone);
      expect(key('public-asymmetric-tile-${_iid(1)}'), findsNothing);
      expect(find.byType(PublicWebsiteImage), findsNWidgets(3));
      final box = tester.getRect(key('public-asymmetric-b_asym000001'));
      expect(tile(tester, 2).top, box.top, reason: 'first on phones: the feature, on top');
      expect(tile(tester, 2).width, closeTo(box.width, 0.01));
    });

    testWidgets('per-image shape, fit and focal point; block defaults; overlay, border, corners', (tester) async {
      await pump(tester, _block(images: [
        _image(1, {'focalX': 20, 'focalY': 80, 'fit': 'contain', 'radius': 4}),
        _image(2, {'aspect': '1:1'}),
      ], extra: {'arrangement': 'staggered', 'columns': '2', 'radius': 24, 'overlayColor': '#000000', 'overlayOpacity': 50, 'borderWidth': '2'}));
      final images = tester.widgetList<PublicWebsiteImage>(find.byType(PublicWebsiteImage)).toList();
      expect(images[0].fit, BoxFit.contain);
      expect([images[0].alignment!.x, images[0].alignment!.y], [closeTo(-0.6, 1e-9), closeTo(0.6, 1e-9)]);
      expect(images[1].fit, BoxFit.cover);
      expect(images[1].alignment, isNull, reason: 'the Media library’s focal point');
      final two = tile(tester, 2);
      expect(two.width / two.height, closeTo(1, 0.02), reason: 'square');
      BorderRadiusGeometry corners(int i) => tester.widget<ClipRRect>(find.descendant(of: key('public-asymmetric-tile-${_iid(i)}'), matching: find.byType(ClipRRect)).first).borderRadius;
      expect(corners(1), BorderRadius.circular(4), reason: 'its own');
      expect(corners(2), BorderRadius.circular(24), reason: 'the block’s');
      expect(find.descendant(of: key('public-asymmetric-tile-${_iid(2)}'), matching: find.byWidgetPredicate((w) => w is ColoredBox && (w.color.a - 0.5).abs() < 0.01 && w.color.r == 0)), findsOneWidget, reason: 'black at 50%');
    });

    testWidgets('captions below or over the image; heading and description optional; photography only', (tester) async {
      await pump(tester, _block(images: [
        _image(1, {'caption': {'en': 'Below it'}}),
        _image(2, {'caption': {'en': 'Over it'}, 'captionPlacement': 'overlay'}),
        _image(3, {'caption': {'en': 'Not shown'}, 'captionPlacement': 'none'}),
      ], extra: {'heading': {'en': 'A day at school'}, 'description': {'en': 'Moments from our classrooms.'}, 'arrangement': 'staggered', 'columns': '3', 'captionAlign': 'center', 'captionSize': 18}));
      expect(find.text('A day at school'), findsOneWidget);
      expect(find.text('Moments from our classrooms.'), findsOneWidget);
      final below = tester.getRect(key('public-asymmetric-tile-${_iid(1)}-caption'));
      expect(below.top, greaterThanOrEqualTo(tester.getRect(key('public-asymmetric-tile-${_iid(1)}-image')).bottom));
      final over = tester.getRect(key('public-asymmetric-tile-${_iid(2)}-caption'));
      expect(over.bottom, closeTo(tester.getRect(key('public-asymmetric-tile-${_iid(2)}-image')).bottom, 0.01));
      expect(find.text('Not shown'), findsNothing);
      expect(tester.widget<Text>(find.text('Below it')).style!.fontSize, 18);
      expect(tester.widget<Text>(find.text('Below it')).textAlign, TextAlign.center);

      // Photography only: no heading, description or captions.
      await pump(tester, _block(count: 5, extra: {'showCaptions': false}));
      expect(find.byType(Text), findsNothing);
      expect(tester.getRect(key('public-asymmetric-b_asym000001')).top, closeTo(tester.getRect(key('public-block-b_asym000001')).top, 0.01), reason: 'the images first');
    });

    testWidgets('a click does one thing: the link, else the larger view; the canvas does nothing', (tester) async {
      final opened = <Map>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') opened.add(call.arguments as Map);
        return call.method == 'canLaunch' || call.method == 'launch';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final block = _block(images: [
        _image(1, {'target': 'https://example.test/visit'}),
        _image(2),
        _image(3, {'action': 'none'}),
        _image(4, {'target': 'https://example.test/here', 'action': 'lightbox'}),
      ], extra: {'arrangement': 'mosaic'});
      await pump(tester, block);
      await tester.tap(key('public-asymmetric-tile-${_iid(1)}'));
      await tester.pumpAndSettle();
      expect(opened.map((a) => a['url']), ['https://example.test/visit']);
      expect(find.byType(PublicGalleryLightbox), findsNothing, reason: 'not both');

      await tester.tap(key('public-asymmetric-tile-${_iid(2)}'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicGalleryLightbox), findsOneWidget);
      expect(find.text('1 of 2'), findsOneWidget, reason: 'the images that open it, in order');
      await tester.tap(key('public-gallery-lightbox-close'));
      await tester.pumpAndSettle();
      await tester.tap(key('public-asymmetric-tile-${_iid(3)}'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicGalleryLightbox), findsNothing);
      expect(opened, hasLength(1));

      // Larger view turned off for the block: the link-less image does nothing.
      await pump(tester, _block(count: 2, extra: {'lightbox': false}));
      await tester.tap(key('public-asymmetric-tile-${_iid(1)}'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicGalleryLightbox), findsNothing);

      // In this tab when asked.
      await pump(tester, _block(images: [_image(1, {'target': 'https://example.test/same', 'newTab': false})]));
      await tester.tap(key('public-asymmetric-tile-${_iid(1)}'));
      await tester.pumpAndSettle();
      expect(opened.last['url'], 'https://example.test/same');

      // The editor's canvas: the same composition, nothing opens.
      await pump(tester, block);
      final published = [for (var i = 1; i <= 4; i++) tile(tester, i)];
      await pump(tester, block, interactive: false);
      expect([for (var i = 1; i <= 4; i++) tile(tester, i)], published);
      await tester.tap(key('public-asymmetric-tile-${_iid(2)}'));
      await tester.pumpAndSettle();
      expect(find.byType(PublicGalleryLightbox), findsNothing);
      expect(opened, hasLength(2));
    });

    testWidgets('screen readers: alt text (own, else the library’s), decorative images skipped, actions named; keyboard focus', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _block(images: [
        _image(1, {'alt': {'en': 'Two children reading'}}),
        _image(2),
        {'id': _iid(3), 'mediaId': 'm_noalt01', 'decorative': true, 'action': 'none'},
        {'id': _iid(4), 'mediaId': 'm_noalt01', 'decorative': true},
      ], extra: {'arrangement': 'mosaic'}));
      expect(find.bySemanticsLabel('Two children reading'), findsOneWidget);
      expect(find.bySemanticsLabel('Photograph 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Photograph 1'), findsNothing, reason: 'replaced by its own');
      expect(find.bySemanticsLabel('Image 4'), findsOneWidget, reason: 'decorative but opens the larger view: still named');
      expect(tester.getSemantics(find.bySemanticsLabel('Photograph 2')).flagsCollection.isButton, isTrue, reason: 'opens the larger view');
      expect(tester.getSemantics(find.bySemanticsLabel('Photograph 2')).flagsCollection.isImage, isTrue);
      handle.dispose();

      // Tab reaches each image that does something.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, isNotNull);
    });

    testWidgets('hover effects; with reduced motion nothing moves', (tester) async {
      final block = _block(count: 2, extra: {'hover': 'zoom'});
      await pump(tester, block);
      expect(find.byType(AnimatedScale), findsNWidgets(2));
      await pump(tester, block, reduceMotion: true);
      expect(find.byType(AnimatedScale), findsNothing);
      await pump(tester, _block(count: 2, extra: {'hover': 'lift'}), reduceMotion: true);
      expect(find.byType(AnimatedSlide), findsNothing);
    });

    testWidgets('size and spacing: maximum width and alignment; background padding; top and bottom space', (tester) async {
      await pump(tester, _block(extra: {'maxWidth': 600, 'align': 'start', 'paddingTop': 40, 'paddingBottom': 24, 'backgroundPadding': 16, 'style': {'background': 'sage'}}));
      final box = tester.getRect(key('public-asymmetric-b_asym000001'));
      final background = tester.getRect(key('public-asymmetric-b_asym000001-background'));
      expect(box.width, 600);
      expect(box.left, closeTo(background.left + 16, 0.01));
      expect(background.top, closeTo(tester.getRect(key('public-block-b_asym000001')).top + 40, 0.01));
    });

    testWidgets('unpublished or missing images are left out; nothing to show, no block', (tester) async {
      await pump(tester, _block(images: [_image(1), {'id': _iid(2), 'mediaId': 'm_draft01'}, {'id': _iid(3), 'mediaId': 'm_gone'}]));
      expect(key('public-asymmetric-tile-${_iid(1)}'), findsOneWidget);
      expect(key('public-asymmetric-tile-${_iid(2)}'), findsNothing);
      expect(key('public-asymmetric-tile-${_iid(3)}'), findsNothing);
      await pump(tester, _block(images: [{'id': _iid(2), 'mediaId': 'm_draft01'}]));
      expect(key('public-block-b_asym000001'), findsNothing);
    });
  });

  // ---------------------------------------------------------- editor
  group('the editor', () {
    Future<StructuredBlock Function()> edit(WidgetTester tester, StructuredBlock start) async {
      var block = start;
      tester.view.physicalSize = const Size(1000, 6000);
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

    const prefix = 'website-block-b_asym000001';

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

    testWidgets('settings grouped and closed at first; each screen size its own; Automatic back with Reset', (tester) async {
      final block = await edit(tester, _block());
      for (final g in ['layout-on-desktop', 'layout-on-tablets', 'layout-on-phones', 'image-appearance-every-image', 'captions', 'size-and-spacing', 'larger-view']) {
        expect(key('$prefix-group-$g'), findsOneWidget, reason: g);
      }
      expect(key('$prefix-mobileArrangement'), findsNothing, reason: 'closed');
      await open(tester, '$prefix-group-layout-on-phones');
      await pick(tester, '$prefix-mobileArrangement', 'mosaic');
      expect(block().string('mobileArrangement'), 'mosaic');
      expect(block().string('arrangement'), 'auto', reason: 'desktop untouched');
      await tester.enterText(key('$prefix-mobileGapX'), '8');
      await tester.pump();
      expect(block().values['mobileGapX'], 8);
      await tester.enterText(key('$prefix-mobileGapX'), '120');
      await tester.pump();
      expect(find.text('Must be from 0–96 px.'), findsOneWidget);
      expect(BlockRegistry.blockProblems(block()).single, contains('must be from 0 to 96 px'));
      await tester.tap(key('$prefix-mobileGapX-reset'));
      await tester.pump();
      expect(block().values['mobileGapX'], isNull);
      expect(block().toMap().containsKey('mobileGapX'), isFalse, reason: 'Automatic is not stored');
      await pick(tester, '$prefix-mobileArrangement', 'auto');
      expect(block().toMap().containsKey('mobileArrangement'), isFalse);
    });

    testWidgets('images: add several (no duplicates), replace, reorder, remove; thumbnails; the feature image marked', (tester) async {
      final block = await edit(tester, _block(count: 2));
      final images = '$prefix-images';
      expect(key('$images-item-${_iid(1)}-badge'), findsOneWidget);
      expect(find.text('Feature image (first, automatically)'), findsOneWidget);
      expect(find.byType(WebsiteMediaThumb), findsNWidgets(2));

      await tester.ensureVisible(key('$images-add-images'));
      await tester.tap(key('$images-add-images'));
      await tester.pumpAndSettle();
      expect(find.text('Already in this gallery'), findsNWidgets(2), reason: 'not chosen twice by mistake');
      await tester.tap(key('website-choose-many-${_mid(5)}'));
      await tester.pump();
      await tester.tap(key('website-choose-many-${_mid(4)}'));
      await tester.pump();
      await tester.tap(key('website-choose-many-add'));
      await tester.pumpAndSettle();
      expect([for (final i in block().items('images')) i.string('mediaId')], [_mid(1), _mid(2), _mid(5), _mid(4)]);
      final ids = [for (final i in block().items('images')) i.id];

      // Replace (the same image again only when chosen on purpose).
      await tester.ensureVisible(key('$images-item-${ids[1]}-mediaId-choose'));
      await tester.tap(key('$images-item-${ids[1]}-mediaId-choose'));
      await tester.pumpAndSettle();
      await tester.tap(key('website-choose-${_mid(1)}'));
      await tester.pumpAndSettle();
      expect(block().items('images')[1].string('mediaId'), _mid(1));

      // The feature image: one at a time.
      await tester.ensureVisible(key('$images-item-${ids[2]}-feature'));
      await tester.tap(key('$images-item-${ids[2]}-feature'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(key('$images-item-${ids[3]}-feature'));
      await tester.tap(key('$images-item-${ids[3]}-feature'));
      await tester.pumpAndSettle();
      expect([for (final i in block().items('images')) i.values['feature']], [false, false, false, true]);
      expect(key('$images-item-${ids[3]}-badge'), findsOneWidget);
      expect(find.text('Feature image'), findsWidgets);

      await tester.ensureVisible(key('$images-item-${ids[3]}-up'));
      await tester.tap(key('$images-item-${ids[3]}-up'));
      await tester.pump();
      expect([for (final i in block().items('images')) i.id], [ids[0], ids[1], ids[3], ids[2]]);
      await tester.ensureVisible(key('$images-item-${ids[0]}-remove'));
      await tester.tap(key('$images-item-${ids[0]}-remove'));
      await tester.pump();
      expect([for (final i in block().items('images')) i.id], [ids[1], ids[3], ids[2]]);
      expect(BlockRegistry.blockProblems(block()), isEmpty);
    });

    testWidgets('per-image settings in their own groups; alt text flagged when missing', (tester) async {
      final block = await edit(tester, _block(images: [_image(1), {'id': _iid(2), 'mediaId': 'm_noalt01'}, {'id': _iid(3), 'mediaId': 'm_draft01'}]));
      final notes = '$prefix-asymmetric-notes';
      expect(find.descendant(of: key(notes), matching: find.textContaining('Image 2 has no alt text')), findsOneWidget);
      expect(find.descendant(of: key(notes), matching: find.textContaining('Image 3 isn’t published')), findsOneWidget);
      final item = '$prefix-images-item-${_iid(2)}';
      await tester.ensureVisible(key('$item-decorative'));
      await tester.tap(key('$item-decorative'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Image 2 has no alt text'), findsNothing);
      expect(key('$item-hideMobile'), findsNothing, reason: 'closed');
      await open(tester, '$item-group-screen-sizes-and-order');
      await tester.tap(key('$item-hideMobile'));
      await tester.pumpAndSettle();
      expect(block().items('images')[1].values['hideMobile'], isTrue);
      await open(tester, '$item-group-shape-and-appearance-this-image');
      await pick(tester, '$item-aspect', 'custom');
      await tester.enterText(key('$item-aspectCustom-en-0'), '7:5');
      await tester.pump();
      await tester.enterText(key('$item-focalY'), '25');
      await tester.pump();
      final stored = (block().toMap()['images'] as List)[1] as Map;
      expect([stored['decorative'], stored['hideMobile'], stored['aspect'], stored['aspectCustom'], stored['focalY']], [true, true, 'custom', {'en': '7:5', 'ta': ''}, 25]);
    });

    test('summary and the Add block list', () {
      expect(blockSummary(_block(count: 3)), '3 image(s), asymmetric editorial');
      expect(blockIcon(_block()), Icons.auto_awesome_mosaic_outlined);
      expect(BlockRegistry.asymmetricGallery.label, 'Asymmetric gallery');
    });
  });
}

extension on List<(String, int)> {
  List<String> sortedByOrder() {
    final numbered = [for (final (i, e) in indexed) (i, e)];
    numbered.sort((a, b) => a.$2.$2 != b.$2.$2 ? a.$2.$2.compareTo(b.$2.$2) : a.$1.compareTo(b.$1));
    return [for (final e in numbered) e.$2.$1];
  }
}
