// Regression: a Photo gallery or Asymmetric gallery that takes images from
// albums must not need its empty starting image slot filled. A gallery is
// checked on what it shows: valid while it has an image (chosen by hand, or
// from its albums); an empty slot beside images is unused. With nothing to
// show it can't be published (a draft with albums may wait for images), and
// publishing's checks (published, consent, files, limits) are unchanged.
// Synthetic test data only.
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/album_galleries.dart';
import 'package:montessori_app/modules/admin/website/data/website_albums_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/album_source.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';

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

const _types = ['gallery', 'asymmetric_gallery'];
const _blankItem = {'id': 'i_blank00001', 'mediaId': ''};

/// The gallery `b_gal000001` of [type] as a new one starts: one empty slot.
Map<String, dynamic> _fresh(String type, {List<String> albums = const [], List<Map<String, dynamic>>? images}) => {
      'id': 'b_gal000001',
      'type': type,
      'v': 1,
      if (type == 'gallery') 'columns': '3',
      'images': images ?? [Map<String, dynamic>.from(_blankItem)],
      if (albums.isNotEmpty) AlbumSource.albumIds: albums,
    };

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parse(raw) as StructuredBlock;
List<String> _media(StructuredBlock b) => [for (final i in b.items('images')) i.string('mediaId')];

