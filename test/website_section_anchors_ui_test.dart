// Section anchors on screen: published sections carry their anchor ids, a
// section link scrolls to its section (same page, another page, an address
// opened directly, sections that load late, a header kept clear), Back
// returns; the editor's link field (page / section of this page / section
// of another page, typed addresses) and Section anchor ID field; and the
// page editor end to end (nothing stored for untouched sections, a
// duplicate gets its own anchor, Links to check after deleting a section).
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/core/navigation/app_router.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/data/website_image_processor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_link_field.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/section_anchors.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_link_targets.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/public_section_anchors.dart';

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

Map<String, dynamic> _text(String id, String heading) => {
      'id': id,
      'type': 'text',
      'v': 1,
      'heading': {'en': heading, 'ta': ''},
      'body': {'en': List.filled(12, 'A paragraph about $heading that takes some room on the page.').join(' '), 'ta': ''},
    };

Map<String, dynamic> _section(String id, String name, {String? anchor, bool hidden = false, List<Map<String, dynamic>>? blocks}) => {
      'id': id,
      'type': 'section',
      'v': 1,
      'name': {'en': name, 'ta': ''},
      'anchor': ?anchor,
      if (hidden) 'hidden': true,
      'layout': '1',
      'style': {'paddingTop': '96', 'paddingBottom': '96'},
      'columns': [
        {'id': 'c_$id', 'blocks': blocks ?? [_text('b_t_$id', name)]},
      ],
    };

Map<String, dynamic> _buttons(String id, List<String> targets) => {
      'id': id,
      'type': 'buttons',
      'v': 1,
      'align': 'start',
      'buttons': [
        for (final (i, t) in targets.indexed) {'id': 'i_${id}_$i', 'label': {'en': 'Go $i', 'ta': ''}, 'target': t, 'variant': 'primary'},
      ],
    };

List<WebsiteBlock> _blocks(List<Map<String, dynamic>> raw) => BlockRegistry.parseList(raw);

/// A public page as PublicScaffold lays it out: the anchor scope (from the
/// route's `#section`) around the page's scroll view.
class _TestPage extends StatelessWidget {
  const _TestPage({required this.blocks, this.headerOffset = 0});

  final List<WebsiteBlock> blocks;
  final double headerOffset;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PublicAnchorScope(
          initialAnchor: PublicRoutes.anchorOf(ModalRoute.of(context)?.settings.name),
          headerOffset: headerOffset,
          child: SingleChildScrollView(
            child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, fullBleed: true),
          ),
        ),
      );
}

/// Sections that appear only after a while (a page whose content loads).
class _LatePage extends StatefulWidget {
  const _LatePage({required this.blocks});
  final List<WebsiteBlock> blocks;

  @override
  State<_LatePage> createState() => _LatePageState();
}

class _LatePageState extends State<_LatePage> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) => _TestPage(blocks: _loaded ? widget.blocks : const []);
}

final _longPage = [
  _buttons('b_top', ['#enquire', '/admissions#fees', '/programs#enquire']),
  _section('b_s1', 'Welcome', anchor: 'welcome'),
  _section('b_s2', 'Programs'),
  _section('b_s3', 'Old offer', anchor: 'offer', hidden: true),
  _section('b_s4', 'Fees', anchor: 'fees'),
  _section('b_s5', 'Enquire', anchor: 'enquire'),
  _section('b_s6', 'Copy of enquire', anchor: 'enquire'),
  _section('b_s7', 'Footer note'),
];

Finder _key(String k) => find.byKey(Key(k));

class _Pushes extends NavigatorObserver {
  int count = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
}

double _topOf(WidgetTester tester, String anchor) => tester.getTopLeft(_key('public-section-anchor-$anchor')).dy;

