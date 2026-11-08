// The page block limit as a school setting (Website → Pages → Editor
// settings): stored as `school_settings/{schoolId}.websiteEditor`,
// default 150, 10–500; changed by admins only, with a revision check and
// an audit entry; the visual editor follows it while open; saving stops a
// page growing past it, but a page already over a lowered limit can still
// be edited, rearranged, saved and published; moves never count as
// growth; duplicates and nested blocks count; columns have no separate
// limit (the screenshot's "This column (or the page) is full" was the old
// six-per-column limit). Synthetic test data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/modules/admin/settings/models/school_settings_model.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_editor_settings.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/block_list_ops.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_editor_settings_card.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_limits.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
final _teacher = AppUser(id: '9000000003', phone: '9000000003', role: 'teacher', isActive: true, name: 'Teacher');

String _pad(int n) => n.toString().padLeft(6, '0');

Map<String, dynamic> _text(String id) => {
      'id': id,
      'type': 'text',
      'v': 1,
      'heading': {'en': 'Heading $id', 'ta': 'தலைப்பு'},
      'body': {'en': 'Words.', 'ta': ''},
    };

/// A section with [perColumn] text blocks in each of its columns.
Map<String, dynamic> _section(int n, {List<int> perColumn = const [3]}) => {
      'id': 'b_s${_pad(n)}',
      'type': 'section',
      'v': 1,
      'layout': List.filled(perColumn.length, '1').join(':'),
      'name': {'en': 'Section $n', 'ta': ''},
      'columns': [
        for (final (c, count) in perColumn.indexed)
          {
            'id': 'c_s${_pad(n)}$c',
            'blocks': [for (var j = 0; j < count; j++) _text('b_s${_pad(n)}c${c}t$j')],
          },
      ],
    };

/// [loose] top-level texts (each 1 block).
List<Map<String, dynamic>> _texts(int loose, {int from = 0}) => [for (var i = from; i < from + loose; i++) _text('b_t${_pad(i)}')];

List<WebsiteBlock> _parse(List<Map<String, dynamic>> raw) => BlockRegistry.parseList(raw);
int _count(List<WebsiteBlock> b) => BlockRegistry.flatten(b).length;