void main() {
  Finder key(String k) => find.byKey(Key(k));
  late FakeFirebaseFirestore db;
  late WebsiteContentAdminService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
  });

  Future<void> media(String id, {String status = 'published', bool consent = true}) => db.collection(WebsiteCollections.media).doc(id).set({
        'url': 'https://storage.example.test/$id.jpg',
        'storagePath': 'website_media/$id/x.jpg',
        'status': status,
        'consentConfirmed': consent,
        'alt': {'en': 'Photo $id', 'ta': 'படம்'},
        'inGallery': true,
      });

  Future<void> seed() async {
    for (var i = 1; i <= 4; i++) {
      await media('m_$i');
    }
    await media('m_draft', status: 'draft');
    await media('m_nocons', consent: false);
  }

  Future<WebsiteAlbum> album(String name, List<String> ids) async {
    final a = await service.albums.create(requesterRole: 'admin', actor: _admin, name: name);
    if (ids.isNotEmpty) await service.albums.addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: ids);
    return a;
  }

  var pages = 0;
  Future<String> pageWith(List<Object?> blocks) async {
    final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Photos', ta: 'புகைப்படங்கள்'), slug: 'photos-${pages++}');
    await db.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
    return created.id;
  }

  Future<CustomPage> draft(String id) async => (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
  Future<void> publish(String id) async => service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await draft(id));
  Future<List<WebsiteBlock>> live(String id) async => BlockRegistry.parseList((await db.collection(WebsiteCollections.livePages).doc(id).get()).data()!['blocks']);
  Future<List<Object?>> storedBlocks(String id) async => (await db.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks'] as List;

  /// [raw] brought up to date from the stored albums, as the editor and
  /// publishing do.
  Future<Map<String, dynamic>> withAlbumImages(Map<String, dynamic> raw) async =>
      AlbumGalleries.update(_parse(raw), albums: await service.albums.list(requesterRole: 'admin'), library: await service.listMedia(requesterRole: 'admin')).block.toMap();

  for (final type in _types) {
    group(type, () {
      test('1. a new gallery: its empty slot, or no slot, still needs an image', () {
        expect(BlockRegistry.blockProblems(BlockRegistry.create(BlockRegistry.definition(type)!)), ['Image 1: choose an image']);
        expect(BlockRegistry.blockProblems(_parse(_fresh(type, images: []))), ['add at least 1 image']);
      });

      test('2–3. one album, several albums: no empty-slot problem; the slot is unused', () async {
        await seed();
        final a = await album('Annual day', ['m_1', 'm_2']);
        final b = await album('Garden', ['m_2', 'm_3']);
        for (final albums in [
          [a.id],
          [a.id, b.id],
        ]) {
          final g = _parse(await withAlbumImages(_fresh(type, albums: albums)));
          expect(_media(g).where((m) => m.isNotEmpty), albums.length == 1 ? ['m_1', 'm_2'] : ['m_1', 'm_2', 'm_3']);
          expect(BlockRegistry.blockProblems(g), isEmpty, reason: '${albums.length} album(s)');
        }
      });

      test('4–5. albums and images by hand together; an empty slot beside them: save and publish succeed, visitors get the images', () async {
        await seed();
        final a = await album('Annual day', ['m_1']);
        final raw = await withAlbumImages(_fresh(type, albums: [a.id], images: [
          {'id': 'i_hand00001', 'mediaId': 'm_4', 'caption': {'en': 'By hand', 'ta': 'கையால்'}},
          {'id': 'i_blank00001', 'mediaId': '', 'caption': {'en': 'To do'}},
        ]));
        final id = await pageWith([raw]);
        final page = await draft(id);
        await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page);
        await publish(id);
        final shown = (await live(id)).single as StructuredBlock;
        expect(_media(shown), ['m_4', 'm_1'], reason: 'kept in order; the empty slot is left out of the published page');
        expect(_media(_parse((await storedBlocks(id)).single as Map<String, dynamic>)), ['m_4', '', 'm_1'], reason: 'the draft keeps it (it was edited)');
        expect(shown.items('images').first.text('caption').ta, 'கையால்');
      });

      test('6. albums with no image visitors may see, and none by hand: the draft saves, publishing is refused', () async {
        await seed();
        final a = await album('Not ready', ['m_draft', 'm_nocons']);
        final raw = await withAlbumImages(_fresh(type, albums: [a.id]));
        expect(BlockRegistry.blockProblems(_parse(raw)), isEmpty);
        expect(AlbumSource.imageWarning(_parse(raw)), contains('albums have no image visitors may see yet'));
        final id = await pageWith([raw]);
        await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: await draft(id));
        await expectLater(publish(id), throwsA(isA<WebsiteContentException>()));
        expect((await db.collection(WebsiteCollections.livePages).doc(id).get()).exists, isFalse);
      });

      test('7–8. albums removed: images by hand still work; with none left, publishing is refused', () async {
        await seed();
        final a = await album('Annual day', ['m_1']);
        final withHand = await withAlbumImages(_fresh(type, albums: [a.id], images: [{'id': 'i_hand00001', 'mediaId': 'm_4'}]));
        final noAlbums = await withAlbumImages({..._parse(withHand).withValue(AlbumSource.albumIds, const <String>[]).toMap()});
        expect(_media(_parse(noAlbums)), ['m_4']);
        final id = await pageWith([noAlbums]);
        await publish(id);
        expect(_media((await live(id)).single as StructuredBlock), ['m_4']);

        final nothing = await withAlbumImages(_parse(await withAlbumImages(_fresh(type, albums: [a.id], images: []))).withValue(AlbumSource.albumIds, const <String>[]).toMap());
        expect(BlockRegistry.blockProblems(_parse(nothing)), ['add at least 1 image']);
        final id2 = await pageWith([nothing]);
        await expectLater(publish(id2), throwsA(isA<WebsiteContentException>()));
      });

      test('10. nested in a section’s Columns / Row: the same', () async {
        await seed();
        final a = await album('Annual day', ['m_1']);
        Map<String, dynamic> nest(Map<String, dynamic> gallery) => {
              'id': 'b_sec00001',
              'type': 'section',
              'v': 1,
              'layout': '1',
              'columns': [
                {
                  'id': 'c_col00000',
                  'blocks': [
                    {'id': 'b_row00001', 'type': 'row', 'v': 1, 'layout': '1', 'columns': [{'id': 'c_r0', 'blocks': [gallery]}]},
                  ],
                },
              ],
            };
        final ok = BlockRegistry.parseList([nest(await withAlbumImages(_fresh(type, albums: [a.id])))]);
        expect(BlockRegistry.validate(ok), isEmpty);
        final updated = AlbumGalleries.updateAll(BlockRegistry.parseList([nest(_fresh(type, albums: [a.id]))]), albums: await service.albums.list(requesterRole: 'admin'), library: await service.listMedia(requesterRole: 'admin'));
        expect(BlockRegistry.validate(updated), isEmpty, reason: 'updated where it is');
        final empty = BlockRegistry.parseList([nest(_fresh(type, albums: [(await album('Empty', [])).id]))]);
        expect(BlockRegistry.validate(empty), isEmpty, reason: 'a draft may wait for album images');
        expect(BlockRegistry.publishProblems(empty).single, contains('Columns / Row), column 1, block 1 ('));
        final id = await pageWith([ok.single.toMap()]);
        await publish(id);
        expect(await live(id), hasLength(1));
      });

      test('11. galleries chosen by hand: stored exactly as before; an empty slot beside images is no longer an error', () {
        final old = _fresh(type, images: [
          {'id': 'i_a00000001', 'mediaId': 'm_1', 'caption': {'en': 'Art', 'ta': 'கலை'}, 'futureKey': 1},
          {'id': 'i_b00000001', 'mediaId': 'm_2'},
        ])
          ..['heading'] = {'en': 'Our days', 'ta': 'எங்கள் நாட்கள்'}
          ..['futureBlockKey'] = 'kept';
        expect(_parse(old).toMap(), old);
        expect(BlockRegistry.blockProblems(_parse(old)), isEmpty);
        final withSlot = _fresh(type, images: [...old['images'] as List<Map<String, dynamic>>, Map<String, dynamic>.from(_blankItem)]);
        expect(BlockRegistry.blockProblems(_parse(withSlot)), isEmpty);
        expect(BlockRegistry.blockProblems(_parse(_fresh(type, images: [Map<String, dynamic>.from(_blankItem), {'id': 'i_c', 'mediaId': ''}]))), ['Image 1: choose an image', 'Image 2: choose an image']);
      });
    });
  }

  // ------------------------------------------------------------ editor
  group('in the editor', () {
    Future<void> open(WidgetTester tester, String id, {Size size = const Size(1400, 2600)}) async {
      tester.view.physicalSize = size;
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

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    StructuredBlock gallery(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.single as StructuredBlock;
    const p = 'website-block-b_gal000001';

    for (final type in _types) {
      testWidgets('$type 2, 9, 12: choosing an album leaves no empty slot to fill; save, reopen and publish; every preview size', (tester) async {
        await seed();
        final a = await album('Annual day', ['m_1', 'm_2']);
        final id = await pageWith([_fresh(type)]);
        await open(tester, id);
        expect(key('$p-problems'), findsOneWidget, reason: 'a new gallery still needs an image');
        await tap(tester, key('$p-edit'));
        expect(find.textContaining('One empty image slot isn’t used yet'), findsOneWidget);

        await tap(tester, key('$p-albums-add'));
        await tap(tester, key('website-album-picker-${a.id}'));
        await tap(tester, key('website-album-picker-done'));
        expect(_media(gallery(tester)), ['m_1', 'm_2'], reason: 'the untouched empty slot is gone');
        expect(key('$p-problems'), findsNothing);
        expect(find.textContaining('choose an image'), findsNothing);
        expect(key('website-inspector-problems'), findsNothing);

        for (final preview in ['tablet', 'mobile', 'desktop']) {
          await tap(tester, key('website-custom-preview-$preview'));
          expect(key('$p-problems'), findsNothing, reason: preview);
          expect(tester.takeException(), isNull, reason: preview);
        }

        await tap(tester, key('website-custom-save-draft'));
        final stored = (await storedBlocks(id)).single as Map;
        expect([for (final i in stored['images'] as List) (i as Map)['mediaId']], ['m_1', 'm_2'], reason: 'saved without an empty slot');
        await open(tester, id);
        expect(_media(gallery(tester)), ['m_1', 'm_2'], reason: 'reopened: no empty slot recreated');
        expect(key('$p-problems'), findsNothing);
        await tap(tester, key('website-custom-publish'));
        if (key('website-custom-publish-confirm').evaluate().isNotEmpty) await tap(tester, key('website-custom-publish-confirm'));
        expect(_media((await live(id)).single as StructuredBlock), ['m_1', 'm_2']);
      });
    }

    testWidgets('an edited empty slot is kept when albums are chosen (not silently removed), and doesn’t block the gallery', (tester) async {
      await seed();
      final a = await album('Annual day', ['m_1']);
      final id = await pageWith([_fresh('gallery', images: [{'id': 'i_blank00001', 'mediaId': '', 'caption': {'en': 'Later'}}])]);
      await open(tester, id);
      await tap(tester, key('$p-edit'));
      await tap(tester, key('$p-albums-add'));
      await tap(tester, key('website-album-picker-${a.id}'));
      await tap(tester, key('website-album-picker-done'));
      expect(_media(gallery(tester)), ['', 'm_1']);
      expect(key('$p-problems'), findsNothing);
      expect(find.textContaining('One empty image slot isn’t used: choose an image there, or remove it.'), findsOneWidget);
    });
  });
}
