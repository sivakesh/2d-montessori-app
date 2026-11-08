// Photo gallery and Asymmetric gallery: what a draft may have and what a
// published page needs. A gallery with albums may be saved while its albums
// have no image visitors may see (with a note); publishing needs at least
// one such image (from albums or chosen by hand). Empty image slots stay in
// the draft, with their ids and settings, and are left out of the published
// page. Publishing doesn't change the saved draft. Synthetic test data only.
import 'dart:convert';
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
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
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
const _noImage = 'needs at least one image visitors may see';

Map<String, dynamic> _gallery(String type, {List<String> albums = const [], required List<Map<String, dynamic>> images}) => {
      'id': 'b_gal000001',
      'type': type,
      'v': 1,
      if (type == 'gallery') 'columns': '3',
      'images': images,
      if (albums.isNotEmpty) AlbumSource.albumIds: albums,
    };

/// An edited empty slot: no image, with a caption, an unknown field and
/// (Asymmetric gallery) a phone setting.
Map<String, dynamic> _editedSlot(String type) => {
      'id': 'i_slot000001',
      'mediaId': '',
      'caption': {'en': 'Sports day', 'ta': 'விளையாட்டு நாள்'},
      'futureItemKey': 'kept',
      if (type == 'asymmetric_gallery') 'hideMobile': true,
    };

Map<String, dynamic> _hand(String type, String id, String media) => {
      'id': id,
      'mediaId': media,
      'caption': {'en': 'Chosen $media', 'ta': 'தேர்வு'},
      if (type == 'asymmetric_gallery') 'mobileColSpan': '2',
    };

StructuredBlock _parse(Object? raw) => BlockRegistry.parse(Map<String, dynamic>.from(raw as Map)) as StructuredBlock;
List<String> _media(StructuredBlock b) => [for (final i in b.items('images')) i.string('mediaId')];
List<String> _ids(StructuredBlock b) => [for (final i in b.items('images')) i.id];

