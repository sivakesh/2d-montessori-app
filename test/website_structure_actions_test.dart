// The structure panel's block rows: Edit, Move up, Move down and a "More
// actions" menu (Duplicate, Hide/Show, Move to column…, Save as template,
// Delete), so a row never wraps its controls, even nested in a four-column
// section in a narrow panel; a tap on the row selects it and never lands
// on an action; the controls' targets don't overlap; each menu action is
// named and does exactly one thing. Synthetic test data only.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';

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

Map<String, dynamic> _text(String id) => {'id': id, 'type': 'text', 'v': 1, 'heading': {'en': 'Heading $id', 'ta': ''}, 'body': {'en': 'Words.', 'ta': ''}};

/// A four-column section `b_sec00001`, two text blocks per column
/// (`b_c<i>t<j>0000`), a top-level text and an unsupported block.
List<Map<String, dynamic>> _page() => [
      {
        'id': 'b_sec00001',
        'type': 'section',
        'v': 1,
        'layout': '1:1:1:1',
        'name': {'en': 'Four columns', 'ta': ''},
        'columns': [
          for (var i = 0; i < 4; i++)
            {
              'id': 'c_col0000$i',
              'blocks': [for (var j = 0; j < 2; j++) _text('b_c${i}t${j}0000')],
            },
        ],
      },
      _text('b_loose0001'),
      {'id': 'b_future01', 'type': 'carousel', 'v': 3},
    ];

void main() {
  Finder key(String k) => find.byKey(Key(k));
  late FakeFirebaseFirestore db;
  late WebsiteContentAdminService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
  });

  Future<void> open(WidgetTester tester, {Size size = const Size(1400, 2400), bool structure = false}) async {
    final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Rows'), slug: 'rows');
    await db.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': _page()});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
      child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: created.id)),
    ));
    await tester.pumpAndSettle();
    if (structure) {
      await tester.tap(key('website-editor-toggle-structure'));
      await tester.pumpAndSettle();
    }
  }

  List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;
  List<String> order(WidgetTester tester) => [
        for (final b in blocks(tester)) ...[b.id, if (b is StructuredBlock && b.type == 'section') for (final c in b.columns('columns')) for (final x in c.blocks) x.id],
      ];

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  const rows = ['b_sec00001', 'b_c3t10000', 'b_c0t00000', 'b_loose0001'];

  for (final (name, size, structure) in [('wide window', const Size(1400, 2400), false), ('medium window, structure panel open', const Size(920, 2400), true)]) {
    testWidgets('$name: one line of controls per row, never overlapping, nested in four columns too', (tester) async {
      await open(tester, size: size, structure: structure);
      expect(tester.takeException(), isNull);
      for (final id in rows) {
        final controls = [for (final a in ['edit', 'up', 'down', 'more']) tester.getRect(key('website-block-$id-$a'))];
        expect(controls.map((r) => r.center.dy.round()).toSet(), hasLength(1), reason: '$id: one line');
        for (var i = 1; i < controls.length; i++) {
          expect(controls[i].left - controls[i - 1].right, greaterThanOrEqualTo(4), reason: '$id: a gap between targets');
        }
        expect(controls.every((r) => r.height >= 36 && r.width >= 36), isTrue, reason: '$id: targets of at least 36 px');
        final card = tester.getRect(key('website-block-$id'));
        expect(controls.every((r) => r.right <= card.right && r.left >= card.left), isTrue, reason: '$id: inside its row');
        for (final hidden in ['duplicate', 'visibility', 'delete', 'save-template']) {
          expect(key('website-block-$id-$hidden'), findsNothing, reason: '$id: $hidden is in the menu');
        }
      }
    });
  }

  testWidgets('a tap anywhere on a row’s text selects it and does nothing else', (tester) async {
    await open(tester);
    final before = order(tester);
    for (final id in rows) {
      final card = tester.getRect(key('website-block-$id'));
      final controls = tester.getRect(key('website-block-$id-up'));
      // The middle of the row, and just above its controls: text, never a button.
      for (final at in [Offset(card.center.dx, card.top + (controls.top - card.top) / 2), Offset(card.left + 40, card.top + 14)]) {
        await tester.ensureVisible(key('website-block-$id'));
        await tester.pumpAndSettle();
        await tester.tapAt(at);
        await tester.pumpAndSettle();
        expect(order(tester), before, reason: '$id: nothing moved, copied or removed');
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.getRect(key('website-block-$id')).top, card.top, reason: '$id: rows keep their place');
      }
    }
  });

  testWidgets('More actions: named, labelled, each doing exactly one thing; Delete still asks', (tester) async {
    await open(tester);
    const id = 'b_c1t00000';
    final more = tester.widget<PopupMenuButton<String>>(key('website-block-$id-more'));
    expect(more.tooltip, contains('Text'), reason: 'announced with the block it acts on');

    await tap(tester, key('website-block-$id-more'));
    for (final label in ['Duplicate', 'Hide from visitors', 'Move to column 1', 'Move to column 3', 'Move to column 4', 'Save as template', 'Delete…']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(key('website-block-$id-to-column-1'), findsNothing, reason: 'not its own column');
    await tester.tap(key('website-block-$id-duplicate'));
    await tester.pumpAndSettle();
    final cols = (blocks(tester).first as StructuredBlock).columns('columns');
    expect(cols[1].blocks, hasLength(3), reason: 'one copy');
    expect(cols.fold<int>(0, (n, c) => n + c.blocks.length), 9, reason: 'nothing else changed');

    await tap(tester, key('website-block-$id-more'));
    await tester.tap(key('website-block-$id-to-column-3'));
    await tester.pumpAndSettle();
    final moved = (blocks(tester).first as StructuredBlock).columns('columns');
    expect(moved[3].blocks.last.id, id);
    expect(moved[1].blocks, hasLength(2));

    await tap(tester, key('website-block-$id-more'));
    await tester.tap(key('website-block-$id-visibility'));
    await tester.pumpAndSettle();
    expect(key('website-block-$id-hidden'), findsOneWidget);
    await tap(tester, key('website-block-$id-more'));
    expect(find.text('Show to visitors'), findsOneWidget);
    await tester.tap(key('website-block-$id-delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'Delete asks first');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(moved[3].blocks.last.id, (blocks(tester).first as StructuredBlock).columns('columns')[3].blocks.last.id, reason: 'Cancel keeps it');
  });

  testWidgets('an unsupported block offers only Delete; top-level rows have no column moves', (tester) async {
    await open(tester);
    await tap(tester, key('website-block-b_future01-more'));
    expect(key('website-block-b_future01-delete'), findsOneWidget);
    for (final a in ['duplicate', 'visibility', 'save-template']) {
      expect(key('website-block-b_future01-$a'), findsNothing, reason: a);
    }
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await tap(tester, key('website-block-b_loose0001-more'));
    expect(find.textContaining('Move to column'), findsNothing);
    expect(key('website-block-b_loose0001-save-template'), findsOneWidget);
  });
}
