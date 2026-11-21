// The school's template library (website_templates): sections and blocks
// saved with every property (columns, widths, gaps, backgrounds, padding,
// per-screen settings, items, images, hidden blocks, order) and inserted
// as independent copies with new ids throughout; scoped to the school
// (another school's templates are never listed, read or changed); images
// a template uses stay in the media library; deleting a template never
// changes a page. Editor: Save as template, Browse templates in Add
// section / Add block / a column, search, filters, preview per screen
// size, rename, description, thumbnail, delete; and a save, reopen and
// publish round-trip of an inserted copy. Synthetic test data only; the
// fake Firestore proves the app's behaviour, the rules are tested on the
// emulator (test/firebase_rules/website_rules_test.py).
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/data/website_templates_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_template_library.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_anchors.dart';
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

/// A fake Firestore whose template queries can be refused, as the rules
/// refuse them for an admin without the school claim.
class _RefusingFirestore extends FakeFirebaseFirestore {
  bool refuseTemplates = false;

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      refuseTemplates && path == WebsiteCollections.templates ? _RefusedCollection() : super.collection(path);
}

// A test double only: queries on it fail as refused queries do.
// ignore: subtype_of_sealed_class
class _RefusedCollection implements CollectionReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => switch (invocation.memberName) {
        #where => this,
        #get => Future<QuerySnapshot<Map<String, dynamic>>>.error(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
        _ => super.noSuchMethod(invocation),
      };
}

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
final _staff = AppUser(id: '9000000003', phone: '9000000003', role: 'staff', isActive: true, name: 'Test staff');
const _photo = 'media_photo_0001';
const _thumb = 'media_thumb_0001';

Map<String, dynamic> _media(String id) => {
      'status': 'published',
      'consentConfirmed': true,
      'url': 'https://storage.example.test/$id.jpg',
      'thumbUrl': 'https://storage.example.test/$id-t.jpg',
      'alt': {'en': 'Children in the garden ($id)', 'ta': ''},
      'storagePath': 'website_media/$id/d.jpg',
      'thumbStoragePath': 'website_media/$id/t.jpg',
    };

/// A section with everything a template must keep: three columns (with
/// per-screen settings), gaps, a background,
/// responsive padding, Tamil text, a heading, buttons (items), an image
/// (a media reference), a hidden block, and block order.
/// [_rawSection] as pages store it (read and written back once).
Map<String, dynamic> _richSection() => Map<String, dynamic>.from(BlockRegistry.toMapList(BlockRegistry.parseList([_rawSection()])).single as Map);

Map<String, dynamic> _rawSection() => {
      'id': 'b_rich00001',
      'type': 'section',
      'v': 1,
      'name': {'en': 'Programmes', 'ta': ''},
      'heading': {'en': 'Our programmes', 'ta': 'எங்கள் திட்டங்கள்'},
      'layout': '1:1:1',
      'tabletColumns': '2',
      'mobileColumns': '1',
      'style': {
        'background': 'token:sageLight',
        'columnGap': '24',
        'rowGap': '16',
        'blockPadding': {
          'desktop': {'top': 64, 'bottom': 64},
          'mobile': {'top': 24},
        },
      },
      'columns': [
        {
          'id': 'c_rich00001',
          'blocks': [
            {'id': 'b_text00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Toddler', 'ta': 'குழந்தை'}, 'body': {'en': 'Ages 1–3.', 'ta': ''}},
            {'id': 'b_img000001', 'type': 'image', 'v': 1, 'mediaId': _photo, 'alt': {'en': '', 'ta': ''}, 'caption': {'en': 'Garden', 'ta': ''}, 'aspect': '4:3'},
          ],
        },
        {
          'id': 'c_rich00002',
          'blocks': [
            {'id': 'b_text00002', 'type': 'text', 'v': 1, 'heading': {'en': 'Primary', 'ta': ''}, 'body': {'en': 'Ages 3–6.', 'ta': ''}, 'hidden': true},
            {
              'id': 'b_btns00001',
              'type': 'buttons',
              'v': 1,
              'buttons': [
                {'id': 'i_btn000001', 'label': {'en': 'Apply', 'ta': ''}, 'target': '/admissions', 'variant': 'primary'},
              ],
            },
          ],
        },
        {'id': 'c_rich00003', 'blocks': []},
      ],
    };