/// Settings that can't be read (say, the security rules don't allow it).
class _UnreadableSettings extends WebsiteEditorSettingsService {
  _UnreadableSettings() : super(firestore: FakeFirebaseFirestore());
  @override
  Stream<WebsiteEditorSettings> watch() => Stream.error(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
  @override
  Future<WebsiteEditorSettings> load() async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
}

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;
  late WebsiteEditorSettingsService settings;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    settings = service.editorSettings;
  });

  Finder key(String k) => find.byKey(Key(k));
  DocumentReference<Map<String, dynamic>> record() => firestore.collection('school_settings').doc(kDefaultSchoolId);

  Future<void> setLimit(int value) async {
    final current = await settings.load();
    await settings.update(requesterRole: 'admin', requesterSchoolId: kDefaultSchoolId, actor: _admin, maxBlocksPerPage: value, expectedRevision: current.revision);
  }

  // ------------------------------------------------------------ setting
  group('the setting', () {
    test('1. none saved: the default of 150; bounds 10–500; an unusable stored value falls back to the default, reported', () async {
      final s = await settings.load();
      expect([s.maxBlocksPerPage, s.isDefault, s.revision, s.storedValueInvalid], [150, true, 0, false]);
      expect(s.limits, BlockLimits.defaults);
      expect([for (final v in [null, 9, 10, 150, 500, 501]) WebsiteEditorSettings.validateMaxBlocks(v) == null], [false, false, true, true, true, false]);
      for (final bad in [0, -5, 9000, 'lots', 12.5]) {
        final read = WebsiteEditorSettings.fromMap(kDefaultSchoolId, {'maxBlocksPerPage': bad, 'revision': 3});
        expect([read.maxBlocksPerPage, read.storedValueInvalid], [150, true], reason: '$bad');
      }
      expect(WebsiteEditorSettings.fromMap(kDefaultSchoolId, {'maxBlocksPerPage': 200.0}).maxBlocksPerPage, 200, reason: 'a whole number stored as a double');
      expect([BlockLimits.defaultPageMaxBlocks, BlockLimits.minPageMaxBlocks, BlockLimits.safetyMaxBlocks], [150, 10, 500]);
    });

    test('a change: only its part of the school record, a revision and an audit entry; a stale revision is refused', () async {
      await record().set({'schoolName': 'Little Steps', 'publicFormSubmissions': {'enabled': true, 'revision': 4}});
      await setLimit(240);
      final data = (await record().get()).data()!;
      expect(data['schoolName'], 'Little Steps');
      expect(data['publicFormSubmissions'], {'enabled': true, 'revision': 4}, reason: 'other settings kept');
      expect([data['websiteEditor']['maxBlocksPerPage'], data['websiteEditor']['revision'], data['websiteEditor']['updatedByName']], [240, 1, 'Test admin']);
      final audit = (await record().collection('audit').get()).docs.single.data();
      expect([audit['action'], audit['maxBlocksPerPage'], audit['previousMaxBlocksPerPage'], audit['byName']], ['website_page_block_limit', 240, 150, 'Test admin']);
      await expectLater(
        settings.update(requesterRole: 'admin', requesterSchoolId: kDefaultSchoolId, actor: _admin, maxBlocksPerPage: 300, expectedRevision: 0),
        throwsA(isA<WebsiteEditorSettingsConflict>().having((e) => e.current.maxBlocksPerPage, 'current', 240)),
      );
      await expectLater(
        settings.update(requesterRole: 'admin', requesterSchoolId: kDefaultSchoolId, actor: _admin, maxBlocksPerPage: 5, expectedRevision: 1),
        throwsArgumentError,
      );
      expect((await settings.load()).maxBlocksPerPage, 240);
    });

    test('12. only an administrator of the school can change it; nothing is written otherwise', () async {
      for (final (role, school) in [('teacher', kDefaultSchoolId), ('parent', kDefaultSchoolId), ('staff', kDefaultSchoolId), ('admin', 'another_school')]) {
        await expectLater(
          settings.update(requesterRole: role, requesterSchoolId: school, actor: _admin, maxBlocksPerPage: 300, expectedRevision: 0),
          throwsA(isA<UnauthorizedSchoolSettingsException>()),
          reason: '$role / $school',
        );
      }
      expect((await record().get()).exists, isFalse);
    });

    Future<void> pumpCard(WidgetTester tester, AppUser user, {WebsiteEditorSettingsService? s}) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WebsiteEditorSettingsCard(service: s ?? settings, user: user))));
      await tester.pumpAndSettle();
    }

    testWidgets('2. an administrator changes it in Website → Pages → Editor settings; invalid values are explained, nothing saved', (tester) async {
      await pumpCard(tester, _admin);
      expect(tester.widget<Text>(key('website-editor-settings-limit')).data, 'Blocks per page: 150');
      expect(tester.widget<Text>(key('website-editor-settings-detail')).data, startsWith('The default.'));
      await tester.tap(key('website-editor-settings-change'));
      await tester.pumpAndSettle();
      await tester.enterText(key('website-editor-settings-field'), '5');
      await tester.tap(key('website-editor-settings-save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number from 10 to 500.'), findsOneWidget);
      expect((await tester.runAsync(() => record().get()))!.exists, isFalse);
      await tester.enterText(key('website-editor-settings-field'), '220');
      await tester.tap(key('website-editor-settings-save'));
      await tester.pumpAndSettle();
      expect(key('website-editor-settings-dialog'), findsNothing);
      expect(tester.widget<Text>(key('website-editor-settings-limit')).data, 'Blocks per page: 220');
      expect(tester.widget<Text>(key('website-editor-settings-detail')).data, startsWith('Set by Test admin'));
      expect((await tester.runAsync(() => settings.load()))!.maxBlocksPerPage, 220);
    });

    testWidgets('12. a non-administrator sees the limit but no Change', (tester) async {
      await pumpCard(tester, _teacher);
      expect(tester.widget<Text>(key('website-editor-settings-limit')).data, 'Blocks per page: 150');
      expect(key('website-editor-settings-change'), findsNothing);
    });

    testWidgets('an unreadable setting is said so; the default applies', (tester) async {
      await pumpCard(tester, _admin, s: _UnreadableSettings());
      expect(tester.widget<Text>(key('website-editor-settings-detail')).data, contains('couldn’t be read'));
    });
  });

  // ------------------------------------------------------------ operations
  group('block operations under a configured limit', () {
    test('4–6. up to the limit and no further; a raised limit allows more at once', () {
      final twelve = BlockLimits.forPage(12);
      var blocks = _parse(_texts(11));
      expect(BlockListOps.canAdd(blocks, BlockRegistry.text, limits: twelve), isTrue);
      blocks = BlockListOps.insert(blocks, BlockPath(blocks.length), BlockRegistry.create(BlockRegistry.text));
      expect(_count(blocks), 12);
      expect(BlockListOps.pageHasRoom(blocks, limits: twelve), isFalse);
      expect(BlockListOps.canAdd(blocks, BlockRegistry.text, limits: twelve), isFalse);
      expect(BlockListOps.canAdd(blocks, BlockRegistry.text, limits: BlockLimits.forPage(13)), isTrue);
      expect(BlockListOps.canAdd(blocks, BlockRegistry.section, limits: BlockLimits.forPage(13)), isFalse, reason: 'a section needs itself, a column block and one more');
    });

    test('8. moving at capacity: within a column, between columns and on the page; the count never changes', () {
      final blocks = _parse([_section(1, perColumn: [3, 2]), ..._texts(2)]); // 1 + 5 + 2 = 8
      final full = BlockLimits.forPage(8);
      expect(BlockListOps.pageHasRoom(blocks, limits: full), isFalse);
      final inColumn = BlockPath.inside(BlockPath(0), 0, 0);
      expect(BlockListOps.canMoveToColumn(blocks, inColumn, 1, limits: full), isTrue);
      final (moved, to) = BlockListOps.moveToColumn(blocks, inColumn, 1, limits: full);
      expect([to.column, _count(moved)], [1, 8]);
      final (down, _) = BlockListOps.move(moved, BlockPath(0), 1);
      expect([down[1].id, _count(down)], ['b_s000001', 8]);
      expect(BlockRegistry.validate(down, limits: full), isEmpty);
    });

    test('9. duplicating counts the copy and everything in it: allowed below the limit, refused at it', () {
      final blocks = _parse([_section(1, perColumn: [2]), ..._texts(2)]); // 1 + 2 + 2 = 5
      expect(BlockListOps.canDuplicate(blocks, BlockPath(0), limits: BlockLimits.forPage(10)), isTrue, reason: '5 + 3 ≤ 10');
      expect(BlockListOps.canDuplicate(blocks, BlockPath(0), limits: BlockLimits.forPage(7)), isFalse, reason: 'the section copy brings 3');
      expect(BlockListOps.canDuplicate(blocks, BlockPath.inside(BlockPath(0), 0, 0), limits: BlockLimits.forPage(6)), isTrue);
      expect(BlockListOps.canDuplicate(blocks, BlockPath.inside(BlockPath(0), 0, 0), limits: BlockLimits.forPage(5)), isFalse);
    });

    test('10. nested sections and columns: no separate column limit (the old six); only the page limit stops them', () {
      final blocks = _parse([_section(1, perColumn: [6, 1])]); // 1 + 7 = 8
      final column = BlockPath(0);
      expect(BlockLimits.defaults.hasColumnLimit, isFalse);
      expect(BlockListOps.columnAtHasRoom(blocks, column, 0), isTrue, reason: 'a seventh block in a column of six: the screenshot');
      expect(BlockListOps.canInsertInColumn(blocks, column, 0, BlockRegistry.create(BlockRegistry.text), limits: BlockLimits.forPage(9)), isTrue);
      expect(BlockListOps.canInsertInColumn(blocks, column, 0, BlockRegistry.create(BlockRegistry.text), limits: BlockLimits.forPage(8)), isFalse);
      // A row inside a section's column: itself and room for a block in its inner column.
      expect(BlockListOps.canInsertInColumn(blocks, column, 1, ColumnOps.newRow(1), limits: BlockLimits.forPage(9)), isFalse);
      expect(BlockListOps.canInsertInColumn(blocks, column, 1, ColumnOps.newRow(1), limits: BlockLimits.forPage(10)), isTrue);
      // An explicit column limit is still honoured where given.
      expect(BlockListOps.columnAtHasRoom(blocks, column, 0, limits: const BlockLimits(maxColumnBlocks: 6)), isFalse);
    });
  });

  // ------------------------------------------------------------ saving
  group('11. save and publish', () {
    Future<String> pageWith(List<Map<String, dynamic>> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Limits', ta: 'வரம்பு'), slug: 'limits');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    Future<CustomPage> draft(String id) async => (await service.getCustomPage(requesterRole: 'admin', pageId: id))!.draft;

    test('a page may not grow past the limit; at or under it saves', () async {
      await setLimit(12);
      final id = await pageWith(_texts(10));
      final page = await draft(id);
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page.copyWith(blocks: () => _parse(_texts(12))));
      await expectLater(
        service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page.copyWith(blocks: () => _parse(_texts(13)))),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', allOf(contains('13 blocks'), contains('limit of 12'), contains('Editor settings')))),
      );
      expect(_count((await draft(id)).blocks!), 12, reason: 'nothing written');
      await setLimit(20);
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page.copyWith(blocks: () => _parse(_texts(13))));
      expect(_count((await draft(id)).blocks!), 13, reason: 'a raised limit applies at once');
    });

    test('7. a lowered limit: existing blocks kept; saving, shrinking and publishing still work; growing does not', () async {
      final id = await pageWith(_texts(30));
      await setLimit(10);
      final page = await draft(id);
      expect(_count(page.blocks!), 30, reason: 'nothing removed by lowering the limit');
      // Edited (same count) and rearranged: saved.
      final edited = [..._parse(_texts(30)).reversed];
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page.copyWith(blocks: () => edited));
      expect((await draft(id)).blocks!.first.id, 'b_t000029');
      // Published as it is.
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: await draft(id));
      expect(((await firestore.collection(WebsiteCollections.livePages).doc(id).get()).data()!['blocks'] as List), hasLength(30));
      // Shrunk: saved; then growing back past the limit is refused.
      final fewer = await draft(id);
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: fewer.copyWith(blocks: () => fewer.blocks!.take(20).toList()));
      await expectLater(
        service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: fewer.copyWith(blocks: () => _parse(_texts(21)))),
        throwsA(isA<WebsiteContentException>()),
      );
      expect(_count((await draft(id)).blocks!), 20);
    });

    test('built-in pages: the same rule for their drafts and publishing', () async {
      await setLimit(10);
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: _parse(_texts(10)));
      await expectLater(
        service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: _parse(_texts(11))),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('limit of 10'))),
      );
      await expectLater(
        service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: _parse(_texts(11))),
        throwsA(isA<WebsiteContentException>()),
      );
      expect((await firestore.collection(WebsiteCollections.livePages).doc(BuiltInPage.contact.id).get()).exists, isFalse, reason: 'nothing published');
    });

    test('an unreadable setting never blocks saving: only the safety ceiling applies', () async {
      final unreadable = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), editorSettings: _UnreadableSettings());
      await unreadable.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: _parse(_texts(200)));
      await expectLater(
        unreadable.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.contact, blocks: _parse(_texts(BlockLimits.safetyMaxBlocks + 1))),
        throwsA(isA<WebsiteContentException>().having((e) => e.message, 'message', contains('at most 500 blocks'))),
      );
    });
  });

  // ------------------------------------------------------------ editor
  group('the editor', () {
    Future<String> pageWith(List<Map<String, dynamic>> blocks, {WebsiteContentAdminService? via}) async {
      final s = via ?? service;
      final created = await s.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Editor', ta: ''), slug: 'editor');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    Future<void> open(WidgetTester tester, String id, {WebsiteContentAdminService? via}) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: WebsiteCustomPageEditorScreen(service: via ?? service, user: _admin, pageId: id)),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    String used(WidgetTester tester) => tester.widget<Text>(key('website-custom-uses-blocks')).data!;
    bool addEnabled(WidgetTester tester) => tester.widget<PopupMenuButton<BlockDefinition>>(key('website-blocks-add')).enabled;
    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;

    testWidgets('3–6. shows the configured limit, follows a change while open, adds up to it and explains when full', (tester) async {
      late String id;
      await tester.runAsync(() async {
        await setLimit(11);
        id = await pageWith(_texts(10));
      });
      await open(tester, id);
      expect(used(tester), startsWith('10 of 11 blocks used'));
      await tap(tester, key('website-blocks-add'));
      await tester.tap(key('website-blocks-add-text'));
      await tester.pumpAndSettle();
      expect(used(tester), startsWith('11 of 11'));
      expect(addEnabled(tester), isFalse);
      expect(find.byTooltip('This page has reached its limit of 11 blocks'), findsOneWidget);
      expect(tester.widget<Text>(key('website-custom-blocks-limit')).data, allOf(contains('room for 11 blocks'), contains('Editor settings')));

      // Raised in Editor settings (another screen or administrator): the
      // open editor follows at once, no rebuild or reload.
      await tester.runAsync(() => setLimit(40));
      await tester.pumpAndSettle();
      expect(used(tester), startsWith('11 of 40'));
      expect(addEnabled(tester), isTrue);
      await tap(tester, key('website-blocks-add'));
      await tester.tap(key('website-blocks-add-text'));
      await tester.pumpAndSettle();
      expect(_count(blocks(tester)), 12);
    });

    testWidgets('7. lowered below the page: nothing removed, editing and saving still work, adding is stopped and explained', (tester) async {
      late String id;
      await tester.runAsync(() async {
        id = await pageWith([_section(1, perColumn: [6]), ..._texts(13)]); // 7 + 13 = 20
        await setLimit(10);
      });
      await open(tester, id);
      expect(used(tester), startsWith('20 of 10'));
      expect(_count(blocks(tester)), 20);
      expect(addEnabled(tester), isFalse);
      expect(tester.widget<Text>(key('website-custom-blocks-limit')).data, allOf(contains('20 blocks, more than the limit of 10'), contains('edited, moved, deleted, saved and published')));
      final column = (blocks(tester).first as StructuredBlock).columns('columns').single;
      expect(find.byTooltip('This page has reached its limit of 10 blocks'), findsWidgets, reason: 'the page, not the column, is what is full');
      expect(column.blocks, hasLength(6));
      await tap(tester, key('website-custom-save-draft'));
      final stored = (await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()))!.data()!['blocks'] as List;
      expect(BlockRegistry.flatten(BlockRegistry.parseList(stored)).length, 20, reason: 'saved as it is');
    });

    testWidgets('the screenshot: a column of six takes another block when the page has room', (tester) async {
      late String id;
      await tester.runAsync(() async => id = await pageWith([_section(1, perColumn: [6]), ..._texts(16)])); // 23
      await open(tester, id);
      expect(used(tester), startsWith('23 of 150'));
      final column = (blocks(tester).first as StructuredBlock).columns('columns').single;
      final add = key('website-canvas-column-${column.id}-add');
      await tap(tester, add);
      await tester.tap(key('website-canvas-column-${column.id}-add-text'));
      await tester.pumpAndSettle();
      expect((blocks(tester).first as StructuredBlock).columns('columns').single.blocks, hasLength(7));
      expect(used(tester), startsWith('24 of 150'));
    });

    testWidgets('an unreadable setting: the default applies and the editor says so', (tester) async {
      final unreadable = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage(), editorSettings: _UnreadableSettings());
      late String id;
      await tester.runAsync(() async => id = await pageWith(_texts(3), via: unreadable));
      await open(tester, id, via: unreadable);
      expect(used(tester), startsWith('3 of 150'));
      expect(tester.widget<Text>(key('website-blocks-limit-setting-note')).data, contains('couldn’t be read, so the default of 150 applies'));
    });
  });
}
