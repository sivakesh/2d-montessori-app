// Website Content → Media library and Gallery order, as administrators use
// them: the image grid (cards per row on each screen), search, filters and
// the result count, an image's details (usage, actions, safe delete),
// selection with only the bulk actions that apply, the latest upload
// shown first; and the gallery order (published images only, drag and
// drop, the keyboard alternative, unsaved changes, save, discard, failure,
// preview, the places of images visitors don't see, and the public order).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_content_screen.dart';
import 'package:montessori_app/modules/admin/website/ui/website_gallery_order.dart';
import 'package:montessori_app/modules/admin/website/ui/website_media_library.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';

class _Processor implements WebsiteImageProcessor {
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

class _Picker extends FilePicker {
  final files = <PlatformFile>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      files.isEmpty ? null : FilePickerResult(files);
}

/// Gallery order saves fail until [fail] is turned off.
class _FailingSaves extends WebsiteContentAdminService {
  _FailingSaves({required super.firestore, required super.storage, required super.imageProcessor});
  bool fail = true;

  @override
  Future<void> reorderGallery({required String requesterRole, required AppUser actor, required List<String> orderedIds}) async {
    if (fail) throw WebsiteContentException('The gallery order couldn’t be saved.');
    return super.reorderGallery(requesterRole: requesterRole, actor: actor, orderedIds: orderedIds);
  }
}

final _admin = AppUser(id: '9000000001', phone: '9000000001', role: 'admin', isActive: true, name: 'Test admin');

void main() {
  Finder key(String k) => find.byKey(Key(k));
  late FakeFirebaseFirestore db;
  late _Picker picker;
  late WebsiteContentAdminService service;

  setUp(() {
    db = FakeFirebaseFirestore();
    picker = _Picker();
    service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _Processor(), filePicker: picker);
  });

  CollectionReference<Map<String, dynamic>> media() => db.collection(WebsiteCollections.media);

  /// A stored image as the library keeps it.
  Future<String> image(String id, {String caption = '', String alt = 'Children at work', String status = 'draft', bool consent = true, bool inGallery = true, int order = 0, String category = 'classroom', DateTime? updatedAt}) async {
    await media().doc(id).set({
      'url': 'https://storage.example.test/$id.jpg',
      'storagePath': 'website_media/$id/1_display.jpg',
      'thumbUrl': 'https://storage.example.test/${id}_t.jpg',
      'thumbStoragePath': 'website_media/$id/1_thumb.jpg',
      'alt': {'en': alt, 'ta': ''},
      'caption': {'en': caption},
      'category': category,
      'status': status,
      'inGallery': inGallery,
      'galleryOrder': order,
      'consentConfirmed': consent,
      'width': 1600,
      'height': 1200,
      'sizeBytes': 204800,
      'updatedAt': ?(updatedAt == null ? null : Timestamp.fromDate(updatedAt)),
    });
    return id;
  }

  Future<Map<String, dynamic>> stored(String id) async => (await media().doc(id).get()).data()!;

