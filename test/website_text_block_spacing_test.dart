// Text blocks (and Buttons, Accreditations) with the shared block spacing:
// padding inside the block, margin outside it, each side on its own, zero a
// value, Desktop / Tablet / Phone inheritance; a top margin is the space
// above the block (in place of Space above or the section's gap, never added
// to it); side spacing is measured from the edges the block is given; the
// editor's canvas lays blocks out exactly as the website does (its outline
// takes no space); nothing changes when nothing is set. Synthetic data only.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_spacing.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/block_spacing_box.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

class _FakeProcessor implements WebsiteImageProcessor {
  @override
  Future<ProcessedWebsiteImage> process(Uint8List bytes, {required String contentType}) async => ProcessedWebsiteImage(
        width: 1600,
        height: 1200,
        display: Uint8List.fromList([1, 2, 3]),
        displayContentType: 'image/jpeg',
        thumb: Uint8List.fromList([4]),
        thumbContentType: 'image/jpeg',
      );
}

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');

const _desktop = Size(1400, 3000);
const _tablet = Size(820, 3000);
const _phone = Size(390, 3000);
const _narrow = Size(320, 3000);

/// The content edge of a 960 px text block on a 1400 px page.
const _edge = (1400 - 960) / 2;

const _address = '4/64, Richard Street,\n\nNGGO Colony,\n\nCoimbatore';

Map<String, dynamic> _text(String id, {String heading = 'Get in Touch', String body = _address, Map<String, dynamic> style = const {}}) => {
      'id': id,
      'type': 'text',
      'v': 1,
      'heading': {'en': heading, 'ta': 'தொடர்பு கொள்ள'},
      'body': {'en': body, 'ta': ''},
      if (style.isNotEmpty) 'style': style,
    };

Map<String, dynamic> _sides(int top, int right, int bottom, int left) => {'top': top, 'right': right, 'bottom': bottom, 'left': left};

Map<String, dynamic> _section(List<Map<String, dynamic>> left, {List<Map<String, dynamic>> right = const []}) => {
      'id': 'b_sect000001',
      'type': 'section',
      'v': 1,
      'layout': '1:1',
      'columns': [
        {'id': 'c_left000001', 'blocks': left},
        {'id': 'c_right00001', 'blocks': right},
      ],
    };

List<WebsiteBlock> _parse(List<Map<String, dynamic>> raw) => BlockRegistry.parseList(raw);

