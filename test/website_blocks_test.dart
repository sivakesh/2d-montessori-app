// Page-builder block foundation (P2a):
// - Stable ids: generated format, uniqueness, legacy/derived ids accepted.
// - Blocks, nested items and columns parse and save back unchanged, with
//   every language key; unknown types, newer versions, unknown keys and
//   wrongly shaped values are kept exactly as stored.
// - Legacy custom-page sections convert to blocks deterministically (ids
//   kept or derived) and back.
// - Duplicating gives fresh ids everywhere; validation covers fields,
//   items, links (same safety checks), ids across the page, nesting, counts
//   and size.
// - Pages: existing pages are stored exactly as before; a page saved with
//   blocks keeps them (including unsupported ones) through the service and
//   the existing editor; block images count for usage and publishing.
// - Public rendering: each block type; hidden, unsupported and invalid
//   blocks and unpublished images are left out one by one; unsafe links
//   aren't shown; columns stack on mobile.
import 'dart:convert';
import 'dart:math';
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
import 'package:montessori_app/modules/public_website/content/blocks/block_ids.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_limits.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/field_spec.dart';
import 'package:montessori_app/modules/public_website/content/blocks/legacy_sections.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
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

String _json(Object? v) => jsonEncode(v);

/// [v] as plain JSON data, for structural comparison (map key order is not
/// meaningful in Firestore).
Object? _plain(Object? v) => jsonDecode(jsonEncode(v));

/// A page's worth of stored blocks covering every type, nested items and
/// columns, with Tamil and Hindi text.
List<Map<String, dynamic>> _storedBlocks() => [
      {'id': 'b_text000001', 'type': 'text', 'v': 1, 'heading': {'en': 'About', 'ta': 'பற்றி', 'hi': 'परिचय'}, 'body': {'en': 'Hello', 'ta': ''}},
      {'id': 'b_image00001', 'type': 'image', 'v': 1, 'mediaId': 'm1', 'alt': {'en': '', 'ta': ''}, 'caption': {'en': 'Garden', 'ta': ''}, 'aspect': '4:3', 'style': {'background': 'sage'}},
      {
        'id': 'b_cols000001', 'type': 'columns', 'v': 1, 'layout': '1:2',
        'columns': [
          {'id': 'c_one0000001', 'blocks': [{'id': 'b_inner00001', 'type': 'text', 'v': 1, 'heading': {'en': 'Left', 'ta': ''}, 'body': {'en': '', 'ta': ''}}]},
          {'id': 'c_two0000001', 'blocks': [{'id': 'b_inner00002', 'type': 'image', 'v': 1, 'mediaId': 'm2', 'alt': {'en': '', 'ta': ''}, 'caption': {'en': '', 'ta': ''}, 'aspect': '1:1'}]},
        ],
      },
      {
        'id': 'b_cta0000001', 'type': 'cta', 'v': 1, 'heading': {'en': 'Visit us', 'ta': ''}, 'body': {'en': '', 'ta': ''},
        'buttons': [{'id': 'i_btn0000001', 'label': {'en': 'Book', 'ta': 'பதிவு', 'fr': 'Réserver'}, 'target': '/contact', 'variant': 'primary'}],
      },
      {
        'id': 'b_btns000001', 'type': 'buttons', 'v': 1, 'align': 'center',
        'buttons': [
          {'id': 'i_btn0000002', 'label': {'en': 'Programs', 'ta': ''}, 'target': '/programs', 'variant': 'secondary'},
          {'id': 'i_btn0000003', 'label': {'en': 'Partner', 'ta': ''}, 'target': 'https://example.org/', 'variant': 'primary'},
        ],
      },
      {
        'id': 'b_gal0000001', 'type': 'gallery', 'v': 1, 'heading': {'en': 'Photos', 'ta': ''}, 'columns': '3',
        'images': [{'id': 'i_img0000001', 'mediaId': 'm1'}, {'id': 'i_img0000002', 'mediaId': 'm3'}],
      },
      {'id': 'b_div0000001', 'type': 'divider', 'v': 1, 'size': 'large'},
    ];

WebsiteMedia _media(String id, {bool published = true}) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      alt: LocalizedText(en: 'Alt $id'),
      status: published ? WebsiteMediaStatus.published : WebsiteMediaStatus.draft,
      consentConfirmed: true,
    );

