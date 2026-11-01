// Tile grids (Photo gallery, School gallery, cards, a page's image grid)
// never build negative widths. The reported exception,
// "BoxConstraints(w=-6.0 …; NOT NORMALIZED)" at the Photo gallery's tile,
// came from a default gallery (2 per row on phones, 12 px apart) laid out
// with no width at all: a window at most 40 px wide, which Flutter Web can
// report for a frame while it resizes or restarts. Also: sections at
// every supported width with no exception or overflow, older documents,
// and the editor's Mobile preview laid out at the phone width it claims.
// Synthetic test data only.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/public_website_theme.dart';
import 'package:montessori_app/modules/public_website/ui/public_gallery_page.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _ids = ['m_a', 'm_b', 'm_c', 'm_d'];

WebsiteMedia _m(String id) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      alt: LocalizedText(en: 'Alt $id'),
      status: WebsiteMediaStatus.published,
      consentConfirmed: true,
    );

final _media = {for (final id in _ids) id: _m(id)};

/// A Photo gallery as stored before its per-row and shape settings
/// existed: 3 per row on desktop, 2 on phones.
Map<String, dynamic> _gallery(String id, {Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'type': 'gallery',
      'v': 1,
      'images': [for (final m in _ids) {'id': 'i_$m${id.substring(2)}', 'mediaId': m}],
      ...extra,
    };

Map<String, dynamic> _cards(String id, {Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'type': 'cards',
      'v': 1,
      'cards': [
        for (var i = 0; i < 4; i++) {'id': 'i_c$i${id.substring(2)}', 'icon': 'star', 'title': {'en': 'Card $i'}},
      ],
      ...extra,
    };

/// A four-column section holding a gallery and cards in each column.
WebsiteBlock _fourColumns({Map<String, dynamic> style = const {}, Map<String, dynamic> gallery = const {}, Map<String, dynamic> cards = const {}}) => BlockRegistry.parse({
      'id': 'b_section0001',
      'type': 'section',
      'v': 1,
      'layout': '1:1:1:1',
      'style': style,
      'columns': [
        for (var i = 0; i < 4; i++)
          {
            'id': 'c_column000$i',
            'blocks': [_gallery('b_gal0000$i', extra: gallery), _cards('b_card000$i', extra: cards)],
          },
      ],
    });

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Every error reported while [blocks] are drawn at [width].
  Future<List<String>> draw(WidgetTester tester, List<WebsiteBlock> blocks, double width) async {
    await size(tester, Size(width, 4000));
    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteDesignScope(
              design: SiteDesign.defaults,
              child: WebsiteBlocksView(blocks: blocks, media: _media, language: PublicLanguage.english, fullBleed: true),
            ),
          ),
        ),
      ));
      await tester.pump();
    } finally {
      FlutterError.onError = original;
    }
    return errors;
  }

  Iterable<Rect> rects(WidgetTester tester, String prefix) =>
      find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith(prefix)).evaluate().map((e) => tester.getRect(find.byWidget(e.widget)));

  test('tile width: never negative; unchanged wherever the tiles fit', () {
    expect(PublicLayout.tileWidth(0, 2, 12), 0, reason: 'the reported case: (0 − 12) / 2 was −6');
    expect(PublicLayout.tileWidth(8, 3, 12), 0);
    expect(PublicLayout.tileWidth(60, 6, 20), 0);
    expect(PublicLayout.tileWidth(350, 2, 12), 169);
    expect(PublicLayout.tileWidth(960, 3, 20), 306);
    expect(PublicLayout.tileWidth(100, 0, 20), 100, reason: 'at least one per row');
  });

  testWidgets('the reported failure: a default Photo gallery in a window 0 to 48 px wide builds no negative width', (tester) async {
    final gallery = BlockRegistry.parse(_gallery('b_gal00000'));
    for (var w = 0.0; w <= 48; w += 4) {
      final errors = await draw(tester, [gallery], w);
      expect(errors.where((e) => e.contains('negative')), isEmpty, reason: 'at ${w}px');
      for (final r in rects(tester, 'public-gallery-item-')) {
        expect(r.width, greaterThanOrEqualTo(0));
      }
    }
  });

  testWidgets('four columns with gaps, cards and galleries per row: no exception or overflow at 320, 390, 820, 1100 and 1400 px', (tester) async {
    final configs = [
      _fourColumns(),
      _fourColumns(style: {'columnGap': '64', 'rowGap': '48', 'width': 'narrow'}, gallery: {'columns': '6', 'tabletColumns': '4', 'mobileColumns': '3'}, cards: {'desktopColumns': '4', 'tabletColumns': '3', 'mobileColumns': '2'}),
      _fourColumns(style: {'columnGap': '0', 'rowGap': '0'}, gallery: {'columns': '1', 'mobileColumns': '1'}),
    ];
    for (final section in configs) {
      for (final w in [320.0, 390.0, 820.0, 1100.0, 1400.0]) {
        final errors = await draw(tester, [section], w);
        expect(errors, isEmpty, reason: 'at ${w}px: ${errors.firstOrNull?.split('\n').first}');
        for (final r in [...rects(tester, 'public-gallery-item-'), ...rects(tester, 'public-card-'), ...rects(tester, 'public-block-column-')]) {
          expect((r.left >= 0, r.right <= w + 0.01, r.width >= 0), (true, true, true), reason: '$r inside ${w}px');
        }
      }
    }
  });

  testWidgets('responsive arrangement is unchanged: desktop one row, tablet two by two, phones stacked', (tester) async {
    final section = _fourColumns(style: {'columnGap': '24', 'rowGap': '16'});
    expect(BlockRegistry.validate([section]), isEmpty, reason: 'ids unique, block valid');
    Rect col(int i) => tester.getRect(key('public-block-column-c_column000$i'));
    await draw(tester, [section], 1400);
    expect({for (var i = 0; i < 4; i++) col(i).top}.length, 1);
    await draw(tester, [section], 820);
    expect((col(1).top, col(2).left), (col(0).top, col(0).left));
    for (final w in [390.0, 320.0]) {
      await draw(tester, [section], w);
      for (var i = 1; i < 4; i++) {
        expect(col(i).top, greaterThan(col(i - 1).bottom));
      }
    }
    // Tiles fill a phone row exactly as before: 2 per row, 12 apart.
    final first = tester.getRect(key('public-gallery-item-i_m_agal00000'));
    expect(first.width, PublicLayout.tileWidth(320 - 40, 2, 12));
  });

  testWidgets('older documents: a section without a layout and a gallery without its newer settings render at every width', (tester) async {
    final old = BlockRegistry.parse({
      'id': 'b_section0002',
      'type': 'section',
      'v': 1,
      'columns': [
        {'id': 'c_column0009', 'blocks': [{'id': 'b_galold001', 'type': 'gallery', 'v': 1, 'images': [{'id': 'i_m_a000old', 'mediaId': 'm_a'}, {'id': 'i_m_b000old', 'mediaId': 'm_b'}]}]},
      ],
    }) as StructuredBlock;
    expect(old.string('layout'), '1');
    expect(BlockRegistry.blockProblems(old), isEmpty);
    for (final w in [0.0, 24.0, 320.0, 390.0, 820.0, 1400.0]) {
      final errors = await draw(tester, [old], w);
      expect(errors.where((e) => e.contains('negative')), isEmpty, reason: 'at ${w}px');
      if (w >= 320) expect(errors, isEmpty, reason: 'at ${w}px');
    }
    expect(rects(tester, 'public-gallery-item-').length, 2);
  });

  testWidgets('the School gallery’s grid builds no negative width in a window almost 0 px wide', (tester) async {
    for (final w in [0.0, 20.0, 390.0]) {
      await size(tester, Size(w, 3000));
      final errors = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.toString());
      try {
        await tester.pumpWidget(ProviderScope(
          overrides: [publicGalleryProvider.overrideWith((ref) async => _media.values.toList())],
          child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PublicGalleryFeed()))),
        ));
        await tester.pump();
        await tester.pump();
      } finally {
        FlutterError.onError = original;
      }
      expect(errors.where((e) => e.contains('negative')), isEmpty, reason: 'at ${w}px');
      if (w >= 320) expect(errors, isEmpty);
    }
  });

  testWidgets('the editor’s Mobile preview is laid out at 390 px, scaled down when the canvas is narrower', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    late String id;
    await tester.runAsync(() async {
      for (final m in _ids) {
        await firestore.collection(WebsiteCollections.media).doc(m).set({
          'url': 'https://example.test/$m.jpg', 'storagePath': 'website_media/$m/d.jpg', 'status': 'published', 'consentConfirmed': true,
          'alt': {'en': 'Alt $m', 'ta': ''}, 'caption': {'en': '', 'ta': ''},
        });
      }
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Scratch'), slug: 'scratch');
      id = created.id;
      await firestore.collection(WebsiteCollections.pageDrafts).doc(id).update({'sections': [], 'schemaVersion': 2, 'blocks': [_gallery('b_gal00000')]});
    });
    Finder tiles() => find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('public-gallery-item-'));
    Future<void> openMobile(Size window, {bool structure = false}) async {
      await size(tester, window);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: id)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(key('website-custom-preview-mobile'));
      await tester.pumpAndSettle();
      if (structure) {
        await tester.tap(key('website-editor-toggle-structure'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    }

    // A wide window: the phone frame at its full 390 px.
    await openMobile(const Size(1400, 2400));
    final reference = tester.renderObject<RenderBox>(tiles().first).size.width;
    // 920 px: the editor's medium layout; with the structure panel open
    // the canvas is narrower than a phone.
    await openMobile(const Size(920, 2400), structure: true);

    final frame = tester.renderObject<RenderBox>(key('website-custom-preview-mobile-frame'));
    expect(frame.size.width, 390, reason: 'laid out at the phone width, not squeezed');
    expect(tester.getRect(key('website-custom-preview-mobile-frame')).width, lessThan(390), reason: 'scaled down to fit the canvas');
    expect(tester.renderObject<RenderBox>(tiles().first).size.width, reference, reason: 'the same tiles as in the full-size phone frame');
  });
}
