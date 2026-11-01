// Visual builder layouts and content controls: four-column sections with
// column and row gaps, items per row for cards and points, the Photo
// gallery's chosen images and settings, and the Map block. Settings added
// to existing block types are optional: blocks saved before they existed
// read, save and render exactly as before.
//
// Synthetic data only. The fake Firestore proves the app's behaviour, not
// deployed security rules.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/field_spec.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_map_block.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/public_website_image.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _desktop = Size(1400, 2400);
const _tablet = Size(820, 2400);
const _phone = Size(390, 2400);
const _narrow = Size(320, 2400);

WebsiteMedia _media(String id, {String caption = ''}) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      alt: LocalizedText(en: 'Alt $id'),
      caption: LocalizedText(en: caption),
      status: WebsiteMediaStatus.published,
      consentConfirmed: true,
    );

final _library = [for (final id in ['m_a', 'm_b', 'm_c', 'm_d', 'm_e', 'm_f']) _media(id, caption: 'Library caption $id')];

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parse(raw) as StructuredBlock;

StructuredBlock _text(String heading) {
  final b = BlockRegistry.create(BlockRegistry.text);
  return b.copyWith(values: {...b.values, 'heading': LocalizedText(en: heading)});
}

/// A section of [layout] with one Text block per column.
StructuredBlock _section(String layout, {Map<String, dynamic> style = const {}}) {
  final widths = columnLayouts[layout]!;
  return _parse({
    'id': 'b_section0001',
    'type': 'section',
    'v': 1,
    'layout': layout,
    'columns': [
      for (var i = 0; i < widths.length; i++)
        {'id': 'c_column000$i', 'blocks': [_text('Column $i').copyWith(id: 'b_coltext000$i').toMap()]},
    ],
    'style': style,
  });
}

Map<String, dynamic> _gallery({Map<String, dynamic> extra = const {}, List<Map<String, dynamic>>? images}) => {
      'id': 'b_gallery0001',
      'type': 'gallery',
      'v': 1,
      'heading': {'en': 'Our school', 'ta': 'எங்கள் பள்ளி'},
      'columns': '3',
      'images': images ?? [for (final m in ['m_a', 'm_b', 'm_c', 'm_d']) {'id': 'i_${m}00000', 'mediaId': m}],
      ...extra,
    };

Map<String, dynamic> _cards(int n, {Map<String, dynamic> extra = const {}}) => {
      'id': 'b_cards00001',
      'type': 'cards',
      'v': 1,
      // As the app stores them: every text with its English and Tamil.
      'heading': {'en': 'Pathways', 'ta': ''},
      'cards': [
        for (var i = 0; i < n; i++)
          {'id': 'i_card00000$i', 'icon': 'star', 'title': {'en': 'Card $i', 'ta': ''}, 'body': {'en': '', 'ta': ''}, 'linkLabel': {'en': '', 'ta': ''}, 'target': '', 'accent': 'primary'},
      ],
      ...extra,
    };

Map<String, dynamic> _map({Map<String, dynamic> extra = const {}}) => {
      'id': 'b_map0000001',
      'type': 'map',
      'v': 1,
      'heading': {'en': 'Find us', 'ta': 'எங்களைக் கண்டறிய'},
      'address': {'en': '12 Synthetic Street, Testville 600001'},
      ...extra,
    };