Map<String, dynamic> _nest(Map<String, dynamic> gallery) => {
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

StructuredBlock _nested(WebsiteBlock section) => (((section as StructuredBlock).columns('columns').single.blocks.single as StructuredBlock).columns('columns').single.blocks.single) as StructuredBlock;

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
  Future<void> save(String id) async => service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: await draft(id));
  Future<void> publish(String id) async => service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await draft(id));
  Future<List<Object?>> stored(String id) async => (await db.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks'] as List;
  Future<List<Object?>?> liveRaw(String id) async => (await db.collection(WebsiteCollections.livePages).doc(id).get()).data()?['blocks'] as List?;

  Future<Map<String, dynamic>> withAlbumImages(Map<String, dynamic> raw) async =>
      AlbumGalleries.update(_parse(raw), albums: await service.albums.list(requesterRole: 'admin'), library: await service.listMedia(requesterRole: 'admin')).block.toMap();

  for (final type in _types) {
    group(type, () {
      test('1, 3, 7. albums with no eligible image: the draft saves (albums kept on reopening); publishing is refused and writes nothing', () async {
        await seed();
        final notReady = await album('Not ready', ['m_draft', 'm_nocons']);
        final empty = await album('Empty', []);
        final raw = await withAlbumImages(_gallery(type, albums: [notReady.id, empty.id], images: [_editedSlot(type)]));
        final id = await pageWith([raw]);
        await save(id);
        final reopened = (await draft(id)).blocks!.single as StructuredBlock;
        expect(AlbumSource.albumsOf(reopened), [notReady.id, empty.id], reason: 'album choices kept, the empty one too');
        expect(BlockRegistry.blockProblems(reopened), isEmpty);

        final before = jsonEncode(await stored(id));
        await expectLater(publish(id), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', allOf(contains(_noImage), contains('published, with consent confirmed')))));
        expect(await liveRaw(id), isNull, reason: 'nothing published');
        expect(jsonEncode(await stored(id)), before, reason: 'the draft is untouched');
      });

      test('4, 6, 11. an eligible album image makes publishing succeed; removing it refuses publishing again', () async {
        await seed();
        final a = await album('Annual day', ['m_draft']);
        final id = await pageWith([_gallery(type, albums: [a.id], images: [])]);
        await expectLater(publish(id), throwsA(isA<WebsiteContentException>()));

        await db.collection(WebsiteCollections.media).doc('m_draft').update({'status': 'published'});
        await publish(id);
        final shown = _parse((await liveRaw(id))!.single);
        expect(_media(shown), ['m_draft']);
        expect(AlbumSource.itemAlbums(shown.items('images').single), [a.id], reason: 'its album mark is kept');
        expect(AlbumSource.albumsOf(shown), [a.id], reason: 'the album choice is published as it is');

        await db.collection(WebsiteCollections.media).doc('m_draft').update({'consentConfirmed': false});
        final published = jsonEncode(await liveRaw(id));
        await expectLater(publish(id), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains(_noImage))));
        expect(jsonEncode(await liveRaw(id)), published, reason: 'the published page stays as it was');
      });

      test('5. an image chosen by hand also makes publishing succeed', () async {
        await seed();
        final a = await album('Not ready', ['m_nocons']);
        final id = await pageWith([await withAlbumImages(_gallery(type, albums: [a.id], images: [_hand(type, 'i_hand000001', 'm_4')]))]);
        await publish(id);
        expect(_media(_parse((await liveRaw(id))!.single)), ['m_4']);
      });

      test('8, 9, 10, 11, 15. empty slots: kept in the draft with ids and settings, left out of the published page; the rest unchanged; the draft unchanged by publishing', () async {
        await seed();
        final a = await album('Annual day', ['m_1', 'm_2']);
        final raw = await withAlbumImages(_gallery(type, albums: [a.id], images: [
          _hand(type, 'i_hand000001', 'm_3'),
          _editedSlot(type),
          _hand(type, 'i_hand000002', 'm_4'),
          {'id': 'i_slot000002', 'mediaId': ''},
        ]));
        final id = await pageWith([raw]);
        await save(id);
        final before = jsonEncode(await stored(id));
        await publish(id);
        expect(jsonEncode(await stored(id)), before, reason: '15. publishing leaves the saved draft as it is');

        final kept = _parse((await stored(id)).single);
        expect(_ids(kept).take(4), ['i_hand000001', 'i_slot000001', 'i_hand000002', 'i_slot000002'], reason: '8. empty slots stay in the draft');
        final slot = Map<String, dynamic>.from(((Map<String, dynamic>.from((await stored(id)).single as Map))['images'] as List)[1] as Map);
        expect(slot['id'], 'i_slot000001');
        expect(slot['caption'], {'en': 'Sports day', 'ta': 'விளையாட்டு நாள்'});
        expect(slot['futureItemKey'], 'kept');
        if (type == 'asymmetric_gallery') expect(slot['hideMobile'], true);

        final shownRaw = Map<String, dynamic>.from((await liveRaw(id))!.single as Map);
        final shown = _parse(shownRaw);
        expect(_media(shown), ['m_3', 'm_4', 'm_1', 'm_2'], reason: '9. no empty slot published; 10. order kept');
        final draftItems = {for (final i in (Map<String, dynamic>.from((await stored(id)).single as Map)['images'] as List)) (i as Map)['id']: i};
        for (final i in shownRaw['images'] as List) {
          expect(i, draftItems[(i as Map)['id']], reason: '10, 11. each image published exactly as in the draft (id, settings, album marks)');
        }
        expect(shownRaw..remove('images'), Map<String, dynamic>.from((await stored(id)).single as Map)..remove('images'), reason: 'the gallery’s own settings and albums unchanged');
      });

      test('13. nested in a section’s Columns / Row: the draft saves, publishing is refused; with images, its empty slots are left out', () async {
        await seed();
        final notReady = await album('Not ready', ['m_draft']);
        final id = await pageWith([_nest(await withAlbumImages(_gallery(type, albums: [notReady.id], images: [_editedSlot(type)])))]);
        await save(id);
        await expectLater(publish(id), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', allOf(contains('Columns / Row), column 1, block 1 ('), contains(_noImage)))));

        final a = await album('Annual day', ['m_1']);
        final id2 = await pageWith([_nest(await withAlbumImages(_gallery(type, albums: [a.id], images: [_editedSlot(type), _hand(type, 'i_hand000001', 'm_4')])))]);
        await save(id2);
        final before = jsonEncode(await stored(id2));
        await publish(id2);
        expect(_media(_nested(BlockRegistry.parseList((await liveRaw(id2))!).single)), ['m_4', 'm_1']);
        expect(_media(_nested(BlockRegistry.parseList(await stored(id2)).single)), ['', 'm_4', 'm_1']);
        expect(jsonEncode(await stored(id2)), before);
      });

      test('14. a gallery chosen by hand, with no empty slot: published exactly as before', () async {
        await seed();
        final raw = _gallery(type, images: [_hand(type, 'i_hand000001', 'm_1'), _hand(type, 'i_hand000002', 'm_2')])
          ..['heading'] = {'en': 'Our days', 'ta': 'எங்கள் நாட்கள்'}
          ..['futureBlockKey'] = 'kept';
        final id = await pageWith([raw]);
        await publish(id);
        expect((await liveRaw(id))!.single, raw);
        expect((await stored(id)).single, raw);
        // Without albums and without an image, it can't even be saved, as before.
        final id2 = await pageWith([_gallery(type, images: [_editedSlot(type)])]);
        await expectLater(save(id2), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('choose an image'))));
      });

      test('built-in pages: the same draft and publishing rules', () async {
        await seed();
        final notReady = await album('Not ready', ['m_nocons']);
        final blocks = BlockRegistry.parseList([await withAlbumImages(_gallery(type, albums: [notReady.id], images: [_editedSlot(type)]))]);
        await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.gallery, blocks: blocks);
        await expectLater(service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.gallery, blocks: blocks), throwsA(isA<WebsiteContentException>()));
        expect((await db.collection(WebsiteCollections.livePages).doc(BuiltInPage.gallery.id).get()).data()?['blocks'], isNull);

        final withImage = BlockRegistry.parseList([await withAlbumImages(_gallery(type, albums: [notReady.id], images: [_editedSlot(type), _hand(type, 'i_hand000001', 'm_2')]))]);
        await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.gallery, blocks: withImage);
        final page = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.gallery);
        expect(_media(page.live!.single as StructuredBlock), ['m_2']);
        expect(_media(page.draft!.single as StructuredBlock), ['', 'm_2']);
      });
    });
  }

  test('an Asymmetric gallery whose image order would move without its empty slot keeps the slot (it still shows nothing)', () {
    // "Third" has its own desktop position; "Second" takes its place in the
    // list. Without the slot before it, the two would swap.
    final raw = _gallery('asymmetric_gallery', images: [
      {'id': 'i_slot000001', 'mediaId': ''},
      {'id': 'i_a00000001', 'mediaId': 'm_2'},
      {'id': 'i_b00000001', 'mediaId': 'm_3', 'order': 1},
    ]);
    final published = BlockRegistry.forVisitors([_parse(raw)]).single as StructuredBlock;
    expect(_media(published), ['', 'm_2', 'm_3']);
    // With no positions set, the slot is left out.
    final plain = BlockRegistry.forVisitors([_parse(_gallery('asymmetric_gallery', images: [raw['images'][0], raw['images'][1]]))]).single as StructuredBlock;
    expect(_media(plain), ['m_2']);
  });

  // ------------------------------------------------------------ editor
  group('in the editor', () {
    Future<void> open(WidgetTester tester, String id) async {
      tester.view.physicalSize = const Size(1400, 2600);
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

    const p = 'website-block-b_gal000001';
    for (final type in _types) {
      testWidgets('$type 2. albums with no eligible image: a note that doesn’t stop saving; publishing is refused with the reason', (tester) async {
        await seed();
        final a = await album('Not ready', ['m_draft', 'm_nocons']);
        final id = await pageWith([_gallery(type, albums: [a.id], images: [])]);
        await open(tester, id);
        expect(key('$p-problems'), findsNothing, reason: 'not a problem');
        expect(find.textContaining('gallery(ies) with albums have no image visitors may see yet'), findsOneWidget, reason: 'the page’s notes');
        await tap(tester, key('$p-edit'));
        expect(key('$p-albums-no-images'), findsOneWidget);
        expect(find.textContaining('You can save the draft; before it can be published'), findsOneWidget);

        await tap(tester, key('website-custom-save-draft'));
        expect(AlbumSource.albumsOf(_parse((await stored(id)).single)), [a.id], reason: 'saved');

        await tap(tester, key('website-custom-publish'));
        if (key('website-custom-publish-confirm').evaluate().isNotEmpty) await tap(tester, key('website-custom-publish-confirm'));
        // The "Draft saved" message goes first.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.textContaining(_noImage), findsWidgets, reason: 'the reason is shown');
        expect(await liveRaw(id), isNull);
        expect(tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.single, isA<StructuredBlock>());
      });
    }
  });
}