void main() {
  group('ids', () {
    test('generated ids: prefix and 10 base-36 characters, unique', () {
      final ids = {for (var i = 0; i < 5000; i++) BlockIds.block()};
      expect(ids, hasLength(5000));
      for (final id in ids.take(50)) {
        expect(id, matches(RegExp(r'^b_[a-z0-9]{10}$')));
        expect(BlockIds.isGenerated(id) && BlockIds.isValid(id), isTrue);
      }
      expect(BlockIds.item(), startsWith('i_'));
      expect(BlockIds.column(), startsWith('c_'));
      expect(BlockIds.row(), startsWith('r_'));
      expect(BlockIds.block(random: Random(1)), BlockIds.block(random: Random(1)), reason: 'deterministic with a seeded generator');
    });

    test('legacy and derived ids stay valid; separators and blanks are not', () {
      for (final ok in ['lq3x9abc', 'lq3x9abc__img', 'Xy12AbCdEf', 'main-home', 'i_btn0000001']) {
        expect(BlockIds.isValid(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'a/b', 'a.b', 'a b', 'x' * 65, 'é']) {
        expect(BlockIds.isValid(bad), isFalse, reason: bad);
      }
    });
  });

  group('parsing and saving', () {
    test('every block type, nested items and columns round-trip exactly, with all language keys', () {
      final stored = _storedBlocks();
      final blocks = BlockRegistry.parseList(stored);
      expect(blocks.whereType<StructuredBlock>(), hasLength(7));
      expect(_plain(BlockRegistry.toMapList(blocks)), _plain(stored));
      final cta = blocks[3] as StructuredBlock;
      expect(cta.items('buttons').single.text('label').textFor('fr'), 'Réserver');
      final cols = blocks[2] as StructuredBlock;
      expect((cols.columns('columns')[1].blocks.single as StructuredBlock).string('mediaId'), 'm2');
      expect(BlockRegistry.validate(blocks), isEmpty);
    });

    test('unknown types, newer versions, missing types and non-block entries are kept exactly', () {
      final stored = <Object?>[
        {'id': 'b_carousel01', 'type': 'carousel', 'v': 1, 'slides': [{'id': 'x', 'title': {'en': 'One'}}]},
        {'id': 'b_textv9_001', 'type': 'text', 'v': 9, 'heading': {'en': 'Future'}, 'newField': true},
        {'id': 'b_notype0001', 'heading': {'en': 'No type'}},
        'not a block',
        {'type': 'text', 'heading': {'en': 'No id'}},
      ];
      final blocks = BlockRegistry.parseList(stored);
      expect(blocks.every((b) => b is UnsupportedBlock), isTrue);
      expect(_json(BlockRegistry.toMapList(blocks)), _json(stored));
      expect(BlockRegistry.validate(blocks), isEmpty, reason: 'kept, not reported as errors');
    });

    test('unknown keys and wrongly shaped values inside known blocks and items are kept, and reported', () {
      final stored = [
        {
          'id': 'b_cta0000002', 'type': 'cta', 'v': 1, 'heading': 42, 'body': {'en': 'x', 'ta': ''}, 'futureKey': {'a': 1},
          'buttons': [{'id': 'i_btn0000009', 'label': {'en': 'Go', 'ta': ''}, 'target': ['bad'], 'variant': 'primary', 'icon': 'star'}],
        },
        {'id': 'b_gal0000002', 'type': 'gallery', 'v': 1, 'heading': {'en': 'G', 'ta': ''}, 'columns': '3', 'images': ['m1', 'm2']},
      ];
      final blocks = BlockRegistry.parseList(stored);
      expect(_plain(BlockRegistry.toMapList(blocks)), _plain(stored));
      final errors = BlockRegistry.validate(blocks);
      expect(errors.any((e) => e.contains('“heading” has a value this app can’t read')), isTrue);
      expect(errors.any((e) => e.contains('Button 1: “target” has a value this app can’t read')), isTrue);
      expect(errors.any((e) => e.contains('“images” has a value this app can’t read')), isTrue);
      expect(blocks.where(WebsiteBlocksView.isShown), isEmpty, reason: 'never shown publicly');
    });

    test('editing a field keeps the other languages and drops only that field’s preserved value', () {
      final block = BlockRegistry.parse(_storedBlocks().first) as StructuredBlock;
      final edited = block.withValue('heading', block.text('heading').copyWith(en: 'About us'));
      expect(edited.text('heading').textFor('hi'), 'परिचय');
      final broken = BlockRegistry.parse({'id': 'b_text000009', 'type': 'text', 'v': 1, 'heading': 7}) as StructuredBlock;
      expect(broken.toMap()['heading'], 7);
      expect(broken.withValue('heading', const LocalizedText(en: 'Fixed')).toMap()['heading'], {'en': 'Fixed', 'ta': ''});
    });
  });

  group('legacy sections', () {
    final sections = [
      const CustomPageSection(id: 'lq3x9aaa', type: CustomSectionType.text, heading: LocalizedText(en: 'Welcome', ta: 'வரவேற்பு', others: {'hi': 'स्वागत'}), body: LocalizedText(en: 'Body')),
      const CustomPageSection(id: 'lq3x9bbb', type: CustomSectionType.imageText, heading: LocalizedText(en: 'Garden'), body: LocalizedText(en: 'Outdoor'), mediaId: 'm1', imageOnRight: true),
      const CustomPageSection(id: 'lq3x9ccc', type: CustomSectionType.imageGrid, heading: LocalizedText(en: 'Photos'), mediaIds: ['m1', 'm2', 'm1']),
      const CustomPageSection(id: 'lq3x9ddd', type: CustomSectionType.callToAction, heading: LocalizedText(en: 'Visit'), body: LocalizedText(en: 'Come'), buttonLabel: LocalizedText(en: 'Book', ta: 'பதிவு'), target: '/contact'),
    ];

    test('convert with kept and derived ids; the same ids every time', () {
      final blocks = LegacySections.toBlocks(sections);
      expect([for (final b in blocks) b.id], ['lq3x9aaa', 'lq3x9bbb', 'lq3x9ccc', 'lq3x9ddd']);
      expect([for (final b in blocks) b.type], ['text', 'columns', 'gallery', 'cta']);
      final cols = (blocks[1] as StructuredBlock).columns('columns');
      expect([for (final c in cols) c.id], ['lq3x9bbb__c1', 'lq3x9bbb__c2']);
      expect([for (final c in cols) c.blocks.single.id], ['lq3x9bbb__txt', 'lq3x9bbb__img'], reason: 'image on the right');
      expect([for (final i in (blocks[2] as StructuredBlock).items('images')) i.id], ['lq3x9ccc__m_m1', 'lq3x9ccc__m_m2', 'lq3x9ccc__m_m1_2']);
      expect((blocks[3] as StructuredBlock).items('buttons').single.id, 'lq3x9ddd__btn');
      expect((blocks[0] as StructuredBlock).text('heading').textFor('hi'), 'स्वागत');
      expect(_json(BlockRegistry.toMapList(LegacySections.toBlocks(sections))), _json(BlockRegistry.toMapList(blocks)));
      expect(BlockRegistry.validate(blocks), isEmpty);
    });

    test('and back to the same sections', () {
      final back = [for (final b in LegacySections.toBlocks(sections)) LegacySections.toSection(b)!];
      expect(_json([for (final s in back) s.toMap()]), _json([for (final s in sections) s.toMap()]));
      expect(LegacySections.toSection(BlockRegistry.parse(_storedBlocks()[4])), isNull, reason: 'a buttons block has no section form');
    });
  });

  group('operations and validation', () {
    test('duplicate: fresh ids for the block, its items, columns and nested blocks; same content', () {
      final blocks = BlockRegistry.parseList(_storedBlocks());
      for (final original in blocks) {
        final copy = BlockRegistry.duplicate(original);
        Set<String> ids(WebsiteBlock b) => {
              for (final x in BlockRegistry.flatten([b])) x.id,
              if (b is StructuredBlock)
                for (final f in b.definition.fields) ...[
                  if (f is ItemsFieldSpec) for (final i in b.items(f.key)) i.id,
                  if (f is ColumnsFieldSpec) for (final c in b.columns(f.key)) c.id,
                ],
            };
        expect(ids(copy).intersection(ids(original)), isEmpty, reason: original.type);
        expect(BlockRegistry.validate([original, copy]), isEmpty, reason: 'no clashing ids');
        String content(WebsiteBlock b) => _json(b.toMap()).replaceAll(RegExp(r'"[bic]_[a-z0-9]{10}"'), '"ID"');
        expect(content(copy), content(original));
      }
      final created = BlockRegistry.create(BlockRegistry.columns);
      expect(created.columns('columns'), hasLength(2));
      expect(BlockRegistry.create(BlockRegistry.cta).items('buttons'), hasLength(1));
    });

    test('field, item, link, nesting, id, count and size problems', () {
      final blocks = BlockRegistry.parseList([
        {'id': 'b_a', 'type': 'text', 'v': 1},
        {'id': 'b_b', 'type': 'image', 'v': 1, 'aspect': 'wide'},
        {'id': 'b_c', 'type': 'cta', 'v': 1, 'heading': {'en': 'x' * 121}, 'buttons': [{'id': 'i_1', 'label': {'en': 'Go'}, 'target': 'javascript:alert(1)'}]},
        {'id': 'b_d', 'type': 'buttons', 'v': 1, 'buttons': [{'id': 'i_2', 'label': {'en': 'Staff'}, 'target': 'https://2dmontessori.com/#/app'}]},
        {'id': 'b_e', 'type': 'gallery', 'v': 1, 'images': []},
        {'id': 'b_f', 'type': 'columns', 'v': 1, 'layout': '1:1:1', 'columns': [{'id': 'c_1', 'blocks': [{'id': 'b_g', 'type': 'columns', 'v': 1, 'columns': [{'id': 'c_9', 'blocks': [{'id': 'b_z', 'type': 'divider', 'v': 1}]}]}]}]},
        {'id': 'b_a', 'type': 'divider', 'v': 1},
        {'id': 'bad id', 'type': 'divider', 'v': 1, 'style': {'background': 'neon'}},
        {'id': 'b_h', 'type': 'buttons', 'v': 1, 'buttons': [{'id': 'i_3', 'label': {'others': ''}, 'target': '/admissions'}, {'id': 'i_3', 'label': {'en': 'B', 'ta': 'ப', 'hi': 'x' * 41}, 'target': '/'}]},
      ]);
      final errors = BlockRegistry.validate(blocks).join('\n');
      expect(errors, contains('Block 1 (Text): add a heading or some text.'));
      expect(errors, contains('Block 2 (Image): choose an image.'));
      expect(errors, contains('Block 2 (Image): “wide” is not a shape option.'));
      expect(errors, contains('Block 3 (Call to action): Heading must be 120 characters or fewer.'));
      expect(errors, contains('Block 3 (Call to action): Button 1: Links must start with https://'));
      expect(errors, contains('Block 4 (Buttons): Button 1: This is a protected part of the app'));
      expect(errors, contains('Block 5 (Photo gallery): add at least 1 image.'));
      expect(errors, contains('Block 6 (Columns): it needs 3 columns for this layout.'));
      expect(errors, contains('Block 6 (Columns): columns can’t contain columns.'));
      expect(errors, contains('blocks can be nested only 1 level deep'));
      expect(errors, contains('the id “b_a” is used more than once'));
      expect(errors, contains('Block 8 (Divider): its id is not valid.'));
      expect(errors, contains('“neon” is not a background option'));
      expect(errors, contains('Button 1: enter button label in English.'));
      expect(errors, contains('the id “i_3” is used more than once'));
      expect(errors, contains('Button 2: Button label must be 40 characters or fewer.'), reason: 'every language is limited');

      final many = [for (var i = 0; i < 41; i++) BlockRegistry.create(BlockRegistry.divider)];
      expect(BlockRegistry.validate(many), contains('A page can have at most 40 blocks.'));
      final big = [BlockRegistry.create(BlockRegistry.text).withValue('body', LocalizedText(en: 'x' * 2000))];
      expect(BlockRegistry.validate(big, limits: const BlockLimits(maxDocumentBytes: 1024)).last, contains('too large'));
    });

    test('images used: blocks, columns and grid items, without repeats', () {
      expect(BlockRegistry.referencedMedia(BlockRegistry.parseList(_storedBlocks())), ['m1', 'm2', 'm3']);
    });
  });

  group('pages', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    test('existing pages are stored exactly as before (no block fields)', () {
      const page = CustomPage(id: 'p', slug: 'open-day', title: LocalizedText(en: 'Open day'), sections: [CustomPageSection(id: 's1', type: CustomSectionType.text, heading: LocalizedText(en: 'Hi'))]);
      expect(page.toContentMap().keys.toSet(), {'kind', 'slug', 'title', 'intro', 'heroMediaId', 'sections', 'showInNavigation', 'navOrder', 'mediaIds'});
      expect(page.usesBlocks, isFalse);
      expect([for (final b in page.effectiveBlocks) b.id], ['s1'], reason: 'sections as blocks, in memory only');
    });

    test('a page with blocks: parsed, saved back (unsupported blocks too), validated, images counted', () {
      final stored = [..._storedBlocks(), {'id': 'b_future0001', 'type': 'timeline', 'v': 1, 'items': []}];
      final page = CustomPage.fromMap('p', {'kind': 'custom', 'slug': 'tour', 'title': {'en': 'Tour', 'ta': ''}, 'sections': [], 'schemaVersion': 2, 'blocks': stored});
      expect(page.usesBlocks, isTrue);
      expect(_plain(page.toContentMap()['blocks']), _plain(stored));
      expect(page.toContentMap()['schemaVersion'], 2);
      expect(page.referencedMedia, ['m1', 'm2', 'm3']);
      expect(page.validationErrors(), isEmpty);
      expect(page.copyWith(title: const LocalizedText(en: 'Tour 2')).blocks, same(page.blocks));
      final broken = page.copyWith(blocks: () => [...page.blocks!, BlockRegistry.create(BlockRegistry.image)]);
      expect(broken.validationErrors().single, contains('choose an image'));
    });

    Future<String> blockPage() async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Tour'), slug: 'tour');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({
        'schemaVersion': 2,
        'blocks': [..._storedBlocks(), {'id': 'b_future0001', 'type': 'timeline', 'v': 1}],
      });
      return created.id;
    }

    test('the service keeps blocks through save and publish; block images must be published, and count as used', () async {
      final id = await blockPage();
      final page = (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page.copyWith(title: const LocalizedText(en: 'Tour 2026')));
      final saved = (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!;
      expect(_plain(saved['blocks']), _plain([..._storedBlocks(), {'id': 'b_future0001', 'type': 'timeline', 'v': 1}]));
      expect(saved['mediaIds'], ['m1', 'm2', 'm3']);
      await expectLater(service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page), throwsA(isA<WebsiteContentException>()), reason: 'its images aren’t published');
      for (final m in ['m1', 'm2', 'm3']) {
        await firestore.collection(WebsiteCollections.media).doc(m).set({'url': 'https://x/$m.jpg', 'storagePath': 'p', 'status': 'published', 'consentConfirmed': true, 'alt': {'en': 'a', 'ta': ''}});
      }
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      expect(_plain((await firestore.collection(WebsiteCollections.livePages).doc(id).get()).data()!['blocks']), _plain(saved['blocks']));
      expect(await service.pagesUsing(requesterRole: 'admin', mediaId: 'm2'), {'the “Tour” page'});
    });

    testWidgets('the existing page editor keeps a block page’s blocks and doesn’t offer section editing', (tester) async {
      final id = await blockPage();
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: service, user: _admin, pageId: id)),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('website-custom-uses-blocks')), findsOneWidget);
      expect(find.byKey(const Key('website-custom-add-section')), findsNothing);
      final before = _plain((await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!['blocks']);
      await tester.enterText(find.byKey(const Key('website-custom-title-en')), 'Tour 2026');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('website-custom-save-draft')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('website-custom-save-draft')));
      await tester.pumpAndSettle();
      final after = (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!;
      expect(after['title']['en'], 'Tour 2026');
      expect(_plain(after['blocks']), before);
    });
  });

  group('public rendering', () {
    final media = {for (final id in ['m1', 'm2', 'm3']) id: _media(id)};

    Future<void> pump(WidgetTester tester, List<WebsiteBlock> blocks, {Size size = const Size(1280, 3000), Map<String, WebsiteMedia>? library, PublicLanguage language = PublicLanguage.english}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WebsiteBlocksView(blocks: blocks, media: library ?? media, language: language)))));
      await tester.pumpAndSettle();
    }

    Finder block(String id) => find.byKey(Key('public-block-$id'));

    testWidgets('every type renders; text in the visitor’s language with fallback', (tester) async {
      await pump(tester, BlockRegistry.parseList(_storedBlocks()));
      expect(tester.takeException(), isNull);
      for (final id in ['b_text000001', 'b_image00001', 'b_cols000001', 'b_cta0000001', 'b_btns000001', 'b_gal0000001', 'b_div0000001']) {
        expect(block(id), findsOneWidget, reason: id);
      }
      expect(find.text('About'), findsOneWidget);
      expect(find.byKey(const Key('public-block-button-i_btn0000001')), findsOneWidget);
      expect(find.text('Garden'), findsOneWidget, reason: 'caption');
      await pump(tester, BlockRegistry.parseList(_storedBlocks()), language: const PublicLanguage('hi', nativeName: 'हिन्दी', englishName: 'Hindi'));
      expect(find.text('परिचय'), findsOneWidget);
      expect(find.text('Visit us'), findsOneWidget, reason: 'no Hindi: English');
    });

    testWidgets('hidden, unsupported and invalid blocks are left out one by one; the rest still shows', (tester) async {
      final blocks = BlockRegistry.parseList([
        {'id': 'b_ok00000001', 'type': 'text', 'v': 1, 'heading': {'en': 'Shown'}},
        {'id': 'b_hidden0001', 'type': 'text', 'v': 1, 'hidden': true, 'heading': {'en': 'Hidden'}},
        {'id': 'b_future0001', 'type': 'carousel', 'v': 1, 'title': {'en': 'Future'}},
        {'id': 'b_badlink001', 'type': 'buttons', 'v': 1, 'buttons': [{'id': 'i_x', 'label': {'en': 'Bad'}, 'target': 'javascript:alert(1)'}]},
        {'id': 'b_broken0001', 'type': 'text', 'v': 1, 'heading': 12},
        {'id': 'b_ok00000002', 'type': 'text', 'v': 1, 'heading': {'en': 'Also shown'}},
      ]);
      await pump(tester, blocks);
      expect(tester.takeException(), isNull);
      expect(find.text('Shown'), findsOneWidget);
      expect(find.text('Also shown'), findsOneWidget);
      for (final id in ['b_hidden0001', 'b_future0001', 'b_badlink001', 'b_broken0001']) {
        expect(block(id), findsNothing, reason: id);
      }
      expect(find.text('Bad'), findsNothing);
    });

    testWidgets('only published images; a grid with none and no heading, and empty columns, are left out', (tester) async {
      final library = {'m1': _media('m1')}; // m2 and m3 are not published
      await pump(tester, BlockRegistry.parseList([
        {'id': 'b_img_pub001', 'type': 'image', 'v': 1, 'mediaId': 'm1'},
        {'id': 'b_img_draft1', 'type': 'image', 'v': 1, 'mediaId': 'm2'},
        {'id': 'b_gal_none01', 'type': 'gallery', 'v': 1, 'images': [{'id': 'i_1', 'mediaId': 'm3'}]},
        {'id': 'b_cols_none1', 'type': 'columns', 'v': 1, 'layout': '1:1', 'columns': [
          {'id': 'c_1', 'blocks': [{'id': 'b_in1', 'type': 'image', 'v': 1, 'mediaId': 'm2'}]},
          {'id': 'c_2', 'blocks': []},
        ]},
      ]), library: library);
      expect(block('b_img_pub001'), findsOneWidget);
      expect(block('b_img_draft1'), findsNothing);
      expect(block('b_gal_none01'), findsNothing);
      expect(block('b_cols_none1'), findsNothing);
    });

    testWidgets('columns side by side on desktop, stacked on mobile', (tester) async {
      final blocks = BlockRegistry.parseList([_storedBlocks()[2]]);
      Rect col(String id) => tester.getRect(find.byKey(Key('public-block-column-$id')));
      await pump(tester, blocks);
      expect(col('c_one0000001').right, lessThan(col('c_two0000001').left));
      expect(col('c_two0000001').width, greaterThan(col('c_one0000001').width * 1.5), reason: '1:2');
      await pump(tester, blocks, size: const Size(390, 3000));
      expect(col('c_one0000001').bottom, lessThanOrEqualTo(col('c_two0000001').top));
    });
  });
}