/// The stored map, as JSON (types as Firestore would hold them).
Object? _plain(Object? v) => jsonDecode(jsonEncode(v));

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// [blocks] as the website draws them at [at] (the editor's canvas when
  /// not [interactive]).
  Future<void> pumpBlocks(WidgetTester tester, List<WebsiteBlock> blocks, {Size at = _desktop, bool interactive = true, PublicLanguage language = PublicLanguage.english}) async {
    await size(tester, at);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: blocks, media: {for (final m in _library) m.id: m}, language: language, interactive: interactive, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> seedMedia() async {
    for (final m in _library) {
      await firestore.collection(WebsiteCollections.media).doc(m.id).set({
        'url': m.url,
        'storagePath': m.storagePath,
        'status': 'published',
        'consentConfirmed': true,
        'alt': {'en': m.alt.en, 'ta': ''},
        'caption': {'en': m.caption.en, 'ta': ''},
      });
    }
  }

  group('existing blocks: unchanged when the new settings are absent', () {
    test('stored before the new settings: read and saved back exactly, valid', () {
      for (final raw in [_gallery(), _cards(3), _section('1:1:1').toMap(), {..._gallery(), 'images': [{'id': 'i_m_a00000', 'mediaId': 'm_a'}]}]) {
        final block = _parse(Map<String, dynamic>.from(_plain(raw) as Map));
        expect(_plain(block.toMap()), _plain(raw), reason: '${raw['type']} round-trips');
        expect(BlockRegistry.blockProblems(block), isEmpty, reason: '${raw['type']} is still valid');
      }
      // A block built before the fields existed (the older section format's
      // conversion fills only some values): its new settings read as defaults.
      final legacy = StructuredBlock(definition: BlockRegistry.gallery, id: 'b_legacy0001', values: {
        'heading': const LocalizedText(en: 'Grid'),
        'columns': '3',
        'images': [const BlockItem(id: 'i_legacy0001', values: {'mediaId': 'm_a'})],
      });
      expect(BlockRegistry.blockProblems(legacy), isEmpty);
      expect((legacy.option('mobileColumns'), legacy.option('aspect'), legacy.option('limit'), legacy.toggle('showCaptions')), ('2', '4:3', 'all', true));
    });

    testWidgets('a gallery looks as before: 3 per row (2 on phones), 4:3, the library’s captions', (tester) async {
      final gallery = _parse(_gallery());
      for (final (at, perRow) in [(_desktop, 3), (_tablet, 3), (_phone, 2)]) {
        await pumpBlocks(tester, [gallery], at: at);
        final first = tester.getRect(key('public-gallery-item-i_m_a00000'));
        final second = tester.getRect(key('public-gallery-item-i_m_b00000'));
        final third = tester.getRect(key('public-gallery-item-i_m_c00000'));
        expect(second.top, first.top, reason: 'two side by side at $at');
        expect(third.top == first.top, perRow >= 3, reason: '$perRow per row at $at');
        expect(tester.widget<PublicWebsiteImage>(find.byType(PublicWebsiteImage).first).aspectRatio, 4 / 3);
        expect(find.text('Library caption m_a'), findsOneWidget);
      }
    });

    testWidgets('cards and points keep their automatic layout: one row, stacked on phones', (tester) async {
      final cards = _parse(_cards(3));
      await pumpBlocks(tester, [cards]);
      final tops = [for (var i = 0; i < 3; i++) tester.getRect(key('public-card-i_card00000$i')).top];
      expect(tops.toSet().length, 1, reason: 'all in one row');
      await pumpBlocks(tester, [cards], at: _phone);
      expect(tester.getRect(key('public-card-i_card000001')).top, greaterThan(tester.getRect(key('public-card-i_card000000')).bottom));
    });

    testWidgets('a three-column section: one row on tablets, as before; default gaps', (tester) async {
      final section = _parse(_plain(_section('1:1:1').toMap()) as Map<String, dynamic>);
      await pumpBlocks(tester, [section], at: _tablet);
      final a = tester.getRect(key('public-block-column-c_column0000'));
      final b = tester.getRect(key('public-block-column-c_column0001'));
      expect(b.top, a.top);
      expect(b.left - a.right, 40, reason: 'the default 40 px between columns');
    });
  });

  group('section and column layouts', () {
    test('four columns, gaps: offered, validated, stored only when set', () {
      expect(columnLayouts['1:1:1:1'], [1, 1, 1, 1]);
      expect((BlockRegistry.section.field('layout') as ChoiceFieldSpec).options, contains('1:1:1:1'));
      expect((BlockRegistry.columns.field('layout') as ChoiceFieldSpec).options, contains('1:1:1:1'));
      expect(BlockRegistry.section.styleKeys, containsAll(['columnGap', 'rowGap', 'padding', 'width', 'spacing']));
      expect(BlockRegistry.blockProblems(_section('1:1:1:1', style: {'columnGap': '24', 'rowGap': '16'})), isEmpty);
      expect(BlockRegistry.blockProblems(_section('1:1:1:1', style: {'columnGap': '25'})).single, contains('columnGap'));
      expect(_section('1:1').toMap()['style'], isNull, reason: 'nothing written unless set');
      // A four-column section needs four columns.
      final short = _section('1:1:1:1').withValue('columns', _section('1:1:1:1').columns('columns').take(3).toList());
      expect(BlockRegistry.blockProblems(short).single, contains('4 columns'));
    });

    testWidgets('four columns: one row on desktop, two by two on tablets, stacked on phones; no overflow', (tester) async {
      final section = _section('1:1:1:1', style: {'columnGap': '24', 'rowGap': '16'});
      Rect col(int i) => tester.getRect(key('public-block-column-c_column000$i'));
      await pumpBlocks(tester, [section]);
      expect({for (var i = 0; i < 4; i++) col(i).top}.length, 1);
      expect(col(1).left - col(0).right, 24, reason: 'the column gap');

      await pumpBlocks(tester, [section], at: _tablet);
      expect((col(1).top, col(2).left), (col(0).top, col(0).left), reason: 'two rows of two');
      expect(col(2).top - col(0).bottom, 16, reason: 'the row gap');

      for (final at in [_phone, _narrow]) {
        await pumpBlocks(tester, [section], at: at);
        expect(tester.takeException(), isNull, reason: 'no overflow at ${at.width}');
        expect(col(1).top - col(0).bottom, 16);
        expect(col(3).right, lessThanOrEqualTo(at.width));
      }
    });

    testWidgets('the editor offers the layouts by name, and four columns adds a column', (tester) async {
      var block = _section('1:1:1');
      await size(tester, _desktop);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteBlockForm(block: block, library: _library, generation: 0, onChanged: (b) => setState(() => block = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      await tester.tap(key('website-block-${block.id}-layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Four columns').last);
      await tester.pumpAndSettle();
      expect((block.string('layout'), block.columns('columns').length), ('1:1:1:1', 4));
      expect(block.columns('columns').take(3).map((c) => c.id), ['c_column0000', 'c_column0001', 'c_column0002'], reason: 'existing columns keep their ids');
      expect(find.text('Space between columns'), findsOneWidget);
    });
  });

  group('items per row', () {
    test('cards and points: per screen size, validated, stored only when set', () {
      for (final d in [BlockRegistry.cards, BlockRegistry.features]) {
        expect([for (final f in d.fields) f.key], containsAll(['desktopColumns', 'tabletColumns', 'mobileColumns']));
      }
      final set = _parse({..._cards(4), 'desktopColumns': '2', 'mobileColumns': '1'});
      expect(_plain(set.toMap()), containsPair('desktopColumns', '2'));
      expect(set.toMap().containsKey('tabletColumns'), isFalse);
      expect(BlockRegistry.blockProblems(_parse({..._cards(4), 'desktopColumns': '7'})).single, contains('per row on desktop'));
      expect(BlockRegistry.blockProblems(_parse(_cards(8))), isEmpty, reason: 'up to eight cards');
    });

    testWidgets('two cards per row on desktop and tablets, one on phones; an unknown value falls back', (tester) async {
      final cards = _parse({..._cards(4), 'desktopColumns': '2'});
      Rect card(int i) => tester.getRect(key('public-card-i_card00000$i'));
      for (final at in [_desktop, _tablet]) {
        await pumpBlocks(tester, [cards], at: at);
        expect((card(1).top, card(2).left), (card(0).top, card(0).left), reason: 'two per row at ${at.width}');
        expect(card(0).height, card(1).height, reason: 'a row shares its height');
      }
      await pumpBlocks(tester, [cards], at: _phone);
      expect(card(1).top, greaterThan(card(0).bottom));

      // A value this version doesn't know: like any block with a problem,
      // it isn't shown (the editor reports it); kept as stored.
      final unknown = _parse({..._cards(3), 'desktopColumns': '9'});
      await pumpBlocks(tester, [unknown]);
      expect(key('public-card-i_card000000'), findsNothing);
      expect(unknown.toMap()['desktopColumns'], '9');
      expect(unknown.option('desktopColumns'), 'auto', reason: 'read safely as the default');
    });
  });

  group('Photo gallery', () {
    test('chosen images, their order, captions, links and settings: kept, validated', () {
      final raw = _gallery(extra: {'columns': '4', 'tabletColumns': '2', 'mobileColumns': '1', 'aspect': '1:1', 'limit': '3', 'showCaptions': false}, images: [
        {'id': 'i_m_c00000', 'mediaId': 'm_c', 'caption': {'en': 'Our garden', 'ta': 'எங்கள் தோட்டம்'}},
        {'id': 'i_m_a00000', 'mediaId': 'm_a', 'target': '/admissions'},
        {'id': 'i_m_b00000', 'mediaId': 'm_b'},
        {'id': 'i_m_d00000', 'mediaId': 'm_d'},
      ]);
      final block = _parse(raw);
      expect(_plain(block.toMap()), _plain(raw));
      expect(BlockRegistry.blockProblems(block), isEmpty);
      expect(BlockRegistry.referencedMedia([block]), ['m_c', 'm_a', 'm_b', 'm_d']);
      expect(BlockRegistry.blockProblems(_parse(_gallery(extra: {'aspect': '2:1'}))).single, contains('image shape'));
      expect(
        BlockRegistry.blockProblems(_parse(_gallery(images: [{'id': 'i_m_a00000', 'mediaId': 'm_a', 'target': 'javascript:alert(1)'}]))),
        isNotEmpty,
        reason: 'links are checked',
      );
    });

    testWidgets('per row on each screen, shape, limit, order, own captions; links instead of the lightbox', (tester) async {
      final block = _parse(_gallery(extra: {'columns': '4', 'tabletColumns': '2', 'mobileColumns': '1', 'aspect': '1:1', 'limit': '3'}, images: [
        {'id': 'i_m_c00000', 'mediaId': 'm_c', 'caption': {'en': 'Our garden'}},
        {'id': 'i_m_a00000', 'mediaId': 'm_a', 'target': '/admissions'},
        {'id': 'i_m_b00000', 'mediaId': 'm_b'},
        {'id': 'i_m_d00000', 'mediaId': 'm_d'},
        {'id': 'i_missing0', 'mediaId': 'm_gone'},
      ]));
      Rect item(String id) => tester.getRect(key('public-gallery-item-$id'));
      await pumpBlocks(tester, [block]);
      expect(key('public-gallery-item-i_m_d00000'), findsNothing, reason: 'the limit: three shown');
      expect(key('public-gallery-item-i_missing0'), findsNothing, reason: 'a removed image is left out');
      expect(item('i_m_c00000').left, lessThan(item('i_m_a00000').left), reason: 'the chosen order');
      expect(item('i_m_c00000').width, closeTo((960 - 3 * 20) / 4, 1), reason: 'four per row in the 960 px content width');
      expect(tester.widget<PublicWebsiteImage>(find.byType(PublicWebsiteImage).first).aspectRatio, 1.0);
      expect(find.text('Our garden'), findsOneWidget, reason: 'its own caption');
      expect(find.text('Library caption m_c'), findsNothing);
      expect(find.text('Library caption m_b'), findsOneWidget, reason: 'else the library’s');

      await pumpBlocks(tester, [block], at: _tablet);
      expect(item('i_m_a00000').top, item('i_m_c00000').top);
      expect(item('i_m_b00000').top, greaterThan(item('i_m_c00000').top), reason: 'two per row on tablets');
      for (final at in [_phone, _narrow]) {
        await pumpBlocks(tester, [block], at: at);
        expect(tester.takeException(), isNull);
        expect(item('i_m_a00000').top, greaterThan(item('i_m_c00000').bottom), reason: 'one per row on phones');
      }

      // Captions off.
      await pumpBlocks(tester, [_parse(_gallery(extra: {'showCaptions': false}))]);
      expect(find.text('Library caption m_a'), findsNothing);
    });

    testWidgets('adding several images at once, in the order ticked; reorder and remove keep ids', (tester) async {
      var block = _parse(_gallery(images: [{'id': 'i_m_a00000', 'mediaId': 'm_a'}]));
      await size(tester, const Size(1200, 2400));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteBlockForm(block: block, library: _library, generation: 0, onChanged: (b) => setState(() => block = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      final prefix = 'website-block-${block.id}-images';
      await tester.ensureVisible(key('$prefix-add-images'));
      await tester.tap(key('$prefix-add-images'));
      await tester.pumpAndSettle();
      expect(find.text('Already in this gallery'), findsOneWidget);
      await tester.tap(key('website-choose-many-m_d'));
      await tester.pump();
      await tester.tap(key('website-choose-many-m_b'));
      await tester.pump();
      expect(find.text('Add 2'), findsOneWidget);
      await tester.tap(key('website-choose-many-add'));
      await tester.pumpAndSettle();
      expect([for (final i in block.items('images')) i.string('mediaId')], ['m_a', 'm_d', 'm_b']);
      final ids = [for (final i in block.items('images')) i.id];
      expect(ids.toSet().length, 3);

      await tester.ensureVisible(key('$prefix-item-${ids[2]}-up'));
      await tester.tap(key('$prefix-item-${ids[2]}-up'));
      await tester.pump();
      expect([for (final i in block.items('images')) i.id], [ids[0], ids[2], ids[1]]);
      await tester.tap(key('$prefix-item-${ids[0]}-remove'));
      await tester.pump();
      expect([for (final i in block.items('images')) i.id], [ids[2], ids[1]]);
      expect(BlockRegistry.blockProblems(block), isEmpty);
    });

    testWidgets('English edits keep the Tamil text; Tamil isn’t offered', (tester) async {
      var block = _parse(_gallery(images: [
        {'id': 'i_m_a00000', 'mediaId': 'm_a', 'caption': {'en': 'Garden', 'ta': 'தோட்டம்'}},
      ]));
      await size(tester, const Size(1200, 2400));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteBlockForm(block: block, library: _library, generation: 0, onChanged: (b) => setState(() => block = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      expect(find.textContaining('(Tamil)'), findsNothing);
      await tester.enterText(key('website-block-${block.id}-heading-en-0'), 'Life at school');
      await tester.enterText(key('website-block-${block.id}-images-item-i_m_a00000-caption-en-0'), 'Our garden');
      await tester.pump();
      expect((block.text('heading').en, block.text('heading').ta), ('Life at school', 'எங்கள் பள்ளி'));
      final caption = block.items('images').single.text('caption');
      expect((caption.en, caption.ta), ('Our garden', 'தோட்டம்'));
    });
  });

  group('Map block', () {
    test('its settings: defaults, keyless addresses from the configured place, validation', () {
      final block = _parse(_map());
      expect(BlockRegistry.blockProblems(block), isEmpty);
      final config = MapBlockConfig.of(block);
      expect((config.address, config.satellite, config.zoom, config.height, config.showDirections), ('12 Synthetic Street, Testville 600001', false, 15, 320.0, true));
      final embed = config.embedUrl();
      expect((embed.scheme, embed.host, embed.path), ('https', 'maps.google.com', '/maps'));
      expect(embed.queryParameters, {'q': '12 Synthetic Street, Testville 600001', 't': 'm', 'z': '15', 'hl': 'en', 'output': 'embed'});
      expect(embed.toString(), isNot(contains('key=')), reason: 'no API key');
      expect(config.directionsUrl.toString(), 'https://www.google.com/maps/dir/?api=1&destination=12+Synthetic+Street%2C+Testville+600001');

      final satellite = MapBlockConfig.of(_parse(_map(extra: {'mapType': 'satellite', 'zoom': '18', 'height': '480', 'showDirections': false})));
      expect((satellite.embedUrl(language: 'ta').queryParameters['t'], satellite.embedUrl().queryParameters['z'], satellite.height, satellite.showDirections), ('k', '18', 480.0, false));
      // Values this version doesn't know: reported, and drawn with the defaults.
      final odd = _parse(_map(extra: {'zoom': '25', 'height': 'tall'}));
      expect(BlockRegistry.blockProblems(odd), hasLength(2));
      expect((MapBlockConfig.of(odd).zoom, MapBlockConfig.of(odd).height), (15, 320.0));

      expect(BlockRegistry.blockProblems(_parse(_map(extra: {'address': {'en': ' '}}))).single, contains('address or place name in English'));
      expect(BlockRegistry.blockProblems(_parse(_map(extra: {'address': {'en': '<script>'}}))).single, contains('< or >'));
      // A new block: valid once it has a place.
      final created = BlockRegistry.create(BlockRegistry.map);
      expect(BlockRegistry.blockProblems(created).single, contains('address'));
      expect(BlockRegistry.blockProblems(created.withValue('address', const LocalizedText(en: 'Somewhere'))), isEmpty);
    });

    testWidgets('drawn with its place, title and directions; fits phones; the editor shows the same, without links', (tester) async {
      final semantics = tester.ensureSemantics();
      final block = _parse(_map(extra: {'details': {'en': 'Open 8 am to 3 pm'}, 'height': '400'}));
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pumpBlocks(tester, [block], at: at);
        expect(tester.takeException(), isNull, reason: 'no overflow at ${at.width}');
        final area = tester.getRect(key('public-map-area'));
        expect(area.height, closeTo(400, 0.01));
        expect(area.right, lessThanOrEqualTo(at.width));
        expect(find.text('Map showing 12 Synthetic Street, Testville 600001'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Map showing 12 Synthetic Street')), findsWidgets);
        expect(find.text('Open 8 am to 3 pm'), findsOneWidget);
        expect(tester.widget<TextButton>(key('public-map-directions')).onPressed, isNotNull);
      }
      // Details beside the map on wide screens, above it on phones.
      await pumpBlocks(tester, [block]);
      expect(tester.getRect(key('public-map-details')).right, lessThan(tester.getRect(key('public-map-area')).left));
      await pumpBlocks(tester, [block], at: _phone);
      expect(tester.getRect(key('public-map-details')).bottom, lessThan(tester.getRect(key('public-map-area')).top));

      // Tamil visitors: Tamil heading and labels, the same place.
      await pumpBlocks(tester, [block], language: PublicLanguage.tamil);
      expect(find.text('எங்களைக் கண்டறிய'), findsOneWidget);
      expect(find.text(PublicStrings.of(PublicLanguage.tamil).mapDirections), findsOneWidget);

      // The editor's canvas: the same map, and nothing that navigates away.
      await pumpBlocks(tester, [block], interactive: false);
      expect(tester.getRect(key('public-map-area')).height, closeTo(400, 0.01));
      expect(tester.widget<TextButton>(key('public-map-directions')).onPressed, isNull);

      await pumpBlocks(tester, [_parse(_map(extra: {'showDirections': false}))]);
      expect(key('public-map-directions'), findsNothing);
      semantics.dispose();
    });
  });

  group('saved, published, reloaded, reverted', () {
    List<WebsiteBlock> pageBlocks() => [
          _section('1:1:1:1', style: {'columnGap': '24'}),
          _parse(_gallery(extra: {'columns': '4', 'mobileColumns': '1', 'aspect': '3:4', 'limit': '3'}, images: [
            {'id': 'i_m_c00000', 'mediaId': 'm_c', 'caption': {'en': 'Garden'}},
            {'id': 'i_m_a00000', 'mediaId': 'm_a'},
          ])),
          _parse(_map()),
          _parse({..._cards(4), 'desktopColumns': '2'}),
        ];

    test('an additional page: draft, publish and reload keep every setting and id', () async {
      await seedMedia();
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Visit'), slug: 'visit');
      final page = created.copyWith(blocks: () => pageBlocks());
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page);
      var state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(_plain(BlockRegistry.toMapList(state.draft.blocks!)), _plain(BlockRegistry.toMapList(pageBlocks())));
      expect(state.live, isNull, reason: 'a draft isn’t published');

      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: state.draft);
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(_plain(BlockRegistry.toMapList(state.live!.blocks!)), _plain(BlockRegistry.toMapList(pageBlocks())));

      // Editing the draft (the map removed) leaves the published page as it was.
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: state.draft.copyWith(blocks: () => pageBlocks().where((b) => b.type != 'map').toList()));
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(state.draft.blocks!.any((b) => b.type == 'map'), isFalse);
      expect(state.live!.blocks!.any((b) => b.type == 'map'), isTrue);
      await service.unpublishCustomPage(requesterRole: 'admin', actor: _admin, pageId: created.id);
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect((state.live, state.draft.blocks!.length), (null, 3), reason: 'unpublishing keeps the draft');
    });

    test('a built-in page: publish, unpublish and revert', () async {
      await seedMedia();
      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: pageBlocks());
      var state = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.contact);
      expect(_plain(BlockRegistry.toMapList(state.live!)), _plain(BlockRegistry.toMapList(pageBlocks())));
      await service.unpublishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact);
      state = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.contact);
      expect((state.live, state.draft?.length), (null, 4));
      await service.revertBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact);
      state = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.contact);
      expect((state.live, state.draft), (null, null));
    });

    testWidgets('the published page and the editor’s canvas draw the same layout', (tester) async {
      await seedMedia();
      final created = await tester.runAsync(() => service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Visit'), slug: 'visit'));
      await tester.runAsync(() => service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: created!.copyWith(blocks: () => pageBlocks())));

      await size(tester, _desktop);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
          websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
        ],
        child: const MontessoriApp(),
      ));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/pages/visit');
      await tester.pumpAndSettle();
      Map<String, Size> sizes() => {
            for (final k in ['public-block-column-c_column0000', 'public-gallery-item-i_m_c00000', 'public-map-area', 'public-card-i_card000000']) k: tester.getSize(key(k)),
          };
      final published = sizes();
      expect(find.text('Map showing 12 Synthetic Street, Testville 600001'), findsOneWidget);

      await pumpBlocks(tester, pageBlocks(), interactive: false);
      expect(sizes(), published);
    });
  });
}
