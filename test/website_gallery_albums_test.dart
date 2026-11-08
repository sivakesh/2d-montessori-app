// Albums as the image source of the Photo gallery and the Asymmetric
// gallery (media library phase 2). A gallery lists its albums; their
// images become ordinary gallery images marked with the albums they came
// from, so every per-image setting works for them. They are brought up to
// date in the editor and when the page is published, keeping only images
// visitors may see; visitors never read an album. Images chosen by hand are
// never changed. Synthetic test data only.
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
import 'package:montessori_app/modules/public_website/content/blocks/field_spec.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
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

/// A library image: published with consent unless set otherwise.
WebsiteMedia _m(String id, {WebsiteMediaStatus status = WebsiteMediaStatus.published, bool consent = true, String url = 'https://storage.example.test/x.jpg'}) =>
    WebsiteMedia(id: id, url: url, storagePath: 'website_media/$id/x.jpg', status: status, consentConfirmed: consent, alt: LocalizedText(en: 'Photo $id'));

WebsiteAlbum _album(String id, List<String> media, {String name = ''}) => WebsiteAlbum(id: id, schoolId: 'default_school', name: name.isEmpty ? 'Album $id' : name, mediaIds: media);

/// A gallery of [type] ([raw] values on top), parsed.
StructuredBlock _gallery({String type = 'gallery', List<Map<String, dynamic>> images = const [], List<String> albums = const [], Map<String, dynamic> raw = const {}}) =>
    BlockRegistry.parse({'id': 'b_gal000001', 'type': type, 'v': 1, 'images': images, if (albums.isNotEmpty) AlbumSource.albumIds: albums, ...raw}) as StructuredBlock;

Map<String, dynamic> _hand(String media, {String id = '', Map<String, dynamic> extra = const {}}) => {'id': id.isEmpty ? 'i_hand_$media' : id, 'mediaId': media, ...extra};

List<String> _media(StructuredBlock b) => [for (final i in b.items('images')) i.string('mediaId')];
List<String> _fromAlbums(StructuredBlock b) => [for (final i in b.items('images')) if (AlbumSource.fromAlbum(i)) i.string('mediaId')];

