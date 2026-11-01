// Photo gallery in the visual editor, as an administrator finds and uses
// it: listed (with its description) under Add block, reached from a School
// gallery block (which stays), images chosen several at a time without
// repeats, reordered, removed, saved as a draft and reopened. Gallery
// rendering, settings and publishing are covered by
// website_builder_layout_test.dart. Synthetic test data only.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _media = ['m_a', 'm_b', 'm_c', 'm_d'];

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    for (final id in _media) {
      await firestore.collection(WebsiteCollections.media).doc(id).set({
        'url': 'https://example.test/$id.jpg',
        'storagePath': 'website_media/$id/d.jpg',
        'status': 'published',
        'consentConfirmed': true,
        'alt': {'en': 'Alt $id', 'ta': ''},
        'caption': {'en': '', 'ta': ''},
      });
    }
  });

  Future<String> page(List<Object?> blocks) async {
    final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Scratch'), slug: 'scratch');
    await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'sections': [], 'schemaVersion': 2, 'blocks': blocks});
    return created.id;
  }

  Future<void> open(WidgetTester tester, String id) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
      child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: id)),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String k) => find.byKey(Key(k));

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;

  StructuredBlock galleryIn(WidgetTester tester) => BlockRegistry.flatten(blocks(tester)).whereType<StructuredBlock>().firstWhere((b) => b.type == 'gallery');

  List<String> chosen(StructuredBlock g) => [for (final i in g.items('images')) i.string('mediaId')];

  Future<void> addImages(WidgetTester tester, String galleryId, List<String> ids) async {
    await tap(tester, key('website-block-$galleryId-images-add-images'));
    for (final id in ids) {
      await tester.tap(key('website-choose-many-$id'));
      await tester.pump();
    }
    await tester.tap(key('website-choose-many-add'));
    await tester.pumpAndSettle();
  }

  testWidgets('Add block lists Photo gallery with its description, next to School gallery; no block type shows a lock', (tester) async {
    await open(tester, await page([]));
    await tap(tester, key('website-blocks-add'));
    expect(key('website-blocks-add-gallery'), findsOneWidget);
    expect(find.descendant(of: key('website-blocks-add-gallery'), matching: find.text('Photo gallery')), findsOneWidget);
    expect(find.descendant(of: key('website-blocks-add-gallery'), matching: find.text('Photographs you choose, in your order')), findsOneWidget);
    expect(find.descendant(of: key('website-blocks-add-gallery_feed'), matching: find.textContaining('to choose photographs, use Photo gallery')), findsOneWidget);
    for (final d in BlockRegistry.all) {
      expect(find.descendant(of: key('website-blocks-add-${d.type}'), matching: find.byIcon(Icons.lock_outline)), findsNothing, reason: d.type);
    }
    await tester.tap(key('website-blocks-add-gallery'));
    await tester.pumpAndSettle();
    expect(blocks(tester).single.type, 'gallery');
    expect(key('website-block-${blocks(tester).single.id}-images-add-images'), findsOneWidget, reason: 'its properties offer Add images');
  });

  testWidgets('a School gallery points to Photo gallery and adds one after it, in its column; the School gallery stays', (tester) async {
    await open(tester, await page([
      {
        'id': 'b_section0001', 'type': 'section', 'v': 1, 'layout': '1',
        'columns': [
          {'id': 'c_column0001', 'blocks': [{'id': 'b_feed000001', 'type': 'gallery_feed', 'v': 1}]},
        ],
      },
    ]));
    await tap(tester, key('website-block-b_feed000001-select'));
    expect(key('website-inspector-gallery-feed-hint'), findsOneWidget);
    expect(find.textContaining('shows every published gallery photograph automatically'), findsOneWidget);

    await tap(tester, key('website-inspector-add-photo-gallery'));
    final column = (blocks(tester).single as StructuredBlock).columns('columns').single.blocks;
    expect([for (final b in column) b.type], ['gallery_feed', 'gallery']);
    expect(column.first.id, 'b_feed000001', reason: 'the School gallery is kept, with its id');
    expect(key('website-inspector-gallery-feed-hint'), findsNothing, reason: 'the new Photo gallery is selected');
    expect(key('website-block-${column[1].id}-images-add-images'), findsOneWidget);
  });

  testWidgets('choose three images at once, in order; no repeats; reorder and remove; saved as a draft and reopened', (tester) async {
    final id = await page([]);
    await open(tester, id);
    await tap(tester, key('website-blocks-add'));
    await tester.tap(key('website-blocks-add-gallery'));
    await tester.pumpAndSettle();
    final galleryId = blocks(tester).single.id;

    await addImages(tester, galleryId, ['m_c', 'm_a', 'm_b']);
    expect(chosen(galleryIn(tester)), ['m_c', 'm_a', 'm_b'], reason: 'in the order ticked');

    // Images already in the gallery can't be chosen again.
    await tap(tester, key('website-block-$galleryId-images-add-images'));
    for (final m in ['m_a', 'm_b', 'm_c']) {
      expect(tester.widget<CheckboxListTile>(key('website-choose-many-$m')).onChanged, isNull, reason: m);
    }
    expect(find.text('Already in this gallery'), findsNWidgets(3));
    await tester.tap(key('website-choose-many-m_d'));
    await tester.pump();
    await tester.tap(key('website-choose-many-add'));
    await tester.pumpAndSettle();
    expect(chosen(galleryIn(tester)), ['m_c', 'm_a', 'm_b', 'm_d']);

    final itemIds = [for (final i in galleryIn(tester).items('images')) i.id];
    await tap(tester, key('website-block-$galleryId-images-item-${itemIds[2]}-up'));
    await tap(tester, key('website-block-$galleryId-images-item-${itemIds[3]}-remove'));
    expect(chosen(galleryIn(tester)), ['m_c', 'm_b', 'm_a']);
    expect(find.descendant(of: key('website-block-$galleryId-images-item-${itemIds[0]}'), matching: find.byType(Image)).evaluate().isNotEmpty ||
        find.textContaining('Alt m_c').evaluate().isNotEmpty, isTrue, reason: 'each chosen image is shown with its thumbnail or alt text');

    await tap(tester, key('website-custom-save-draft'));
    final stored = (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!;
    expect([for (final i in (stored['blocks'] as List).single['images'] as List) i['mediaId']], ['m_c', 'm_b', 'm_a']);
    expect((await firestore.collection(WebsiteCollections.livePages).doc(id).get()).exists, isFalse, reason: 'nothing published');

    await open(tester, id);
    expect(chosen(galleryIn(tester)), ['m_c', 'm_b', 'm_a'], reason: 'the order survives a reload');
    expect([for (final i in galleryIn(tester).items('images')) i.id], [itemIds[0], itemIds[2], itemIds[1]], reason: 'item ids kept, in the new order');
  });
}