void main() {
  Finder key(String k) => find.byKey(Key(k));

  Future<void> pump(WidgetTester tester, List<WebsiteBlock> blocks, {Size at = _desktop, bool interactive = true, bool spaced = true}) async {
    tester.view.physicalSize = at;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, interactive: interactive, spaced: spaced, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Rect r(WidgetTester tester, String text) => tester.getRect(find.descendant(of: find.byType(WebsiteBlocksView), matching: find.text(text)).first);
  Rect box(WidgetTester tester, String id) => tester.getRect(key('public-block-$id-padding'));
  double round(double v) => (v * 100).roundToDouble() / 100;

  group('a Text block on its own', () {
    testWidgets('nothing set: drawn exactly as before (no default padding, nothing added)', (tester) async {
      await pump(tester, _parse([_text('b_text000001')]));
      final heading = r(tester, 'Get in Touch');
      expect(find.byType(FitPadding), findsNothing);
      // Paragraphs keep their spacing: one line apart plus 14 px.
      expect(round(r(tester, 'NGGO Colony,').top - r(tester, '4/64, Richard Street,').bottom), 14);
      await pump(tester, _parse([_text('b_text000001', style: {BlockSpacing.padding: {'watch': {'top': 9}}})]));
      expect(r(tester, 'Get in Touch'), heading, reason: 'an unknown screen sets nothing');
    });

    testWidgets('padding on all four sides, from the block’s edges; long text keeps wrapping inside', (tester) async {
      final long = List.filled(30, 'Children learn at their own pace in a prepared environment.').join(' ');
      await pump(tester, _parse([_text('b_text000001', body: long, style: {BlockSpacing.padding: {'desktop': _sides(10, 30, 20, 40)}})]));
      final b = box(tester, 'b_text000001');
      expect(b.left, _edge, reason: 'the block spans the content width');
      expect(b.width, 960);
      expect(r(tester, 'Get in Touch').left - b.left, 40);
      expect(r(tester, 'Get in Touch').top - b.top, 10);
      final body = tester.getRect(find.text(long));
      expect(round(b.bottom - body.bottom), 20);
      expect(body.right, lessThanOrEqualTo(b.right - 30 + 0.01));
      expect(tester.renderObject<RenderFitPadding>(key('public-block-b_text000001-padding')).applied, const EdgeInsets.fromLTRB(40, 10, 30, 20));
    });

    testWidgets('top and bottom on their own; zero is zero', (tester) async {
      await pump(tester, _parse([_text('b_text000001', style: {BlockSpacing.padding: {'desktop': {'top': 0, 'bottom': 36}}})]));
      final b = box(tester, 'b_text000001');
      expect(r(tester, 'Get in Touch').top, b.top, reason: 'top 0');
      expect(round(b.bottom - r(tester, 'Coimbatore').bottom), 36);
      expect(tester.renderObject<RenderFitPadding>(key('public-block-b_text000001-padding')).applied, const EdgeInsets.only(bottom: 36));
    });

    testWidgets('Desktop, Tablet and Phone: their own values, Tablet from Desktop, Phone from Tablet', (tester) async {
      final raw = _text('b_text000001', style: {
        BlockSpacing.padding: {
          'desktop': {'top': 30, 'left': 24},
          'tablet': {'top': 12},
          'mobile': {'left': 0},
        },
      });
      final seen = <Size, EdgeInsets>{};
      for (final s in [_desktop, _tablet, _phone]) {
        await pump(tester, _parse([raw]), at: s);
        seen[s] = tester.renderObject<RenderFitPadding>(key('public-block-b_text000001-padding')).applied;
      }
      expect(seen[_desktop], const EdgeInsets.only(top: 30, left: 24));
      expect(seen[_tablet], const EdgeInsets.only(top: 12, left: 24));
      expect(seen[_phone], const EdgeInsets.only(top: 12), reason: 'left 0 on phones');
    });

    testWidgets('margin moves the block, padding moves the content inside it: independent', (tester) async {
      await pump(tester, _parse([
        _text('b_text000001', style: {
          'background': 'token:goldLight',
          BlockSpacing.padding: {'desktop': _sides(8, 8, 8, 8)},
          BlockSpacing.margin: {'desktop': {'left': 50, 'top': 12}},
        }),
      ]), spaced: false);
      final surface = tester.getRect(find.ancestor(of: find.text('Get in Touch'), matching: find.byWidgetPredicate((w) => w is Container && w.decoration != null)).first);
      final outer = tester.getRect(key('public-block-b_text000001-margin'));
      expect(surface.left - outer.left, 50, reason: 'margin outside the background');
      expect(surface.top - outer.top, 12);
      expect(r(tester, 'Get in Touch').left - surface.left, 8, reason: 'padding inside it, unchanged by the margin');
      expect(r(tester, 'Get in Touch').top - surface.top, 8);
    });

    testWidgets('a top margin is the space above the block: not added to Space above', (tester) async {
      await pump(tester, _parse([_text('b_text000001'), _text('b_text000002', heading: 'Second', body: 'More.', style: {BlockSpacing.margin: {'desktop': {'top': 10}}})]));
      expect(round(r(tester, 'Second').top - r(tester, 'Coimbatore').bottom), 10, reason: 'not 56 + 10');
      await pump(tester, _parse([_text('b_text000001'), _text('b_text000002', heading: 'Second', body: 'More.', style: {BlockSpacing.margin: {'desktop': {'top': 0}}})]));
      expect(round(r(tester, 'Second').top - r(tester, 'Coimbatore').bottom), 0, reason: 'zero: no space at all');
      await pump(tester, _parse([_text('b_text000001'), _text('b_text000002', heading: 'Second', body: 'More.')]));
      expect(round(r(tester, 'Second').top - r(tester, 'Coimbatore').bottom), 56, reason: 'unset: Space above as before');
    });

    testWidgets('narrow screens: long words and lines wrap, nothing overflows', (tester) async {
      final long = List.filled(20, 'Supercalifragilistic independence and concentration.').join(' ');
      await pump(tester, _parse([_text('b_text000001', body: long, style: {BlockSpacing.padding: {'desktop': _sides(16, 200, 16, 200)}})]), at: _narrow);
      expect(tester.takeException(), isNull);
      final body = tester.getRect(find.text(long));
      expect(body.left, greaterThanOrEqualTo(0));
      expect(body.right, lessThanOrEqualTo(_narrow.width));
      expect(body.width, greaterThan(_narrow.width / 3), reason: 'readable, not squeezed to nothing');
    });
  });

  group('inside a section', () {
    testWidgets('padding from the column’s edges; headings and paragraphs keep their spacing; the top margin replaces the gap', (tester) async {
      await pump(tester, _parse([
        _section([
          _text('b_text000001', style: {BlockSpacing.padding: {'desktop': {'left': 24, 'top': 0}}}),
          _text('b_text000002', heading: 'Phone', body: '+91 00000 00000', style: {BlockSpacing.margin: {'desktop': {'top': 6}}}),
          _text('b_text000003', heading: 'Email', body: 'hello@example.test'),
        ]),
      ]));
      final column = tester.getRect(key('public-block-column-c_left000001'));
      final first = box(tester, 'b_text000001');
      expect(first.left, column.left);
      expect(first.width, column.width, reason: 'never narrower than its column');
      expect(r(tester, 'Get in Touch').left - column.left, 24);
      expect(r(tester, 'Get in Touch').top, first.top, reason: 'top 0');
      expect(round(r(tester, 'NGGO Colony,').top - r(tester, '4/64, Richard Street,').bottom), 14, reason: 'paragraph spacing unchanged');
      expect(round(r(tester, 'Phone').top - r(tester, 'Coimbatore').bottom), 6, reason: 'its margin, not 32 + 6');
      expect(round(r(tester, 'Email').top - r(tester, '+91 00000 00000').bottom), 32, reason: 'unset: the section’s gap as before');
      expect(r(tester, 'Phone').left, column.left, reason: 'no side spacing: in place');
      expect(find.byType(FitPadding), findsNWidgets(2), reason: 'each block’s own, once; none for the third');
    });

    testWidgets('Buttons and Accreditations in a column: padding moves their content by exactly the value', (tester) async {
      Map<String, dynamic> buttons(Map<String, dynamic> style) => {
            'id': 'b_btns000001',
            'type': 'buttons',
            'v': 1,
            'buttons': [
              {'id': 'i_button00001', 'label': {'en': 'Visit us'}, 'target': '/contact', 'variant': 'primary'},
            ],
            if (style.isNotEmpty) 'style': style,
          };
      Map<String, dynamic> accreditations(Map<String, dynamic> style) => {
            'id': 'b_accred0001',
            'type': 'accreditations',
            'v': 1,
            'items': [
              {'id': 'i_accred0001', 'name': {'en': 'Synthetic Quality Mark', 'ta': ''}},
            ],
            if (style.isNotEmpty) 'style': style,
          };
      await pump(tester, _parse([_section([buttons(const {}), accreditations(const {})])]));
      final button = tester.getRect(key('public-block-button-i_button00001'));
      final card = tester.getRect(key('public-accreditation-i_accred0001'));
      final pad = {BlockSpacing.padding: {'desktop': _sides(10, 0, 0, 30)}};
      await pump(tester, _parse([_section([buttons(pad), accreditations(pad)])]));
      expect(tester.getRect(key('public-block-button-i_button00001')).topLeft - button.topLeft, const Offset(30, 10));
      expect(tester.getSize(key('public-block-button-i_button00001')), button.size, reason: 'the button keeps its size');
      final now = tester.getRect(key('public-accreditation-i_accred0001'));
      expect(now.left - card.left, 30);
      expect(now.right, lessThanOrEqualTo(tester.getRect(key('public-block-column-c_left000001')).right + 0.01), reason: 'inside its column');
      expect(tester.takeException(), isNull);
    });
  });

  group('every block type', () {
    testWidgets('side spacing measured from the content edges at the top level; nothing set, nothing moves', (tester) async {
      final samples = <Map<String, dynamic>>[
        _text('b_text000001'),
        {
          'id': 'b_btns000001',
          'type': 'buttons',
          'v': 1,
          'buttons': [
            {'id': 'i_button00001', 'label': {'en': 'Visit us'}, 'target': '/contact', 'variant': 'primary'},
          ],
        },
        {'id': 'b_note000001', 'type': 'notice', 'v': 1, 'title': {'en': 'Closed on Monday'}},
        {'id': 'b_divd000001', 'type': 'divider', 'v': 1},
      ];
      for (final raw in samples) {
        await pump(tester, _parse([raw]));
        final before = tester.getRect(key('public-block-${raw['id']}'));
        await pump(tester, _parse([{...raw, 'style': {BlockSpacing.padding: {'desktop': {'top': 4}}}}]));
        expect(tester.getRect(key('public-block-${raw['id']}')).width, before.width, reason: '${raw['id']}: top only changes no width');
        await pump(tester, _parse([{...raw, 'style': {BlockSpacing.margin: {'desktop': {'left': 16}}}}]));
        expect(tester.getRect(key('public-block-${raw['id']}-margin')).left, closeTo((1400 - (raw['type'] == 'notice' ? 760 : 960)) / 2, 0.5), reason: '${raw['id']}: from the content edge');
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('the editor’s canvas', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    testWidgets('lays blocks out exactly as the website: the outline takes no space; selecting moves nothing', (tester) async {
      final blocks = [
        _section([
          _text('b_text000001', style: {BlockSpacing.padding: {'desktop': {'top': 18, 'bottom': 0, 'left': 12}}}),
          _text('b_text000002', heading: 'Phone', body: 'Call us.', style: {BlockSpacing.margin: {'desktop': {'top': 8}}}),
        ]),
      ];
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Contact test'), slug: 'contact-test');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: created.id)),
      ));
      await tester.pumpAndSettle();

      // In the canvas: offsets inside the blocks.
      // In layout pixels (the canvas may draw a preview size scaled down).
      (double, double, double, double) measure() {
        final first = tester.getRect(key('public-block-b_text000001-padding'));
        final scale = first.width / tester.renderObject<RenderBox>(key('public-block-b_text000001-padding')).size.width;
        return (
          round((r(tester, 'Get in Touch').top - first.top) / scale),
          round((r(tester, 'Get in Touch').left - first.left) / scale),
          round((r(tester, 'Phone').top - r(tester, 'Coimbatore').bottom) / scale),
          round(first.height / scale),
        );
      }

      final canvas = measure();
      final heading = r(tester, 'Get in Touch');
      await tester.tap(key('website-canvas-block-b_text000001'));
      await tester.pumpAndSettle();
      expect(r(tester, 'Get in Touch'), heading, reason: 'selecting draws an outline and moves nothing');

      await pump(tester, _parse(blocks)); // the visitor preview and published page
      expect(measure(), canvas);
      expect(canvas.$1, 18);
      expect(canvas.$2, 12);
      expect(canvas.$3, 8, reason: 'its margin is the gap, in the canvas too');
    });
  });
}