Future<void> _surface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('published sections and scrolling', () {
    testWidgets('sections carry their anchor ids; hidden ones none; an anchor is never rendered twice', (tester) async {
      await _surface(tester, const Size(1200, 800));
      await tester.pumpWidget(MaterialApp(home: _TestPage(blocks: _blocks(_longPage))));
      await tester.pumpAndSettle();
      for (final a in ['welcome', 'programs', 'fees', 'enquire', 'footer-note']) {
        expect(_key('public-section-anchor-$a'), findsOneWidget, reason: a);
      }
      expect(_key('public-section-anchor-offer'), findsNothing, reason: 'hidden: not drawn');
      expect(find.byType(PublicSectionAnchor), findsNWidgets(5), reason: 'the second “enquire” isn’t given the same anchor');
      final semantics = tester.widgetList<Semantics>(find.descendant(of: find.byType(PublicSectionAnchor), matching: find.byType(Semantics))).map((s) => s.properties.identifier).whereType<String>().toList();
      expect(semantics.toSet(), {'welcome', 'programs', 'fees', 'enquire', 'footer-note'});
      expect(semantics.length, semantics.toSet().length, reason: 'no duplicate identifiers');
    });

    testWidgets('a same-page link scrolls to its section (#enquire, and this page’s own address with it)', (tester) async {
      await _surface(tester, const Size(1200, 800));
      final observer = _Pushes();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        initialRoute: '/programs',
        onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => _TestPage(blocks: _blocks(_longPage))),
      ));
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'enquire'), greaterThan(800), reason: 'below the fold');
      await tester.tap(_key('public-block-button-i_b_top_0'));
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'enquire'), moreOrLessEquals(0, epsilon: 1), reason: 'scrolled to the section’s top');
      final pushed = observer.count;
      expect(ModalRoute.of(tester.element(_key('public-section-anchor-enquire')))!.settings.name, '/programs');

      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 5000));
      await tester.pumpAndSettle();
      await tester.tap(_key('public-block-button-i_b_top_2'));
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'enquire'), moreOrLessEquals(0, epsilon: 1), reason: '/programs#enquire on /programs');
      expect(observer.count, pushed, reason: 'no new page for a section of this page');
    });

    testWidgets('a header that stays on screen is kept clear above the section', (tester) async {
      await _surface(tester, const Size(1200, 800));
      await tester.pumpWidget(MaterialApp(home: _TestPage(blocks: _blocks(_longPage), headerOffset: 80)));
      await tester.pumpAndSettle();
      await tester.tap(_key('public-block-button-i_b_top_0'));
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'enquire'), moreOrLessEquals(80, epsilon: 1));
    });

    testWidgets('another page’s section: the page opens at it; Back returns', (tester) async {
      await _surface(tester, const Size(1200, 800));
      final other = _blocks([_section('b_o1', 'Intro'), _section('b_o2', 'More'), _section('b_o3', 'Fees', anchor: 'fees'), _section('b_o4', 'End')]);
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/programs',
        onGenerateRoute: (s) => MaterialPageRoute(
          settings: s,
          builder: (_) => PublicRoutes.pathOf(s.name ?? '') == '/admissions' ? _TestPage(blocks: other) : _TestPage(blocks: _blocks(_longPage)),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(_key('public-block-button-i_b_top_1'));
      await tester.pumpAndSettle();
      expect(ModalRoute.of(tester.element(_key('public-section-anchor-fees')))!.settings.name, '/admissions#fees', reason: 'the address keeps the section');
      expect(_topOf(tester, 'fees'), moreOrLessEquals(0, epsilon: 1));
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(_key('public-block-button-i_b_top_1'), findsOneWidget, reason: 'back on the first page');
    });

    testWidgets('an address with a section opens at it, also when the sections load late', (tester) async {
      await _surface(tester, const Size(1200, 800));
      await tester.pumpWidget(MaterialApp(
        initialRoute: '/contact#fees',
        onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => _LatePage(blocks: _blocks(_longPage))),
      ));
      await tester.pump();
      expect(_key('public-section-anchor-fees'), findsNothing, reason: 'not loaded yet');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_topOf(tester, 'fees'), moreOrLessEquals(0, epsilon: 1));
    });

    test('the app opens public pages at a section from their address (and Back/Forward entries)', () {
      String name(String route) => AppLocation.parse(route).name;
      expect(name('/teacher-training#enquire'), '/teacher-training#enquire');
      expect(AppLocation.parse('/teacher-training#enquire').anchor, 'enquire');
      expect(name('/#programs'), '/#programs');
      expect(name('/admissions#enquire'), '/admissions#enquire');
      expect(name('/pages/Open-Day#faq'), '/pages/open-day#faq');
      expect(name('/gallery#albums'), '/gallery#albums');
      expect(AppLocation.parse('/app#x').management, isTrue, reason: 'only public pages open at a section');
      expect(AppLocation.parse('/app#x').anchor, isNull);
      expect(name('/admissions#Not-Valid'), '/admissions', reason: 'not a section anchor: the page itself');
      expect(name('/teacher-training'), '/teacher-training', reason: 'plain addresses unchanged');
    });
  });

  group('editor fields', () {
    final here = _blocks([_section('b_e1', 'Enquire', anchor: 'enquire'), _section('b_e2', 'Fees')]);
    final site = WebsiteLinkSite(pages: [
      WebsiteLinkPage(route: '/admissions', label: 'Admissions', blocks: here),
      WebsiteLinkPage(route: '/teacher-training', label: 'Teacher Training', blocks: _blocks([_section('b_t1', 'Course'), _section('b_t2', 'Enquire', anchor: 'enquire')])),
      const WebsiteLinkPage(route: '/programs', label: 'Programs'),
    ]);

    Future<List<String>> pumpLink(WidgetTester tester, {String value = '', WebsiteLinkSite? linkSite, bool scoped = true}) async {
      await _surface(tester, const Size(900, 1400));
      final changes = <String>[];
      final field = WebsiteLinkField(keyPrefix: 'link', label: 'Button link', value: value, generation: 0, onChanged: changes.add);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: scoped ? WebsiteLinkScope(site: linkSite ?? site, route: '/admissions', blocks: here, child: field) : field,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return changes;
    }

    Future<void> choose(WidgetTester tester, String dropdown, String item) async {
      await tester.tap(_key(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    String address(WidgetTester tester) => tester.widget<EditableText>(find.descendant(of: _key('link-0'), matching: find.byType(EditableText))).controller.text;

    String? error(WidgetTester tester) => tester.widget<TextField>(find.descendant(of: _key('link-0'), matching: find.byType(TextField))).decoration?.errorText;

    testWidgets('a section of this page: chosen by name, stored as #anchor', (tester) async {
      final changes = await pumpLink(tester);
      expect(find.text('A page of this website'), findsOneWidget, reason: 'an empty link starts as a page');
      await choose(tester, 'link-kind', 'A section of this page');
      await choose(tester, 'link-section', 'Enquire (#enquire)');
      expect(changes.last, '#enquire');
      expect(address(tester), '#enquire');
      expect(error(tester), isNull);
      expect(find.text('Fees (#fees)'), findsNothing, reason: 'menu closed');
    });

    testWidgets('a section of another page: page first, then its section; /page#anchor', (tester) async {
      final changes = await pumpLink(tester);
      await choose(tester, 'link-kind', 'A section of another page');
      await choose(tester, 'link-page', 'Teacher Training — /teacher-training');
      await choose(tester, 'link-section', 'Enquire (#enquire)');
      expect(changes.last, '/teacher-training#enquire');
      expect(error(tester), isNull, reason: 'the failure this fixes: /teacher-training#enquire is accepted');
    });

    testWidgets('a page; typed addresses; missing pages and sections are named', (tester) async {
      final changes = await pumpLink(tester);
      await choose(tester, 'link-page', 'Programs — /programs');
      expect(changes.last, '/programs');
      await tester.enterText(_key('link-0'), '/teacher-training#nope');
      await tester.pumpAndSettle();
      expect(error(tester), contains('There is no section “#nope” on Teacher Training'));
      await tester.enterText(_key('link-0'), '/pages/missing');
      await tester.pumpAndSettle();
      expect(error(tester), 'There is no page at /pages/missing.');
      await tester.enterText(_key('link-0'), 'javascript:alert(1)');
      await tester.pumpAndSettle();
      expect(error(tester), contains('Links must start with https://'));
      await tester.enterText(_key('link-0'), 'https://example.org/apply');
      await tester.pumpAndSettle();
      expect(error(tester), isNull);
      expect(changes.last, 'https://example.org/apply');
    });

    testWidgets('existing links open as their kind; email and phone are kept as typed', (tester) async {
      await pumpLink(tester, value: 'mailto:office@example.org');
      expect(find.text('An email address (mailto:)'), findsOneWidget);
      expect(address(tester), 'mailto:office@example.org');
      expect(error(tester), isNull);
      await pumpLink(tester, value: 'tel:+911234567890');
      expect(find.text('A phone number (tel:)'), findsOneWidget);
      await pumpLink(tester, value: '/teacher-training#enquire');
      expect(find.text('A section of another page'), findsOneWidget);
      expect(find.text('Enquire (#enquire)'), findsOneWidget, reason: 'its section shown chosen');
    });

    testWidgets('without the site (it couldn’t be read): the address field only, checked for its format', (tester) async {
      final changes = await pumpLink(tester, scoped: false, value: '#enquire');
      expect(_key('link-kind'), findsNothing);
      expect(error(tester), isNull);
      await tester.enterText(_key('link-0'), '/teacher-training#Bad Anchor');
      await tester.pumpAndSettle();
      expect(error(tester), contains('not a section anchor ID'));
      expect(changes.last, '/teacher-training#Bad Anchor');
    });

    testWidgets('Section anchor ID: shown, edited, unique on the page, regenerated, never cleared; a change warns of its links', (tester) async {
      await _surface(tester, const Size(900, 1400));
      final section = here.first as StructuredBlock;
      final changes = <String>[];
      final withLinks = WebsiteLinkSite(pages: [
        ...site.pages,
        WebsiteLinkPage(route: '/contact', label: 'Contact', blocks: _blocks([_buttons('b_c1', ['/admissions#enquire'])])),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WebsiteLinkScope(
            site: withLinks,
            route: '/admissions',
            blocks: here,
            child: WebsiteAnchorField(keyPrefix: 'anchor', section: section, generation: 0, onChanged: changes.add),
          ),
        ),
      ));
      String? err() => tester.widget<TextField>(find.descendant(of: _key('anchor-0'), matching: find.byType(TextField))).decoration?.errorText;
      expect(find.text('enquire'), findsOneWidget);
      expect(find.textContaining('link to this section with #enquire or /admissions#enquire'), findsOneWidget);
      expect(_key('anchor-links'), findsNothing);

      await tester.enterText(_key('anchor-0'), 'fees');
      await tester.pumpAndSettle();
      expect(err(), isNull, reason: '“Fees” has no stored anchor yet: its own is derived, so this one is free');
      await tester.enterText(_key('anchor-0'), 'Bad Id');
      await tester.pumpAndSettle();
      expect(err(), contains('lowercase letters'));
      await tester.enterText(_key('anchor-0'), 'apply-now');
      await tester.pumpAndSettle();
      expect(err(), isNull);
      expect(changes.last, 'apply-now');
      expect(find.textContaining('1 link on this website leads to “#enquire”'), findsOneWidget, reason: 'the Contact button');

      final before = changes.length;
      await tester.enterText(_key('anchor-0'), '');
      await tester.pumpAndSettle();
      expect(changes.length, before, reason: 'an empty anchor is never saved');
      expect(err(), 'Enter an anchor ID.');

      await tester.tap(_key('anchor-regenerate'));
      await tester.pumpAndSettle();
      expect(changes.last, 'enquire', reason: 'from its name, unique among the other sections');
    });

    testWidgets('Section anchor ID: another section’s stored anchor is refused', (tester) async {
      await _surface(tester, const Size(900, 1000));
      final blocks = _blocks([_section('b_x1', 'Enquire', anchor: 'enquire'), _section('b_x2', 'Fees', anchor: 'fees')]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WebsiteLinkScope(
            site: null,
            route: '/admissions',
            blocks: blocks,
            child: WebsiteAnchorField(keyPrefix: 'anchor', section: blocks[1] as StructuredBlock, generation: 0, onChanged: (_) {}),
          ),
        ),
      ));
      await tester.enterText(_key('anchor-0'), 'enquire');
      await tester.pumpAndSettle();
      expect(find.textContaining('Another section of this page (Enquire) uses “enquire”'), findsOneWidget);
    });
  });

  group('in the page editor', () {
    late FakeFirebaseFirestore db;
    late WebsiteContentAdminService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: db, storage: MockFirebaseStorage(), imageProcessor: _FakeProcessor());
    });

    Future<String> pageWith(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Anchors', ta: ''), slug: 'anchors');
      await db.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'blocks': blocks});
      return created.id;
    }

    Future<void> open(WidgetTester tester, String id) async {
      await _surface(tester, const Size(1400, 2400));
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

    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(_key('website-custom-blocks')).blocks;

    /// Selects a section by its structure row's title (a click on the
    /// canvas inside a section selects the block there).
    Future<void> selectSection(WidgetTester tester, String id) async {
      await tester.ensureVisible(_key('website-block-$id-select'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(_key('website-block-$id-select')) + const Offset(40, 14));
      await tester.pumpAndSettle();
    }

    Future<List<Object?>> stored(FirebaseFirestore db, String collection, String id) async => (await db.collection(collection).doc(id).get()).data()!['blocks'] as List;

    testWidgets('a page from before: saved exactly as stored; a duplicate gets its own anchor; deleting the section shows the link that breaks; publish', (tester) async {
      final raw = [
        _section('b_sec1', 'Enquire', blocks: [_text('b_txt1', 'Ask us')]),
        _buttons('b_btn1', ['#enquire']),
      ];
      final id = await pageWith(raw);
      await open(tester, id);
      expect(_key('website-custom-link-count'), findsNothing, reason: '#enquire leads to the section (its anchor is derived from its name)');

      await tap(tester, _key('website-custom-save-draft'));
      expect(BlockRegistry.parseList(await stored(db, WebsiteCollections.pageDrafts, id)).map((b) => b.toMap()).toList(), _blocks(raw).map((b) => b.toMap()).toList(),
          reason: 'nothing new stored for untouched sections');
      expect((await stored(db, WebsiteCollections.pageDrafts, id)).first, isNot(contains('anchor')));

      // Duplicate the section: the copy gets “enquire-2”; the original is untouched.
      await selectSection(tester, 'b_sec1');
      await tap(tester, _key('website-canvas-b_sec1-duplicate'));
      final copy = blocks(tester)[1] as StructuredBlock;
      expect(copy.type, 'section');
      expect(SectionAnchors.stored(copy), 'enquire-2');
      expect(SectionAnchors.stored(blocks(tester).first as StructuredBlock), '');
      expect(SectionAnchors.effective(blocks(tester))['b_sec1'], 'enquire');

      // Delete the original: the button's #enquire now leads nowhere.
      await selectSection(tester, 'b_sec1');
      await tap(tester, _key('website-canvas-b_sec1-delete'));
      await tap(tester, _key('website-block-delete-confirm'));
      expect(blocks(tester).map((b) => b.id), [copy.id, 'b_btn1']);
      expect(SectionAnchors.stored(blocks(tester).first as StructuredBlock), 'enquire-2', reason: 'the copy keeps its anchor');
      expect(find.text('1 link to check'), findsOneWidget);
      expect(find.descendant(of: _key('website-custom-link-checks'), matching: find.textContaining('There is no section “#enquire” on this page')), findsOneWidget);

      // A warning only: the draft saves, and publishing gives visitors the copy's anchor.
      await tap(tester, _key('website-custom-save-draft'));
      await tap(tester, _key('website-custom-publish'));
      final live = BlockRegistry.parseList(await stored(db, WebsiteCollections.livePages, id));
      expect(SectionAnchors.effective(live), {copy.id: 'enquire-2'});
      expect(_key('website-custom-unsaved'), findsNothing);
    });
  });
}