  Future<void> pump(WidgetTester tester, {Size size = const Size(1280, 2400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [currentUserProvider.overrideWith((ref) => _admin)],
      child: MaterialApp(home: WebsiteContentScreen(service: service)),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

  /// How many cards share the first card's row.
  int perRow(WidgetTester tester, List<String> ids) {
    final top = tester.getTopLeft(key('website-media-${ids.first}')).dy;
    return ids.where((id) => tester.getTopLeft(key('website-media-$id')).dy == top).length;
  }

  group('media library', () {
    testWidgets('a grid of image cards: 2 per row on phones, 3 on tablets, 4–6 on desktops; images first, titles not the default alt text', (tester) async {
      final ids = [for (var i = 0; i < 7; i++) await image('m_grid0000$i', caption: i == 0 ? 'Sports day relay' : '', alt: i == 1 ? WebsiteMedia.defaultAlt : 'Children at work')];
      await pump(tester);
      expect(key('website-media-grid'), findsOneWidget);
      expect(key('website-media-purpose'), findsOneWidget);
      expect(perRow(tester, ids), inInclusiveRange(4, 6));
      expect(text(tester, 'website-media-m_grid00000-title'), 'Sports day relay', reason: 'the caption first');
      expect(text(tester, 'website-media-m_grid00001-title'), 'Untitled image', reason: 'never the default alt text as a title');
      expect(key('website-media-m_grid00001-default-alt'), findsOneWidget, reason: 'flagged as the default alt text');
      expect(text(tester, 'website-media-m_grid00002-title'), 'Children at work');
      final card = tester.getSize(key('website-media-m_grid00000'));
      expect(card.height, lessThan(card.width * 1.6), reason: 'cards don’t become excessively tall');

      await pump(tester, size: const Size(820, 2400));
      expect(perRow(tester, ids), 3);
      await pump(tester, size: const Size(390, 2400));
      expect(perRow(tester, ids), 2);
      expect(tester.takeException(), isNull, reason: 'no overflow at phone width');
    });

    testWidgets('search (caption, alt text, category, album), filters, result count and Clear filters', (tester) async {
      await image('m_pub00001', caption: 'Garden planting', status: 'published', order: 0);
      await image('m_drf00001', caption: 'Library corner', inGallery: false, category: 'campus');
      await image('m_drf00002', alt: 'Painting at the easel');
      final album = await service.albums.create(requesterRole: 'admin', actor: _admin, name: 'Annual day');
      await service.albums.addMedia(requesterRole: 'admin', actor: _admin, albumId: album.id, mediaIds: ['m_drf00002']);
      await pump(tester);
      expect(text(tester, 'website-media-result-count'), '3 images');
      expect(key('website-media-clear-filters'), findsNothing);

      Future<void> search(String q) async {
        await tester.enterText(key('website-media-search'), q);
        await tester.pumpAndSettle();
      }

      Set<String> shown() => {for (final id in ['m_pub00001', 'm_drf00001', 'm_drf00002']) if (find.byKey(Key('website-media-$id')).evaluate().isNotEmpty) id};

      await search('garden');
      expect(shown(), {'m_pub00001'});
      expect(text(tester, 'website-media-result-count'), '1 image of 3');
      await search('easel');
      expect(shown(), {'m_drf00002'}, reason: 'alt text');
      await search('annual');
      expect(shown(), {'m_drf00002'}, reason: 'album name');
      await search('campus');
      expect(shown(), {'m_drf00001'}, reason: 'category');
      await search('nothing like this');
      expect(key('website-media-filter-empty'), findsOneWidget);
      await tap(tester, key('website-media-filter-empty-clear'));
      expect(shown(), hasLength(3));

      await tap(tester, key('website-media-filter-published'));
      expect(shown(), {'m_pub00001'});
      await tap(tester, key('website-media-filter-notPublished'));
      expect(shown(), {'m_drf00001', 'm_drf00002'});
      await tap(tester, key('website-media-filter-notInGallery'));
      expect(shown(), {'m_drf00001'});
      await tap(tester, key('website-media-filter-inGallery'));
      expect(shown(), {'m_pub00001', 'm_drf00002'});
      await tap(tester, key('website-media-clear-filters'));
      expect(shown(), hasLength(3));
      expect((await stored('m_drf00002'))['status'], 'draft', reason: 'filters change nothing stored');
    });

    testWidgets('details: preview, caption, alt text, albums, status, gallery and where it is used; Edit details opens the editor', (tester) async {
      await image('m_used0001', caption: 'Morning circle', status: 'published');
      await db.collection(WebsiteCollections.pageDrafts).doc('home').set({'mediaIds': ['m_used0001']});
      final album = await service.albums.create(requesterRole: 'admin', actor: _admin, name: 'Classrooms');
      await service.albums.addMedia(requesterRole: 'admin', actor: _admin, albumId: album.id, mediaIds: ['m_used0001']);
      await pump(tester);
      await tap(tester, key('website-media-m_used0001'));
      expect(key('website-media-details'), findsOneWidget);
      expect(key('website-media-details-preview'), findsOneWidget);
      expect(text(tester, 'website-media-details-title'), 'Morning circle');
      expect(find.descendant(of: key('website-media-details-albums'), matching: find.text('Classrooms')), findsOneWidget);
      expect(find.descendant(of: key('website-media-details-gallery'), matching: find.text('In the public gallery.')), findsOneWidget);
      expect(text(tester, 'website-media-details-usage'), contains('Homepage hero'));
      expect(find.textContaining('website_media/'), findsNothing, reason: 'no storage paths');
      expect(find.textContaining('m_used0001'), findsNothing, reason: 'no internal ids');
      expect(tester.widget<OutlinedButton>(key('website-media-details-delete')).onPressed, isNull, reason: 'in use: not deletable');
      expect(text(tester, 'website-media-details-delete-blocked'), contains('Homepage hero'));
      await tap(tester, key('website-media-details-edit'));
      expect(key('website-media-crops'), findsOneWidget, reason: 'the existing editor');
    });

    testWidgets('details actions: unpublish, gallery, album, and delete after confirming (an unused image)', (tester) async {
      await image('m_act00001', caption: 'Story time', status: 'published');
      final album = await service.albums.create(requesterRole: 'admin', actor: _admin, name: 'Reading');
      await pump(tester);

      await tap(tester, key('website-media-m_act00001'));
      await tap(tester, key('website-media-details-unpublish'));
      expect(key('website-media-details'), findsNothing);
      expect((await stored('m_act00001'))['status'], isNot('published'));

      await tap(tester, key('website-media-m_act00001'));
      await tap(tester, key('website-media-details-gallery-remove'));
      expect((await stored('m_act00001'))['inGallery'], isFalse);
      expect((await stored('m_act00001'))['consentConfirmed'], isTrue, reason: 'nothing else changes');

      await tap(tester, key('website-media-m_act00001'));
      await tap(tester, key('website-media-details-album-add'));
      await tap(tester, key('website-media-details-album-${album.id}'));
      expect((await service.albums.list(requesterRole: 'admin')).single.mediaIds, ['m_act00001']);
      expect(key('website-media-m_act00001-album-${album.id}'), findsOneWidget);

      await tap(tester, key('website-media-m_act00001'));
      await tap(tester, key('website-media-details-delete'));
      await tap(tester, key('website-media-details-delete-cancel'));
      expect((await media().doc('m_act00001').get()).exists, isTrue, reason: 'Cancel keeps it');
      await tap(tester, key('website-media-details-delete'));
      await tap(tester, key('website-media-details-delete-confirm'));
      expect((await media().doc('m_act00001').get()).exists, isFalse);
      expect(key('website-media-m_act00001'), findsNothing);
      expect((await service.albums.list(requesterRole: 'admin')).single.mediaIds, isEmpty, reason: 'taken out of its album');
    });

    testWidgets('details: publishing without consent is refused with the reason', (tester) async {
      await image('m_nocon001', consent: false);
      await pump(tester);
      await tap(tester, key('website-media-m_nocon001'));
      await tap(tester, key('website-media-details-publish'));
      expect(find.textContaining('consent'), findsWidgets);
      expect((await stored('m_nocon001'))['status'], 'draft');
    });

    testWidgets('selection: count, select and deselect; Actions disabled with none; only applicable actions offered', (tester) async {
      await image('m_sel00001', status: 'published');
      await image('m_sel00002', status: 'published');
      await pump(tester);
      expect(text(tester, 'website-media-selection-count'), '0 selected');
      expect(tester.widget<PopupMenuButton<String>>(key('website-media-bulk')).enabled, isFalse);
      await tap(tester, key('website-media-m_sel00001-select'));
      await tap(tester, key('website-media-m_sel00002-select'));
      expect(text(tester, 'website-media-selection-count'), '2 selected');
      await tap(tester, key('website-media-m_sel00002-select'));
      expect(text(tester, 'website-media-selection-count'), '1 selected', reason: 'deselected');
      await tap(tester, key('website-media-bulk'));
      bool enabled(String a) => tester.widget<PopupMenuItem<String>>(key('website-media-bulk-$a')).enabled;
      expect(enabled('publish'), isFalse, reason: 'already published');
      expect(enabled('confirmConsent'), isFalse, reason: 'already confirmed');
      expect(enabled('addToGallery'), isFalse, reason: 'already in the gallery');
      expect(enabled('unpublish'), isTrue);
      expect(enabled('removeFromGallery'), isTrue);
      expect(enabled('delete'), isTrue);
    });

    testWidgets('uploading: types and size explained; the new images are shown first, marked New, with a Just uploaded filter', (tester) async {
      await image('m_old00001', updatedAt: DateTime(2026, 1, 1));
      picker.files.addAll([
        PlatformFile(name: 'a.jpg', size: 3, bytes: Uint8List.fromList([9, 9, 9])),
        PlatformFile(name: 'b.png', size: 3, bytes: Uint8List.fromList([8, 9, 9])),
      ]);
      await pump(tester);
      expect(find.textContaining('JPEG, PNG or WebP, up to 15 MB each'), findsOneWidget);
      await tap(tester, key('website-upload'));
      await tester.ensureVisible(key('website-upload-confirm'));
      await tester.tap(key('website-upload-confirm'));
      await tester.pumpAndSettle();
      expect(text(tester, 'website-upload-status'), '2 uploaded · 0 failed');
      await tap(tester, key('website-upload-cancel'));
      final uploaded = [for (final d in (await media().get()).docs) if (d.id != 'm_old00001') d.id];
      expect(uploaded, hasLength(2));
      expect(tester.widget<ChoiceChip>(key('website-media-filter-recent')).selected, isTrue);
      expect(find.text('New'), findsNWidgets(2));
      expect(key('website-media-m_old00001'), findsNothing, reason: 'only the new ones while that filter is on');
      await tap(tester, key('website-media-filter-all'));
      expect(key('website-media-m_old00001'), findsOneWidget);
      final first = tester.getTopLeft(key('website-media-${uploaded.first}'));
      final old = tester.getTopLeft(key('website-media-m_old00001'));
      expect(first.dy < old.dy || (first.dy == old.dy && first.dx < old.dx), isTrue, reason: 'the new ones first');
      expect(find.textContaining('consent has been obtained'), findsWidgets, reason: 'the consent warning is still shown');
    });

    testWidgets('empty and loading states', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [currentUserProvider.overrideWith((ref) => _admin)],
        child: MaterialApp(home: WebsiteContentScreen(service: service)),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'loading');
      await tester.pumpAndSettle();
      expect(key('website-media-empty'), findsOneWidget);
      expect(key('website-media-grid'), findsNothing);
    });
  });

  group('gallery order', () {
    // The public gallery: published images marked for it, in order.
    List<String> publicOrder(List<WebsiteMedia> m) => [for (final x in m) if (x.inGallery) x.id];
    Future<List<String>> live() async => publicOrder(await WebsiteContentRepository(firestore: db).publishedMedia());

    Future<void> openGallery(WidgetTester tester, {Size size = const Size(1280, 2400)}) async {
      await pump(tester, size: size);
      await tap(tester, key('website-tab-gallery'));
    }

    String position(WidgetTester tester, String id) => tester.widget<Text>(find.descendant(of: key('website-gallery-position-$id'), matching: find.byType(Text))).data!;

    Future<void> seed() async {
      await image('m_g1', caption: 'One', status: 'published', order: 0);
      await image('m_draft', caption: 'Draft', order: 1);
      await image('m_g2', caption: 'Two', status: 'published', order: 2);
      await image('m_g3', caption: 'Three', status: 'published', order: 3);
      await image('m_pages', caption: 'Pages only', status: 'published', inGallery: false, order: 4);
    }

    testWidgets('published gallery images only, in their order, numbered; the others listed apart', (tester) async {
      await seed();
      await openGallery(tester);
      expect(key('website-gallery-purpose'), findsOneWidget);
      expect(find.text('Only published images appear in the public gallery. Drag a card by its handle to a new place, or use its Move menu (or Alt+↑/↓). Then Save order. This order is the public gallery’s only; it doesn’t change the Media library, albums or pages.'), findsOneWidget);
      expect([position(tester, 'm_g1'), position(tester, 'm_g2'), position(tester, 'm_g3')], ['1', '2', '3']);
      expect(key('website-gallery-m_draft'), findsNothing);
      expect(key('website-gallery-not-shown-m_draft'), findsOneWidget);
      expect(key('website-gallery-m_pages'), findsNothing, reason: 'not in the gallery');
      expect(tester.widget<FilledButton>(key('website-gallery-save')).onPressed, isNull, reason: 'nothing to save');
      expect(await live(), ['m_g1', 'm_g2', 'm_g3']);
    });

    testWidgets('drag and drop: the dropped card takes the target’s place; unsaved until Save order', (tester) async {
      await seed();
      await openGallery(tester);
      final drag = await tester.startGesture(tester.getCenter(key('website-gallery-handle-m_g3')));
      await tester.pump(const Duration(milliseconds: 50));
      await drag.moveTo(tester.getCenter(key('website-gallery-m_g1')));
      await tester.pump();
      final card = tester.widget<Card>(key('website-gallery-m_g1'));
      expect((card.shape! as RoundedRectangleBorder).side.width, 3, reason: 'the drop place is marked');
      await drag.up();
      await tester.pumpAndSettle();
      expect([position(tester, 'm_g3'), position(tester, 'm_g1'), position(tester, 'm_g2')], ['1', '2', '3']);
      expect(key('website-gallery-unsaved'), findsOneWidget);
      expect(find.text('Gallery order •'), findsOneWidget, reason: 'the tab shows it too');
      expect(await live(), ['m_g1', 'm_g2', 'm_g3'], reason: 'visitors keep the saved order');

      await tap(tester, key('website-gallery-save'));
      expect(await live(), ['m_g3', 'm_g1', 'm_g2']);
      expect(key('website-gallery-unsaved'), findsNothing);
      expect(find.text('Gallery order saved. Visitors see the new order.'), findsOneWidget);
      // The draft image kept its place among them.
      expect((await stored('m_draft'))['galleryOrder'], 1);
      expect([(await stored('m_g3'))['galleryOrder'], (await stored('m_g1'))['galleryOrder'], (await stored('m_g2'))['galleryOrder']], [0, 2, 3]);
      expect((await stored('m_pages'))['galleryOrder'], 4, reason: 'images not in the gallery are untouched');
    });

    testWidgets('keyboard and Move menu; Discard changes goes back to the saved order; switching tabs keeps unsaved changes', (tester) async {
      await seed();
      await openGallery(tester);
      // Alt+↓ on a focused card.
      await tester.tap(key('website-gallery-m_g1'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(position(tester, 'm_g1'), '2');
      // Move menu: to last.
      await tap(tester, key('website-gallery-move-m_g2'));
      await tap(tester, key('website-gallery-last-m_g2'));
      expect([position(tester, 'm_g1'), position(tester, 'm_g3'), position(tester, 'm_g2')], ['1', '2', '3']);

      await tap(tester, key('website-tab-media'));
      await tap(tester, key('website-tab-gallery'));
      expect(key('website-gallery-unsaved'), findsOneWidget, reason: 'kept across tabs');

      await tap(tester, key('website-gallery-discard'));
      expect([position(tester, 'm_g1'), position(tester, 'm_g2'), position(tester, 'm_g3')], ['1', '2', '3']);
      expect(key('website-gallery-unsaved'), findsNothing);
      expect(await live(), ['m_g1', 'm_g2', 'm_g3']);
    });

    testWidgets('a failed save keeps the arrangement to try again', (tester) async {
      service = _FailingSaves(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _Processor());
      await seed();
      await openGallery(tester);
      await tap(tester, key('website-gallery-move-m_g3'));
      await tap(tester, key('website-gallery-first-m_g3'));
      await tap(tester, key('website-gallery-save'));
      expect(find.text('The gallery order couldn’t be saved.'), findsOneWidget, reason: 'the failure is reported');
      expect(key('website-gallery-unsaved'), findsOneWidget, reason: 'the arrangement is kept');
      expect(position(tester, 'm_g3'), '1');
      expect(await live(), ['m_g1', 'm_g2', 'm_g3'], reason: 'visitors keep the saved order');
      (service as _FailingSaves).fail = false;
      await tap(tester, key('website-gallery-save'));
      expect(await live(), ['m_g3', 'm_g1', 'm_g2'], reason: 'saved on retry');
    });

    testWidgets('Preview gallery shows the order being arranged; leaving with unsaved changes asks first', (tester) async {
      await seed();
      await openGallery(tester);
      await tap(tester, key('website-gallery-move-m_g3'));
      await tap(tester, key('website-gallery-first-m_g3'));
      await tap(tester, key('website-gallery-preview'));
      expect(key('website-gallery-preview-dialog'), findsOneWidget);
      expect(find.descendant(of: key('website-gallery-preview-0'), matching: find.text('Three')), findsOneWidget);
      expect(find.textContaining('not saved yet'), findsOneWidget);
      await tap(tester, key('website-gallery-preview-close'));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(key('website-gallery-leave-cancel'), findsOneWidget);
      await tap(tester, key('website-gallery-leave-cancel'));
      expect(key('website-gallery-unsaved'), findsOneWidget, reason: 'still arranging');
    });

    testWidgets('phone width: two per row, no overflow, every move available', (tester) async {
      await seed();
      await openGallery(tester, size: const Size(360, 1600));
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(key('website-gallery-m_g1')).dy, tester.getTopLeft(key('website-gallery-m_g2')).dy);
      expect(tester.getTopLeft(key('website-gallery-m_g3')).dy, greaterThan(tester.getTopLeft(key('website-gallery-m_g1')).dy));
      await tap(tester, key('website-gallery-move-m_g2'));
      await tap(tester, key('website-gallery-up-m_g2'));
      expect(position(tester, 'm_g2'), '1');
    });

    test('the order stored: the images visitors don’t see keep their places', () {
      WebsiteMedia m(String id, {bool shown = true}) => WebsiteMedia(id: id, url: 'u', storagePath: '', status: shown ? WebsiteMediaStatus.published : WebsiteMediaStatus.draft, consentConfirmed: true);
      final gallery = [m('a'), m('x', shown: false), m('b'), m('c'), m('y', shown: false)];
      expect(WebsiteGalleryOrder.orderToSave(gallery, ['c', 'a', 'b']), ['c', 'x', 'a', 'b', 'y']);
      expect(WebsiteGalleryOrder.reconcile(gallery, ['a', 'b', 'c']), isNull, reason: 'the saved order again');
      expect(WebsiteGalleryOrder.reconcile([m('a'), m('c')], ['c', 'b', 'a']), ['c', 'a'], reason: 'a removed image leaves the arrangement');
      expect(WebsiteGalleryOrder.move(['a', 'b', 'c'], 'c', 0), ['c', 'a', 'b']);
    });
  });

  test('card titles: caption, else alt text unless it is the default, never a file name', () {
    WebsiteMedia m({String caption = '', String alt = '', bool decorative = false}) =>
        WebsiteMedia(id: 'm', url: '', storagePath: 'website_media/m/1_display.jpg', caption: LocalizedText(en: caption), alt: LocalizedText(en: alt), decorative: decorative);
    expect(mediaTitle(m(caption: 'Sports day', alt: 'Relay')), 'Sports day');
    expect(mediaTitle(m(alt: 'Relay race')), 'Relay race');
    expect(mediaTitle(m(alt: WebsiteMedia.defaultAlt)), 'Untitled image');
    expect(mediaTitle(m(decorative: true)), 'Decorative image');
  });
}