void main() {
  Finder key(String k) => find.byKey(Key(k));
  final library = [
    for (var i = 1; i <= 6; i++) _m('m_$i'),
    _m('m_draft', status: WebsiteMediaStatus.draft),
    _m('m_hidden', status: WebsiteMediaStatus.hidden),
    _m('m_nocons', consent: false),
    _m('m_nofile', url: ''),
  ];

  // ------------------------------------------------------------ model
  group('updating a gallery from its albums', () {
    for (final type in ['gallery', 'asymmetric_gallery']) {
      test('$type: one album: its images visitors may see, in album order, marked; the others counted with why', () {
        final albums = [_album('a1', ['m_2', 'm_draft', 'm_1', 'm_hidden', 'm_nocons', 'm_nofile', 'm_gone'])];
        final r = AlbumGalleries.update(_gallery(type: type, albums: ['a1']), albums: albums, library: library);
        expect(_media(r.block), ['m_2', 'm_1']);
        expect(r.block.items('images').every((i) => AlbumSource.itemAlbums(i).single == 'a1'), isTrue);
        expect(r.added, 2);
        expect(r.excluded, {
          'm_draft': AlbumImageExclusion.notPublished,
          'm_hidden': AlbumImageExclusion.hidden,
          'm_nocons': AlbumImageExclusion.noConsent,
          'm_nofile': AlbumImageExclusion.noFile,
          'm_gone': AlbumImageExclusion.notInLibrary,
        });
        expect(r.albums.single.included, 2);
        expect(r.albums.single.excludedCount, 5);
        expect(BlockRegistry.blockProblems(r.block), isEmpty);
      });
    }

    test('several albums: each image once, marked with every album it is in; first album first', () {
      final albums = [_album('a1', ['m_1', 'm_2']), _album('a2', ['m_2', 'm_3'])];
      final r = AlbumGalleries.update(_gallery(albums: ['a1', 'a2']), albums: albums, library: library);
      expect(_media(r.block), ['m_1', 'm_2', 'm_3']);
      expect([for (final i in r.block.items('images')) AlbumSource.itemAlbums(i)], [
        ['a1'],
        ['a1', 'a2'],
        ['a2'],
      ]);
      expect(r.albums.map((c) => c.included), [2, 2]);
    });

    test('images chosen by hand: never changed or moved; an album image already chosen isn’t added again', () {
      final g = _gallery(albums: ['a1'], images: [
        _hand('m_3', extra: {'caption': {'en': 'Our garden', 'ta': 'எங்கள் தோட்டம்'}, 'futureItemKey': 7}),
        _hand('m_9'), // not in the library: left to the existing checks
      ]);
      final r = AlbumGalleries.update(g, albums: [_album('a1', ['m_1', 'm_3'])], library: library);
      expect(_media(r.block), ['m_3', 'm_9', 'm_1']);
      expect(r.block.items('images').first.toMap((r.block.definition.field('images') as ItemsFieldSpec).itemFields), {
        'id': 'i_hand_m_3',
        'mediaId': 'm_3',
        'caption': {'en': 'Our garden', 'ta': 'எங்கள் தோட்டம்'},
        'futureItemKey': 7,
      }, reason: 'kept exactly, Tamil and unknown fields too');
      expect(r.albums.single.alsoChosen, 1);
      // Removing the album leaves the hand-chosen images.
      final off = AlbumGalleries.update(r.block.withValue(AlbumSource.albumIds, const <String>[]), albums: [_album('a1', ['m_1', 'm_3'])], library: library);
      expect(_media(off.block), ['m_3', 'm_9']);
      expect(off.removed, 1);
    });

    test('album changes: a new image is added at the end; a removed one leaves; the rest keep their place and settings', () {
      var albums = [_album('a1', ['m_1', 'm_2', 'm_3'])];
      var g = AlbumGalleries.update(_gallery(type: 'asymmetric_gallery', albums: ['a1']), albums: albums, library: library).block;
      // The editor reorders and sets per-image settings on album images.
      final items = g.items('images');
      g = g.withValue('images', [
        items[2].withValue('feature', true),
        items[0].withValue('caption', const LocalizedText(en: 'Painting', ta: 'ஓவியம்')),
        items[1],
      ]);
      albums = [_album('a1', ['m_1', 'm_3', 'm_4'])];
      final r = AlbumGalleries.update(g, albums: albums, library: library);
      expect(_media(r.block), ['m_3', 'm_1', 'm_4']);
      expect((r.added, r.removed), (1, 1));
      expect(r.block.items('images')[0].value<bool>('feature'), isTrue);
      expect(r.block.items('images')[1].text('caption').ta, 'ஓவியம்');
      expect(r.block.items('images')[0].id, items[2].id, reason: 'same item, same id');
      // Nothing changed: the same block.
      final again = AlbumGalleries.update(r.block, albums: albums, library: library);
      expect(again.changed, isFalse);
      expect(identical(again.block, r.block), isTrue);
    });

    test('images that stop being visible (unpublished, hidden, consent withdrawn, deleted) leave on the next update', () {
      final albums = [_album('a1', ['m_1', 'm_2', 'm_3', 'm_4'])];
      final g = AlbumGalleries.update(_gallery(albums: ['a1']), albums: albums, library: library).block;
      expect(_media(g), ['m_1', 'm_2', 'm_3', 'm_4']);
      final changed = [
        _m('m_1', status: WebsiteMediaStatus.draft),
        _m('m_2', status: WebsiteMediaStatus.hidden),
        _m('m_3', consent: false),
        // m_4 deleted
        ...library.skip(4),
      ];
      final r = AlbumGalleries.update(g, albums: albums, library: changed);
      expect(_media(r.block), isEmpty);
      expect(r.removed, 4);
      expect(BlockRegistry.blockProblems(r.block), isEmpty, reason: 'the draft can be saved');
      expect(AlbumSource.imageWarning(r.block), contains('albums have no image visitors may see yet'), reason: 'with a note');
      expect(BlockRegistry.publishProblems([r.block]).single, contains('needs at least one image visitors may see'), reason: 'publishing is refused');
      expect(BlockRegistry.blockProblems(_gallery()), ['add at least 1 image'], reason: 'no image and no album is');
    });

    test('a deleted album, or albums that can’t be read: its images stay (while visible) until it is removed', () {
      final albums = [_album('a1', ['m_1', 'm_2'])];
      final g = AlbumGalleries.update(_gallery(albums: ['a1']), albums: albums, library: library).block;
      final deleted = AlbumGalleries.update(g, albums: const [], library: library);
      expect(_media(deleted.block), ['m_1', 'm_2']);
      expect(deleted.albums.single.album, isNull);
      expect(deleted.albums.single.unavailable, isFalse);
      final unreadable = AlbumGalleries.update(g, albums: null, library: [...library.where((m) => m.id != 'm_2'), _m('m_2', consent: false)]);
      expect(_media(unreadable.block), ['m_1'], reason: 'kept, but never an image visitors may not see');
      expect(unreadable.albums.single.unavailable, isTrue);
      final removed = AlbumGalleries.update(g.withValue(AlbumSource.albumIds, const <String>[]), albums: const [], library: library);
      expect(_media(removed.block), isEmpty);
    });

    test('an album image the editor removes stays out; “include again” brings it back; never more than the gallery holds', () {
      final albums = [_album('a1', [for (var i = 1; i <= 6; i++) 'm_$i'])];
      final g = AlbumGalleries.update(_gallery(albums: ['a1']), albums: albums, library: library).block;
      final edited = g.withValue('images', g.items('images').where((i) => i.string('mediaId') != 'm_2').toList());
      final remembered = AlbumGalleries.rememberRemovals(g, edited);
      expect(AlbumSource.excludedOf(remembered), ['m_2']);
      final r = AlbumGalleries.update(remembered, albums: albums, library: library);
      expect(_media(r.block), isNot(contains('m_2')));
      expect(r.excluded['m_2'], AlbumImageExclusion.leftOut);
      final back = AlbumGalleries.update(remembered.withValue(AlbumSource.excludedKey, const <String>[]), albums: albums, library: library);
      expect(_media(back.block).last, 'm_2');

      // An Asymmetric gallery holds 12.
      final many = [for (var i = 0; i < 14; i++) _m('m_x$i')];
      final big = AlbumGalleries.update(_gallery(type: 'asymmetric_gallery', albums: ['big']), albums: [_album('big', [for (final m in many) m.id])], library: many);
      expect(big.block.items('images'), hasLength(12));
      expect(big.excluded.values.toSet(), {AlbumImageExclusion.galleryFull});
    });

    test('galleries without albums, and other blocks, are left exactly as they are; nested galleries are updated', () {
      final plain = _gallery(images: [_hand('m_draft')]);
      expect(identical(AlbumGalleries.update(plain, albums: const [], library: library).block, plain), isTrue);
      final page = BlockRegistry.parseList([
        plain.toMap(),
        {'id': 'b_text00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Hi', 'ta': 'வணக்கம்'}},
        {
          'id': 'b_sec00001',
          'type': 'section',
          'v': 1,
          'layout': '1',
          'columns': [
            {
              'id': 'c_col00000',
              'blocks': [
                {'id': 'b_row00001', 'type': 'row', 'v': 1, 'layout': '1', 'columns': [{'id': 'c_r0', 'blocks': [_gallery(type: 'asymmetric_gallery', albums: ['a1']).toMap()..['id'] = 'b_inner0001']}]},
              ],
            },
          ],
        },
      ]);
      final out = AlbumGalleries.updateAll(page, albums: [_album('a1', ['m_5'])], library: library);
      expect(identical(out[0], page[0]) && identical(out[1], page[1]), isTrue);
      final inner = ((out[2] as StructuredBlock).columns('columns').first.blocks.first as StructuredBlock).columns('columns').first.blocks.first as StructuredBlock;
      expect(_media(inner), ['m_5']);
      expect(AlbumGalleries.anyUsesAlbums(page), isTrue);
      expect(AlbumGalleries.anyUsesAlbums([page[0], page[1]]), isFalse);
    });

    test('stored as read: album fields only when used; Tamil and unknown fields kept; new galleries unchanged', () {
      final fresh = BlockRegistry.create(BlockRegistry.gallery).toMap();
      expect(fresh.keys, isNot(anyOf(contains(AlbumSource.albumIds), contains(AlbumSource.excludedKey))));
      expect(((fresh['images'] as List).single as Map).keys.toSet(), {'id', 'mediaId'}, reason: 'one empty image, as before');
      final old = {
        'id': 'b_old000001',
        'type': 'gallery',
        'v': 1,
        'heading': {'en': 'Our days', 'ta': 'எங்கள் நாட்கள்'},
        'columns': '3',
        'mobileColumns': '1',
        'images': [_hand('m_1', extra: {'caption': {'en': 'Art', 'ta': 'கலை'}})],
        'futureBlockKey': {'x': 1},
      };
      expect(BlockRegistry.parse(old).toMap(), old, reason: 'an existing gallery is stored exactly as before');
      final withAlbums = {
        ...old,
        AlbumSource.albumIds: ['a1', 'a2'],
        AlbumSource.excludedKey: ['m_4'],
        'images': [
          ...old['images'] as List,
          {'id': 'i_alb000001', 'mediaId': 'm_2', 'albums': ['a1', 'a2'], 'futureItemKey': true},
        ],
      };
      expect(BlockRegistry.parse(withAlbums).toMap(), withAlbums);
      expect(BlockRegistry.blockProblems(BlockRegistry.parse(withAlbums)), isEmpty);
      expect(BlockRegistry.blockProblems(BlockRegistry.parse({...withAlbums, AlbumSource.albumIds: List.filled(11, 'a')})), isNotEmpty, reason: 'at most 10, once each');
    });
  });

  // ------------------------------------------------------------ rendering
  group('on the page', () {
    Future<void> pump(WidgetTester tester, List<WebsiteBlock> blocks, List<WebsiteMedia> published, double width) async {
      tester.view.physicalSize = Size(width, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteDesignScope(
              design: SiteDesign.defaults,
              child: WebsiteBlocksView(blocks: blocks, media: {for (final m in published) m.id: m}, language: PublicLanguage.english, interactive: false, spaced: false, fullBleed: true),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'no overflow at $width px');
    }

    testWidgets('both galleries draw album images like any other, on desktop, tablet and phone; a withdrawn image is never drawn', (tester) async {
      final albums = [_album('a1', ['m_1', 'm_2', 'm_3'])];
      final photo = AlbumGalleries.update(_gallery(albums: ['a1'], images: [_hand('m_4')]), albums: albums, library: library).block;
      final asym = AlbumGalleries.update(_gallery(type: 'asymmetric_gallery', albums: ['a1']), albums: albums, library: library).block.copyWith(id: 'b_asym00001');
      final visible = [for (final m in library) if (m.visibleToVisitors) m];
      for (final width in [1280.0, 820.0, 390.0]) {
        await pump(tester, [photo, asym], visible, width);
        for (final item in photo.items('images')) {
          expect(key('public-gallery-item-${item.id}'), findsOneWidget, reason: '${item.string('mediaId')} at $width');
        }
        for (final item in asym.items('images')) {
          expect(key('public-asymmetric-tile-${item.id}'), findsOneWidget);
        }
      }
      // Consent withdrawn after publishing: the public list no longer has it.
      final withdrawn = [for (final m in visible) if (m.id != 'm_2') m];
      await pump(tester, [photo, asym], withdrawn, 1280);
      final m2 = photo.items('images').firstWhere((i) => i.string('mediaId') == 'm_2');
      expect(key('public-gallery-item-${m2.id}'), findsNothing);
      expect(find.byKey(const ValueKey('public-image-m_2')), findsNothing);
    });
  });

  // ------------------------------------------------------------ editor and publishing
  group('editing and publishing', () {
    late FakeFirebaseFirestore db;
    late WebsiteContentAdminService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<void> seedMedia() async {
      for (final m in library) {
        await db.collection(WebsiteCollections.media).doc(m.id).set({
          'url': m.url,
          'storagePath': m.storagePath,
          'status': m.status.name,
          'consentConfirmed': m.consentConfirmed,
          'alt': {'en': m.alt.en},
          'inGallery': true,
        });
      }
    }

    Future<WebsiteAlbum> album(String name, List<String> ids, {String description = ''}) async {
      final a = await service.albums.create(requesterRole: 'admin', actor: _admin, name: name, description: description);
      if (ids.isNotEmpty) await service.albums.addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: ids);
      return a;
    }

    Future<String> pageWith(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Photos', ta: 'புகைப்படங்கள்'), slug: 'photos');
      await db.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    Future<CustomPage> page(String id) async => (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
    Future<List<WebsiteBlock>> live(String id) async => BlockRegistry.parseList((await db.collection(WebsiteCollections.livePages).doc(id).get()).data()!['blocks']);

    test('publishing copies in the album images visitors may see; album changes reach visitors only when republished; no album data is public', () async {
      await seedMedia();
      final a = await album('Annual day', ['m_1', 'm_draft', 'm_2']);
      final id = await pageWith([_gallery(albums: [a.id], images: [_hand('m_6')]).toMap()]);
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await page(id));
      var shown = (await live(id)).single as StructuredBlock;
      expect(_media(shown), ['m_6', 'm_1', 'm_2'], reason: 'by hand first, then the album’s published images');
      expect(_media((await page(id)).blocks!.single as StructuredBlock), _media(shown), reason: 'the draft matches what was published');
      final liveJson = (await db.collection(WebsiteCollections.livePages).doc(id).get()).data().toString();
      expect(liveJson, isNot(contains('Annual day')), reason: 'no album name or record on the live page');

      // The album changes: visitors still see what was published.
      await service.albums.addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: ['m_3']);
      await service.albums.removeMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: ['m_1']);
      expect(_media((await live(id)).single as StructuredBlock), ['m_6', 'm_1', 'm_2']);
      // Republished: up to date.
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await page(id));
      shown = (await live(id)).single as StructuredBlock;
      expect(_media(shown), ['m_6', 'm_2', 'm_3']);

      // Consent withdrawn later: visitors never get it, before or after republishing.
      await db.collection(WebsiteCollections.media).doc('m_2').update({'consentConfirmed': false, 'status': 'hidden'});
      final public = await WebsiteContentRepository(firestore: db).publishedMedia();
      expect(public.map((m) => m.id), isNot(contains('m_2')));
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await page(id));
      expect(_fromAlbums((await live(id)).single as StructuredBlock), ['m_3']);

      // The album is deleted: the gallery keeps what it has.
      await service.albums.delete(requesterRole: 'admin', albumId: a.id);
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await page(id));
      expect(_media((await live(id)).single as StructuredBlock), ['m_6', 'm_3']);
    });

    test('an image in a gallery’s draft is protected from deletion like any other', () async {
      await seedMedia();
      final a = await album('Garden', ['m_1']);
      final id = await pageWith([_gallery(albums: [a.id]).toMap()]);
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await page(id));
      await expectLater(service.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: 'm_1'), throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('Photos'))));
    });

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
      String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;
      const p = 'website-block-b_gal000001';

      for (final type in ['gallery', 'asymmetric_gallery']) {
        testWidgets('$type: choose albums (search), see what each gives and why some can’t; remove one; images chosen by hand stay; save, reopen, publish', (tester) async {
          await seedMedia();
          final a = await album('Annual day', ['m_1', 'm_2', 'm_draft', 'm_nocons'], description: 'Stage');
          final b = await album('Garden', ['m_2', 'm_3']);
          await album('Empty', []);
          final id = await pageWith([_gallery(type: type, images: [_hand('m_6', extra: {'caption': {'en': 'Hand', 'ta': 'கை'}})]).toMap()]);
          await open(tester, id);
          await tap(tester, key('$p-edit'));
          expect(key('$p-albums'), findsOneWidget);
          expect(text(tester, '$p-albums-mode'), 'Images chosen by hand: 0 images from albums, 1 image chosen by hand.');

          await tap(tester, key('$p-albums-add'));
          expect(text(tester, 'website-album-picker-${a.id}-count'), contains('4 images, 2 visitors may see'));
          await tester.enterText(key('website-album-picker-search'), 'gard');
          await tester.pumpAndSettle();
          expect(key('website-album-picker-${a.id}'), findsNothing);
          await tap(tester, key('website-album-picker-${b.id}'));
          await tester.enterText(key('website-album-picker-search'), '');
          await tester.pumpAndSettle();
          await tap(tester, key('website-album-picker-${a.id}'));
          await tap(tester, key('website-album-picker-done'));

          expect(_media(gallery(tester)), ['m_6', 'm_2', 'm_3', 'm_1'], reason: 'Garden first (chosen first), then Annual day; m_2 once');
          expect(text(tester, '$p-albums-mode'), 'Albums and images chosen by hand: 3 images from albums, 1 image chosen by hand.');
          expect(text(tester, '$p-album-${a.id}-count'), '2 images in the gallery · 2 not included: 1 not published, 1 consent not confirmed');
          expect(text(tester, '$p-album-${b.id}-count'), '2 images in the gallery');
          expect(key('$p-albums-preview'), findsOneWidget);
          expect(find.textContaining('publishing updates this gallery from its albums'), findsOneWidget);
          expect(find.textContaining('From an album'), findsWidgets);

          // Remove Garden: m_3 leaves; m_2 stays (Annual day has it).
          await tap(tester, key('$p-album-${b.id}-remove'));
          expect(_media(gallery(tester)), ['m_6', 'm_2', 'm_1']);
          expect((gallery(tester).items('images').first.text('caption')).ta, 'கை', reason: 'the hand-chosen image unchanged');

          // Save, reopen, publish.
          final before = gallery(tester).toMap();
          await tap(tester, key('website-custom-save-draft'));
          await open(tester, id);
          expect(gallery(tester).toMap(), before);
          await tap(tester, key('website-custom-publish'));
          if (key('website-custom-publish-confirm').evaluate().isNotEmpty) await tap(tester, key('website-custom-publish-confirm'));
          expect((await live(id)).single.toMap(), before);
        });
      }

      testWidgets('removing an album image keeps it out; the album changes: “Update from albums”; include again', (tester) async {
        await seedMedia();
        final a = await album('Annual day', ['m_1', 'm_2']);
        final id = await pageWith([AlbumGalleries.update(_gallery(albums: [a.id]), albums: [_album(a.id, ['m_1', 'm_2'])], library: library).block.toMap()]);
        await service.albums.addMedia(requesterRole: 'admin', actor: _admin, albumId: a.id, mediaIds: ['m_3']);
        await open(tester, id);
        await tap(tester, key('$p-edit'));
        expect(find.textContaining('Update from albums (1 new)'), findsOneWidget, reason: 'the album gained an image since');
        await tap(tester, key('$p-albums-update'));
        expect(_media(gallery(tester)), ['m_1', 'm_2', 'm_3']);
        expect(key('$p-albums-update'), findsNothing);

        final m1 = gallery(tester).items('images').first;
        await tap(tester, key('$p-images-item-${m1.id}-remove'));
        expect(_media(gallery(tester)), ['m_2', 'm_3']);
        expect(AlbumSource.excludedOf(gallery(tester)), ['m_1']);
        expect(key('$p-albums-update'), findsNothing, reason: 'not brought back');
        await tap(tester, key('$p-albums-include-again'));
        expect(_media(gallery(tester)), ['m_2', 'm_3', 'm_1']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a narrow window: the panel and picker fit', (tester) async {
        await seedMedia();
        await album('A long album name for the annual day celebrations in the garden', ['m_1']);
        final id = await pageWith([_gallery(images: [_hand('m_6')]).toMap()]);
        await open(tester, id, size: const Size(600, 2400));
        await tap(tester, key('website-editor-tab-structure'));
        await tap(tester, key('$p-edit'));
        expect(key('$p-albums'), findsOneWidget);
        await tap(tester, key('$p-albums-add'));
        expect(key('website-album-picker'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