/// Every id in [map] (blocks, columns, items), depth first.
List<String> _ids(Object? map) => [
      if (map is Map) ...[
        if (map['id'] is String) map['id'] as String,
        for (final v in map.values) ..._ids(v),
      ],
      if (map is List)
        for (final v in map) ..._ids(v),
    ];

/// [map] with every id replaced by its position (to compare content).
Object? _withoutIds(Object? map) => map is Map
    ? {for (final e in map.entries) e.key: e.key == 'id' ? '-' : _withoutIds(e.value)}
    : map is List
        ? [for (final v in map) _withoutIds(v)]
        : map;

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parseList([raw]).single as StructuredBlock;

void main() {
  Finder key(String k) => find.byKey(Key(k));
  late FakeFirebaseFirestore db;
  late WebsiteTemplatesService templates;

  setUp(() async {
    db = FakeFirebaseFirestore();
    templates = WebsiteTemplatesService(firestore: db);
    for (final id in [_photo, _thumb]) {
      await db.collection(WebsiteCollections.media).doc(id).set(_media(id));
    }
  });

  // ------------------------------------------------------------ model
  group('saving and inserting', () {
    test('a section is saved exactly as pages store it, with its images and schema version', () async {
      final section = _parse(_richSection());
      final saved = await templates.save(requesterRole: 'admin', actor: _admin, block: section, name: '  Programmes  ', description: 'Three columns', thumbnailMediaId: _thumb);
      final doc = (await db.collection(WebsiteCollections.templates).doc(saved.id).get()).data()!;
      expect(doc['block'], _richSection(), reason: 'every property, nested blocks and order, unchanged');
      expect((doc['schoolId'], doc['schemaVersion'], doc['kind'], doc['blockType'], doc['name']), ('default_school', 1, 'section', 'section', 'Programmes'));
      expect(doc['mediaIds'], unorderedEquals([_photo, _thumb]));
      expect(doc['thumbnailMediaId'], _thumb);
      final block = await templates.save(requesterRole: 'admin', actor: _admin, block: section.columns('columns').first.blocks.first, name: 'Toddler text');
      expect((await db.collection(WebsiteCollections.templates).doc(block.id).get()).data()!['kind'], 'block');
    });

    test('inserting makes an independent deep copy: new ids everywhere, everything else the same', () async {
      final saved = await templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Programmes');
      final template = (await templates.get(requesterRole: 'admin', templateId: saved.id))!;
      final a = WebsiteTemplatesService.instantiate(template).toMap();
      final b = WebsiteTemplatesService.instantiate(template).toMap();
      final original = _ids(_richSection());
      for (final copy in [a, b]) {
        final ids = _ids(copy);
        expect(ids, hasLength(original.length), reason: 'every block, column and item');
        expect(ids.toSet(), hasLength(ids.length), reason: 'unique');
        expect(ids.toSet().intersection(original.toSet()), isEmpty, reason: 'none shared with the template');
        expect(_withoutIds(copy), _withoutIds(_richSection()), reason: 'content, settings, style, images, hidden, order: unchanged');
      }
      expect(_ids(a).toSet().intersection(_ids(b).toSet()), isEmpty, reason: 'two copies share nothing');
      final copy = BlockRegistry.parseList([a]).single as StructuredBlock;
      expect([ColumnsPerRow.on(copy, 'desktop'), ColumnsPerRow.on(copy, 'tablet'), ColumnsPerRow.on(copy, 'mobile')], [3, 2, 1], reason: 'responsive settings kept');
      expect(BlockRegistry.referencedMedia([copy]), [_photo], reason: 'the same media library image, no file copied');
      expect(copy.style['blockPadding'], _richSection()['style']['blockPadding']);
      expect(BlockRegistry.blockProblems(copy), isEmpty);
    });

    test('a template can’t hold blocks this version can’t show; one from a newer version is listed but not inserted', () async {
      final unknown = BlockRegistry.parseList([
        {
          ..._richSection(),
          'columns': [
            {'id': 'c_x0000001', 'blocks': [{'id': 'b_future01', 'type': 'hologram', 'v': 1}]},
            {'id': 'c_x0000002', 'blocks': []},
            {'id': 'c_x0000003', 'blocks': []},
          ],
        },
      ]).single;
      expect(WebsiteTemplatesService.blockProblem(unknown), contains('newer version'));
      await expectLater(templates.save(requesterRole: 'admin', actor: _admin, block: unknown, name: 'X'), throwsA(isA<WebsiteContentException>()));

      await db.collection(WebsiteCollections.templates).doc('future').set({
        'schoolId': 'default_school',
        'schemaVersion': 2,
        'kind': 'section',
        'blockType': 'section',
        'name': 'From the future',
        'block': _richSection(),
        'mediaIds': [],
      });
      final future = (await templates.get(requesterRole: 'admin', templateId: 'future'))!;
      expect(future.insertProblem, contains('newer version'));
      expect(() => WebsiteTemplatesService.instantiate(future), throwsA(isA<WebsiteContentException>()));
    });

    test('names and descriptions are checked; containers are known; search finds words in any order', () async {
      final section = _parse(_richSection());
      for (final name in ['', '   ', 'x' * 81]) {
        await expectLater(templates.save(requesterRole: 'admin', actor: _admin, block: section, name: name), throwsA(isA<WebsiteContentException>()), reason: '"$name"');
      }
      await expectLater(templates.save(requesterRole: 'admin', actor: _admin, block: section, name: 'Ok', description: 'x' * 301), throwsA(isA<WebsiteContentException>()));
      final t = await templates.save(requesterRole: 'admin', actor: _admin, block: section, name: 'Programmes band', description: 'Three columns with prices');
      expect(t.isContainer, isTrue);
      expect([t.matches('prices programmes'), t.matches('SECTION'), t.matches('gallery')], [true, true, false]);
    });
  });

  // ------------------------------------------------------------ service
  group('the library', () {
    test('admins only', () async {
      for (final call in <Future<Object?> Function()>[
        () => templates.list(requesterRole: _staff.role),
        () => templates.save(requesterRole: _staff.role, actor: _staff, block: _parse(_richSection()), name: 'X'),
        () => templates.delete(requesterRole: 'parent', templateId: 'x'),
      ]) {
        await expectLater(call(), throwsA(isA<UnauthorizedWebsiteContentException>()));
      }
    });

    test('scoped to the school: another school’s templates are never listed, read, changed or deleted', () async {
      final other = WebsiteTemplatesService(firestore: db, schoolId: 'other_school');
      final mine = await templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Ours');
      final theirs = await other.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Theirs');
      expect((await templates.list(requesterRole: 'admin')).map((t) => t.name), ['Ours']);
      expect((await other.list(requesterRole: 'admin')).map((t) => t.name), ['Theirs']);
      expect(await templates.get(requesterRole: 'admin', templateId: theirs.id), isNull);
      await expectLater(templates.updateDetails(requesterRole: 'admin', actor: _admin, templateId: theirs.id, name: 'Taken', description: ''), throwsA(isA<WebsiteContentException>()));
      await expectLater(templates.setThumbnail(requesterRole: 'admin', actor: _admin, templateId: theirs.id, mediaId: _thumb), throwsA(isA<WebsiteContentException>()));
      await expectLater(templates.delete(requesterRole: 'admin', templateId: theirs.id), throwsA(isA<WebsiteContentException>()));
      expect((await db.collection(WebsiteCollections.templates).doc(theirs.id).get()).data()!['name'], 'Theirs', reason: 'untouched');
      expect(await other.get(requesterRole: 'admin', templateId: mine.id), isNull);
    });

    test('rename, describe, replace and remove the thumbnail (its image tracked), delete', () async {
      final t = await templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Programmes');
      await templates.updateDetails(requesterRole: 'admin', actor: _admin, templateId: t.id, name: 'Our programmes', description: 'For the home page');
      await templates.setThumbnail(requesterRole: 'admin', actor: _admin, templateId: t.id, mediaId: _thumb);
      var stored = (await templates.get(requesterRole: 'admin', templateId: t.id))!;
      expect((stored.name, stored.description, stored.thumbnailMediaId), ('Our programmes', 'For the home page', _thumb));
      expect(stored.mediaIds, unorderedEquals([_photo, _thumb]));
      await templates.setThumbnail(requesterRole: 'admin', actor: _admin, templateId: t.id, mediaId: null);
      stored = (await templates.get(requesterRole: 'admin', templateId: t.id))!;
      expect(stored.thumbnailMediaId, isNull);
      expect(stored.mediaIds, [_photo]);
      expect(stored.block.toMap(), _richSection(), reason: 'the content never changes with its details');
      await expectLater(templates.updateDetails(requesterRole: 'admin', actor: _admin, templateId: t.id, name: '', description: ''), throwsA(isA<WebsiteContentException>()));
      await templates.delete(requesterRole: 'admin', templateId: t.id);
      expect(await templates.list(requesterRole: 'admin'), isEmpty);
    });

    test('an image a template uses can’t be deleted from the media library; free once the template is gone', () async {
      final service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
      final t = await service.templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Programmes', thumbnailMediaId: _thumb);
      expect(await service.pagesUsing(requesterRole: 'admin', mediaId: _photo), contains('the “Programmes” template'));
      expect(await service.pagesUsing(requesterRole: 'admin', mediaId: _thumb), contains('the “Programmes” template'), reason: 'its thumbnail too');
      await expectLater(service.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: _photo), throwsA(isA<WebsiteContentException>()));
      await service.templates.delete(requesterRole: 'admin', templateId: t.id);
      expect(await service.pagesUsing(requesterRole: 'admin', mediaId: _photo), isEmpty);
    });
  });

  group('when the templates can’t be read (no school claim, offline)', () {
    late _RefusingFirestore refusing;

    /// The template library saved, then its queries refused.
    Future<WebsiteContentAdminService> refused() async {
      refusing = _RefusingFirestore();
      for (final id in [_photo, 'media_free_0001']) {
        await refusing.collection(WebsiteCollections.media).doc(id).set(_media(id));
      }
      final service = WebsiteContentAdminService(firestore: refusing, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
      await service.templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Programmes');
      refusing.refuseTemplates = true;
      await expectLater(refusing.collection(WebsiteCollections.templates).where('schoolId', isEqualTo: 'default_school').get(), throwsA(isA<FirebaseException>()));
      return service;
    }

    test('deleting an image is refused (it might be in a template), with the reason', () async {
      final service = await refused();
      await expectLater(
        service.deleteMedia(requesterRole: 'admin', actor: _admin, mediaId: 'media_free_0001'),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('template library couldn’t be checked'))),
      );
      expect((await refusing.collection(WebsiteCollections.media).doc('media_free_0001').get()).exists, isTrue, reason: 'kept');
    });

    test('withdrawing consent still works at once', () async {
      final service = await refused();
      final media = (await service.getMedia(requesterRole: 'admin', mediaId: _photo))!;
      await service.updateMediaDetails(
        requesterRole: 'admin',
        actor: _admin,
        mediaId: _photo,
        alt: media.alt,
        caption: media.caption,
        category: media.category,
        inGallery: media.inGallery,
        focalX: media.focalX,
        focalY: media.focalY,
        consentConfirmed: false,
      );
      final stored = (await refusing.collection(WebsiteCollections.media).doc(_photo).get()).data()!;
      expect(stored['consentConfirmed'], isFalse, reason: 'withdrawn');
      expect(await service.pagesUsing(requesterRole: 'admin', mediaId: _photo), contains(WebsiteContentAdminService.templatesUncheckedLabel), reason: 'the uses list says what it couldn’t check');
    });
  });

  // ------------------------------------------------------------ editor
  group('in the page editor', () {
    late WebsiteContentAdminService service;

    setUp(() {
      service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<String> pageWith(String slug, List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: LocalizedText(en: 'Page $slug', ta: 'பக்கம்'), slug: slug);
      await db.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    Future<void> open(WidgetTester tester, String id, {Size size = const Size(1400, 2400)}) async {
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

    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;

    /// Selects block [id] in the structure by its title line (its action
    /// buttons can wrap onto the row's middle in a narrow panel).
    Future<void> select(WidgetTester tester, String id) async {
      await tester.ensureVisible(key('website-block-$id-select'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(key('website-block-$id-select')) + const Offset(40, 14));
      await tester.pumpAndSettle();
    }
    Future<Map<String, dynamic>> stored(String id) async => (await db.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!;

    Future<void> heading(WidgetTester tester, String blockId, String text) async {
      final f = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('website-block-$blockId-heading-en') == true);
      await tester.ensureVisible(f);
      await tester.enterText(f, text);
      await tester.pumpAndSettle();
    }

    testWidgets('save a section on one page, find it, insert it on another, edit the copy on its own, save, reopen, publish', (tester) async {
      final source = await pageWith('source', [_richSection()]);
      final target = await pageWith('target', [
        {'id': 'b_intro0001', 'type': 'text', 'v': 1, 'heading': {'en': 'Welcome', 'ta': ''}, 'body': {'en': 'Hello.', 'ta': ''}},
      ]);

      // Save as template (structure: on the selected row; canvas toolbar too).
      await open(tester, source);
      await select(tester, 'b_rich00001');
      expect(key('website-canvas-b_rich00001-save-template'), findsOneWidget, reason: 'on the canvas toolbar');
      await tap(tester, key('website-block-b_rich00001-more'));
      await tap(tester, key('website-block-b_rich00001-save-template'));
      expect(key('website-template-save-dialog'), findsOneWidget);
      expect(tester.widget<TextField>(key('website-template-save-name')).controller!.text, 'Programmes', reason: 'the section’s name to start');
      await tester.enterText(key('website-template-save-name'), '');
      await tap(tester, key('website-template-save-confirm'));
      expect(find.text('Give the template a name.'), findsOneWidget);
      await tester.enterText(key('website-template-save-name'), 'Programmes band');
      await tester.enterText(key('website-template-save-description'), 'Three programmes with a button');
      await tap(tester, key('website-template-save-thumbnail-choose'));
      await tap(tester, key('website-choose-$_thumb'));
      await tap(tester, key('website-template-save-confirm'));
      expect(key('website-template-save-dialog'), findsNothing);
      expect(find.text('Saved “Programmes band” to the template library.'), findsOneWidget);
      final saved = (await templates.list(requesterRole: 'admin')).single;
      expect(saved.block.toMap(), _richSection());
      expect(saved.thumbnailMediaId, _thumb);
      expect(blocks(tester).single.toMap(), _richSection(), reason: 'the page itself is unchanged');

      // Another page: Add section → Browse section templates.
      await open(tester, target);
      await tap(tester, key('website-sections-add'));
      await tap(tester, key('website-sections-add-templates'));
      expect(key('website-templates'), findsOneWidget);
      expect(key('website-template-${saved.id}'), findsOneWidget);
      expect(find.text('Programmes band'), findsOneWidget);
      await tester.enterText(key('website-templates-search'), 'gallery');
      await tester.pumpAndSettle();
      expect(key('website-templates-empty'), findsOneWidget, reason: 'search');
      await tester.enterText(key('website-templates-search'), 'button programmes');
      await tester.pumpAndSettle();
      expect(key('website-template-${saved.id}'), findsOneWidget);

      // Preview per screen size, then insert.
      await tap(tester, key('website-template-${saved.id}-open-preview'));
      expect(key('website-template-preview-frame-desktop'), findsOneWidget);
      for (final s in ['tablet', 'mobile', 'desktop']) {
        await tap(tester, key('website-template-preview-$s'));
        expect(key('website-template-preview-frame-$s'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: s);
      }
      await tap(tester, key('website-template-preview-insert'));
      expect(key('website-templates'), findsNothing);
      final inserted = blocks(tester).last as StructuredBlock;
      expect(blocks(tester).first.id, 'b_intro0001', reason: 'existing content untouched');
      // Placed on this page, the section is given its own anchor id here
      // (as it is given new ids); the rest is the template's content.
      expect(SectionAnchors.stored(inserted), 'programmes', reason: 'an anchor id from its name, unique on this page');
      expect(_withoutIds(inserted.toMap()..remove(SectionAnchors.field)), _withoutIds(_richSection()));
      expect(_ids(inserted.toMap()).toSet().intersection(_ids(_richSection()).toSet()), isEmpty, reason: 'new ids');

      // Edit the copy: the template and the source page stay as they were.
      final firstText = inserted.columns('columns').first.blocks.first.id;
      await select(tester, firstText);
      await tap(tester, key('website-block-$firstText-edit'));
      await heading(tester, firstText, 'Toddler community');
      await tap(tester, key('website-custom-save-draft'));
      final draft = await stored(target);
      final copy = BlockRegistry.parseList(draft['blocks']).last as StructuredBlock;
      expect((copy.columns('columns').first.blocks.first as StructuredBlock).text('heading').en, 'Toddler community');
      expect((copy.columns('columns').first.blocks.first as StructuredBlock).text('heading').ta, 'குழந்தை', reason: 'Tamil kept');
      expect((await templates.get(requesterRole: 'admin', templateId: saved.id))!.block.toMap(), _richSection(), reason: 'the template is unchanged');
      expect(BlockRegistry.parseList((await stored(source))['blocks']).single.toMap(), _richSection(), reason: 'the source page is unchanged');

      // Reopen and publish.
      await open(tester, target);
      expect(blocks(tester).last.toMap(), copy.toMap());
      await tap(tester, key('website-custom-publish'));
      if (key('website-custom-publish-confirm').evaluate().isNotEmpty) await tap(tester, key('website-custom-publish-confirm'));
      final live = (await db.collection(WebsiteCollections.livePages).doc(target).get()).data()!;
      final published = BlockRegistry.parseList(live['blocks']);
      expect(published.last.toMap()['columns'][0]['blocks'][0]['heading'], {'en': 'Toddler community', 'ta': 'குழந்தை'});
      expect(published.last.toMap()['tabletColumns'], '2');

      // Deleting the template leaves the pages as they are.
      await templates.delete(requesterRole: 'admin', templateId: saved.id);
      expect(BlockRegistry.parseList((await stored(target))['blocks']).last.toMap(), copy.toMap());
    });

    testWidgets('a block template goes into a column; sections and blocks with columns aren’t offered there', (tester) async {
      final textBlock = _parse(_richSection()).columns('columns').first.blocks.first;
      final text = await templates.save(requesterRole: 'admin', actor: _admin, block: textBlock, name: 'Toddler text');
      final section = await templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Programmes band');
      final columns = await templates.save(requesterRole: 'admin', actor: _admin, block: BlockRegistry.create(BlockRegistry.columns), name: 'Two columns block');
      final page = await pageWith('columns', [
        {
          'id': 'b_sec00001',
          'type': 'section',
          'v': 1,
          'layout': '1:1',
          'columns': [
            {'id': 'c_col00001', 'blocks': []},
            {'id': 'c_col00002', 'blocks': []},
          ],
        },
      ]);
      await open(tester, page);
      await tap(tester, key('website-column-c_col00002-add'));
      await tap(tester, key('website-column-c_col00002-add-templates'));
      expect(key('website-template-${section.id}'), findsNothing, reason: 'block templates only');
      expect(tester.widget<FilledButton>(key('website-template-${columns.id}-insert')).onPressed, isNull, reason: 'no columns inside columns');
      await tap(tester, key('website-template-${text.id}-insert'));
      final cols = (blocks(tester).single as StructuredBlock).columns('columns');
      expect((cols[0].blocks.length, cols[1].blocks.length), (0, 1));
      expect(_withoutIds(cols[1].blocks.single.toMap()), _withoutIds(textBlock.toMap()));
      expect(cols[1].blocks.single.id, isNot(textBlock.id));

      // Add block (on the page) offers block templates; Add section, sections.
      await tap(tester, key('website-blocks-add'));
      await tap(tester, key('website-blocks-add-templates'));
      expect(key('website-template-${text.id}'), findsOneWidget);
      expect(key('website-template-${section.id}'), findsNothing);
      await tap(tester, key('website-template-${columns.id}-insert'));
      expect(blocks(tester).last.type, 'columns', reason: 'a columns block may go on the page');
    });

    testWidgets('a template from a newer version, or with a block this version can’t show, is listed but can’t be inserted', (tester) async {
      Map<String, dynamic> stored(String name, {int schemaVersion = 1, Map<String, dynamic>? block}) => {
            'schoolId': 'default_school',
            'schemaVersion': schemaVersion,
            'kind': 'block',
            'blockType': block?['type'] ?? 'text',
            'name': name,
            'block': block ?? {'id': 'b_text00009', 'type': 'text', 'v': 1, 'heading': {'en': 'Hi', 'ta': ''}},
            'mediaIds': [],
          };
      await db.collection(WebsiteCollections.templates).doc('t_newer').set(stored('Newer', schemaVersion: 2));
      await db.collection(WebsiteCollections.templates).doc('t_unknown').set(stored('Unknown', block: {'id': 'b_holo0001', 'type': 'hologram', 'v': 1}));
      await db.collection(WebsiteCollections.templates).doc('t_newer_block').set(stored('Newer block', block: {'id': 'b_text00008', 'type': 'text', 'v': 99}));
      final page = await pageWith('compat', const []);
      await open(tester, page);
      await tap(tester, key('website-blocks-add'));
      await tap(tester, key('website-blocks-add-templates'));
      for (final id in ['t_newer', 't_unknown', 't_newer_block']) {
        expect(key('website-template-$id'), findsOneWidget, reason: '$id listed');
        expect(tester.widget<FilledButton>(key('website-template-$id-insert')).onPressed, isNull, reason: '$id can’t be inserted');
        expect(key('website-template-$id-why-not'), findsOneWidget, reason: '$id says why');
      }
      expect(tester.widget<Text>(key('website-template-t_newer-why-not')).data, contains('newer version'));
      await tap(tester, key('website-template-t_unknown-open-preview'));
      expect(tester.widget<FilledButton>(key('website-template-preview-insert')).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('manage: rename, describe, replace the thumbnail, delete (pages keep their copies)', (tester) async {
      final t = await templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Programmes');
      final page = await pageWith('manage', const []);
      await open(tester, page);
      await tap(tester, key('website-sections-add'));
      await tap(tester, key('website-sections-add-templates'));
      final k = 'website-template-${t.id}';

      await tap(tester, key('$k-menu'));
      await tap(tester, key('$k-details'));
      await tester.enterText(key('website-template-details-name'), 'Our programmes');
      await tester.enterText(key('website-template-details-description'), 'For the home page');
      await tap(tester, key('website-template-details-save'));
      expect(tester.widget<Text>(key('$k-name')).data, 'Our programmes');
      expect(tester.widget<Text>(key('$k-description')).data, 'For the home page');

      await tap(tester, key('$k-menu'));
      await tap(tester, key('$k-thumbnail'));
      await tap(tester, key('website-choose-$_thumb'));
      expect((await templates.get(requesterRole: 'admin', templateId: t.id))!.thumbnailMediaId, _thumb);
      await tap(tester, key('$k-menu'));
      expect(find.text('Replace thumbnail'), findsOneWidget);
      await tap(tester, key('$k-remove-thumbnail'));
      expect((await templates.get(requesterRole: 'admin', templateId: t.id))!.thumbnailMediaId, isNull);

      await tap(tester, key('$k-insert'));
      final copy = blocks(tester).single.toMap();
      await tap(tester, key('website-sections-add'));
      await tap(tester, key('website-sections-add-templates'));
      await tap(tester, key('$k-menu'));
      await tap(tester, key('$k-delete'));
      expect(find.textContaining('keep their own copies'), findsOneWidget);
      await tap(tester, key('website-template-delete-confirm'));
      expect(key('website-templates-empty'), findsOneWidget);
      await tap(tester, key('website-templates-close'));
      expect(blocks(tester).single.toMap(), copy, reason: 'the inserted copy stays');
      expect(await templates.list(requesterRole: 'admin'), isEmpty);
    });

    testWidgets('the library and preview fit desktop, tablet and phone windows', (tester) async {
      await templates.save(requesterRole: 'admin', actor: _admin, block: _parse(_richSection()), name: 'Programmes', description: 'A longer description that wraps onto a second line in a narrow card');
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
      for (final size in const [Size(1400, 1000), Size(820, 1100), Size(390, 844)]) {
        await tester.pumpWidget(const SizedBox()); // a fresh app (no dialogs left open) per size
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(size),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open'),
                  onPressed: () => showTemplateLibrary(context, service: templates, user: _admin, library: const [], media: const {}),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(key('open'));
        await tester.pumpAndSettle();
        final shown = (await templates.list(requesterRole: 'admin')).single;
        expect(tester.widget<Text>(key('website-template-${shown.id}-name')).data, 'Programmes', reason: '$size');
        expect(tester.takeException(), isNull, reason: 'library at $size');
        final t = (await templates.list(requesterRole: 'admin')).single;
        await tester.tap(key('website-template-${t.id}-open-preview'));
        await tester.pumpAndSettle();
        for (final s in ['tablet', 'mobile', 'desktop']) {
          await tester.tap(key('website-template-preview-$s'));
          await tester.pumpAndSettle();
          expect(key('website-template-preview-frame-$s'), findsOneWidget, reason: '$s preview at $size');
        }
        expect(tester.takeException(), isNull, reason: 'preview at $size');
        final dialog = tester.getRect(key('website-template-preview'));
        expect(dialog.left >= 0 && dialog.right <= size.width, isTrue, reason: 'the preview fits the window at $size');
      }
    });
  });
}
