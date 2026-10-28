// Visual builder styling: a page's own background, the top (utility) bar,
// the site typography, and a block's own font sizes. Defaults keep every
// existing page, header and block exactly as it was; settings go through
// the existing draft, publish and revert flows.
//
// Synthetic data only. The fake Firestore proves the app's behaviour, not
// deployed security rules.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_built_in_page_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_design_editors.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_provider.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/field_spec.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/built_in_pages.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_custom_page.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/content/website_page_style.dart';
import 'package:montessori_app/modules/public_website/content/website_site_layout.dart';
import 'package:montessori_app/modules/public_website/content/website_site_style.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/public_website_theme.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _desktop = Size(1400, 2400);
const _phone = Size(360, 1600);

StructuredBlock _text(String heading, String body, {Map<String, dynamic> style = const {}}) {
  final b = BlockRegistry.create(BlockRegistry.text);
  return b.copyWith(values: {...b.values, 'heading': LocalizedText(en: heading), 'body': LocalizedText(en: body)}, style: style);
}

StructuredBlock _hero(String title, {Map<String, dynamic> style = const {}}) {
  final b = BlockRegistry.create(BlockRegistry.hero);
  return b.copyWith(values: {...b.values, 'heading': LocalizedText(en: title)}, style: style);
}

/// The size of the text showing exactly [text].
double? _sizeOf(WidgetTester tester, String text) {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) return null;
  final widget = tester.widget<Text>(finder.first);
  return (widget.style?.fontSize) ?? DefaultTextStyle.of(finder.evaluate().first).style.fontSize;
}

void main() {
  late FakeFirebaseFirestore firestore;
  late WebsiteContentAdminService service;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<void> size(WidgetTester tester, Size s) async {
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpSite(WidgetTester tester, String route, {Size at = _desktop}) async {
    await size(tester, at);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
      ],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
    if (route != '/') {
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpBlocks(WidgetTester tester, List<WebsiteBlock> blocks, {SiteDesign design = SiteDesign.defaults, Size at = _desktop}) async {
    await size(tester, at);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(design: design, child: WebsiteBlocksView(blocks: blocks, media: const {}, language: PublicLanguage.english, fullBleed: true)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<CustomPage> customPage(String slug, {PageStyle style = const PageStyle(), bool publish = true}) async {
    final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: LocalizedText(en: 'Page $slug'), slug: slug);
    final page = created.copyWith(blocks: () => [_text('About $slug', 'Synthetic body text.')], pageStyle: style);
    publish
        ? await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page)
        : await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: page);
    return page;
  }

  Future<Map<String, dynamic>?> doc(String collection, String id) async => (await firestore.collection(collection).doc(id).get()).data();

  Future<void> publishLayout(SiteLayout layout) => service.publishSiteLayout(requesterRole: 'admin', actor: _admin, layout: layout);

  group('defaults: nothing set keeps everything as it was', () {
    test('no new keys are written, and stored documents read back unchanged', () {
      expect(SiteDesign.defaults.toMap().keys, ['palette', 'bodySize', 'headingSize', 'lineHeight']);
      expect(const SiteHeaderStyle().toMap().keys.where((k) => k.startsWith('utility')), isEmpty);
      expect(const PageStyle().toMap(), isEmpty);
      expect(const CustomPage(id: 'p', slug: 'p').toContentMap().containsKey(PageStyle.field), isFalse);

      // As saved by the previous version: read and written back exactly.
      final oldDesign = {'palette': [for (final c in SiteDesign.defaultPalette) c.toMap()], 'bodySize': 17.0, 'headingSize': 28.0, 'lineHeight': 1.7, 'futureKey': 1};
      expect(SiteDesign.fromMap(oldDesign).toMap(), oldDesign);
      expect(SiteDesign.fromMap(oldDesign).validationErrors(), isEmpty, reason: 'the old list sizes are in range');
      final oldHeader = {'utilityBackground': 'token:gold', 'navAlign': 'center', 'showLogo': true, 'height': 'normal'};
      expect(SiteHeaderStyle.fromMap(oldHeader).toMap(), oldHeader);
      final block = _text('H', 'B', style: {'background': 'sage', 'fontSize': 'large'});
      expect(BlockRegistry.parseList(BlockRegistry.toMapList([block])).single.toMap(), block.toMap());
    });

    testWidgets('the site looks as before: top bar, titles, navigation and body sizes', (tester) async {
      await pumpSite(tester, '/');
      final bar = tester.widget<Container>(key('public-utility-bar'));
      expect(bar.padding, const EdgeInsets.symmetric(vertical: 6));
      final controls = tester.widget<Wrap>(key('public-utility-bar-controls'));
      // Centred on screen, as before (see 'alignment moves the controls').
      expect((controls.alignment, controls.crossAxisAlignment, controls.spacing), (WrapAlignment.center, WrapCrossAlignment.center, 12.0));
      expect(_sizeOf(tester, 'EN'), 13);
      expect(tester.widget<Text>(find.descendant(of: key('public-management-login'), matching: find.byType(Text))).style!.fontSize, 13);
      expect(tester.widget<Text>(key('public-hero-title')).style!.fontSize, 44);
      expect(key('public-page-background'), findsNothing);
    });

    testWidgets('blocks keep the site typography', (tester) async {
      await pumpBlocks(tester, [_text('Heading A', 'Body A'), _hero('Hero A')]);
      expect(_sizeOf(tester, 'Heading A'), 26);
      expect(_sizeOf(tester, 'Body A'), 16);
      expect(_sizeOf(tester, 'Hero A'), 44);
      await pumpBlocks(tester, [_hero('Hero A')], at: _phone);
      expect(_sizeOf(tester, 'Hero A'), 32);
    });
  });

  group('page background', () {
    test('saved with the draft, published with the page, and cleared', () async {
      final page = await customPage('open-day', style: const PageStyle(background: '#FFF4E0'), publish: false);
      expect((await doc(WebsiteCollections.pageDrafts, page.id))![PageStyle.field], {'background': '#FFF4E0'});
      expect(await doc(WebsiteCollections.livePages, page.id), isNull, reason: 'a draft never reaches the website');
      final reopened = (await service.getCustomPage(requesterRole: 'admin', pageId: page.id))!;
      expect(reopened.draft.pageStyle.background, '#FFF4E0');
      expect(reopened.draft.samePublishedContentAs(reopened.live), isFalse);

      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: reopened.draft);
      expect((await doc(WebsiteCollections.livePages, page.id))![PageStyle.field], {'background': '#FFF4E0'});

      // A palette colour, then back to the site's own: removed, not left behind.
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: reopened.draft.copyWith(pageStyle: const PageStyle(background: 'token:sageLight')));
      expect((await doc(WebsiteCollections.pageDrafts, page.id))![PageStyle.field], {'background': 'token:sageLight'});
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: reopened.draft.copyWith(pageStyle: const PageStyle()));
      expect((await doc(WebsiteCollections.pageDrafts, page.id))!.containsKey(PageStyle.field), isFalse);
      expect((await doc(WebsiteCollections.livePages, page.id))![PageStyle.field], {'background': '#FFF4E0'}, reason: 'the live page is unchanged until published');

      await expectLater(
        service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: reopened.draft.copyWith(pageStyle: const PageStyle(background: 'red'))),
        throwsA(isA<WebsiteContentException>()),
      );
    });

    test('a built-in page: draft, publish, unpublish and revert keep it with the blocks', () async {
      final blocks = [_text('Admissions', 'Synthetic text.')];
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: blocks, style: const PageStyle(background: '#EEF5EA'));
      var state = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.admissions);
      expect((state.draftStyle.background, state.liveStyle.isDefault), ('#EEF5EA', true));

      await service.publishBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: blocks, style: state.draftStyle);
      state = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.admissions);
      expect(state.liveStyle.background, '#EEF5EA');
      expect((await WebsiteContentRepository(firestore: firestore).liveContent()).builtInStyles['admissions']?.background, '#EEF5EA');

      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: blocks);
      expect((await doc(WebsiteCollections.pageDrafts, 'admissions'))!.containsKey(PageStyle.field), isFalse, reason: 'cleared in the draft');
      expect((await doc(WebsiteCollections.livePages, 'admissions'))![PageStyle.field], {'background': '#EEF5EA'}, reason: 'live unchanged');

      await service.revertBuiltInPage(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions);
      state = await service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.admissions);
      expect((state.draftStyle.isDefault, state.liveStyle.isDefault), (true, true), reason: 'the built-in page looks as it always has');
    });

    testWidgets('on the website: the page content only, never the header, top bar or footer', (tester) async {
      await customPage('colours', style: const PageStyle(background: '#FFF4E0'));
      await pumpSite(tester, '/pages/colours');
      expect(tester.widget<ColoredBox>(key('public-page-background')).color, const Color(0xFFFFF4E0));
      expect(find.descendant(of: key('public-page-background'), matching: key('public-header')), findsNothing);
      expect(find.descendant(of: key('public-page-background'), matching: key('public-footer')), findsNothing);
      expect(find.descendant(of: key('public-page-background'), matching: find.text('About colours')), findsOneWidget);
      expect((tester.widget<Container>(key('public-header')).decoration as BoxDecoration).color, PublicColors.background);
      expect(tester.widget<Container>(key('public-utility-bar')).color, PublicColors.sageLight);
    });

    testWidgets('the built-in editor: live preview, unsaved until saved, restored on reopening', (tester) async {
      await service.saveBuiltInPageDraft(requesterRole: 'admin', actor: _admin, page: BuiltInPage.admissions, blocks: [_text('Admissions', 'Text.')]);
      await size(tester, _desktop);
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions)),
      ));
      await tester.pumpAndSettle();
      expect(key('website-builtin-unsaved'), findsNothing);
      expect(key('public-page-background'), findsNothing);

      await tester.ensureVisible(key('website-page-background-choose'));
      await tester.tap(key('website-page-background-choose'));
      await tester.pumpAndSettle();
      await tester.enterText(key('website-page-background-hex'), '#E6EDE2');
      await tester.pump();
      await tester.tap(key('website-page-background-hex-apply'));
      await tester.pumpAndSettle();
      expect(tester.widget<ColoredBox>(key('public-page-background')).color, const Color(0xFFE6EDE2), reason: 'shown at once on the canvas');
      expect(key('website-builtin-unsaved'), findsOneWidget);

      await tester.tap(key('website-builtin-save-draft'));
      await tester.pumpAndSettle();
      expect(key('website-builtin-unsaved'), findsNothing);
      expect((await tester.runAsync(() => service.getBuiltInPage(requesterRole: 'admin', page: BuiltInPage.admissions)))!.draftStyle.background, '#E6EDE2');

      // Reopened: the same setting.
      await tester.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [authStateProvider.overrideWith((ref) => Stream<User?>.value(null))],
        child: MaterialApp(home: WebsiteBuiltInPageEditorScreen(service: service, user: _admin, page: BuiltInPage.admissions)),
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<ColoredBox>(key('public-page-background')).color, const Color(0xFFE6EDE2));
    });
  });

  group('top bar', () {
    const custom = SiteHeaderStyle(
      utilityBackground: '#163829',
      utilityTextColor: '#FFFFFF',
      utilityAlign: 'start',
      utilityVerticalAlign: 'bottom',
      utilityFontSize: 16,
      utilityPaddingX: 24,
      utilityPaddingY: 12,
      utilitySpacing: 28,
    );

    test('validated, saved and read back', () {
      expect(SiteHeaderStyle.fromMap(custom.toMap()).toMap(), custom.toMap());
      expect(custom.validationErrors((_) => null), isEmpty);
      expect(const SiteHeaderStyle(utilityFontSize: 30).validationErrors((_) => null).single, contains('Top bar text size'));
      expect(const SiteHeaderStyle(utilitySpacing: 2.5).validationErrors((_) => null).single, contains('whole number'));
      expect(const SiteHeaderStyle(utilityTextColor: 'white').validationErrors((_) => null).single, contains('top bar text colour'));
    });

    testWidgets('colours, alignment, padding, spacing and text size on the website; switching language still works', (tester) async {
      await publishLayout(const SiteLayout(header: custom));
      await pumpSite(tester, '/');
      final bar = tester.widget<Container>(key('public-utility-bar'));
      expect((bar.color, bar.padding), (const Color(0xFF163829), const EdgeInsets.symmetric(vertical: 12)));
      final controls = tester.widget<Wrap>(key('public-utility-bar-controls'));
      expect((controls.alignment, controls.crossAxisAlignment, controls.spacing), (WrapAlignment.start, WrapCrossAlignment.end, 28.0));
      expect(_sizeOf(tester, 'EN'), 16);
      final login = tester.widget<TextButton>(key('public-management-login'));
      expect(login.style!.foregroundColor!.resolve({}), const Color(0xFFFFFFFF));
      expect(tester.widget<Text>(find.descendant(of: key('public-management-login'), matching: find.byType(Text))).style!.fontSize, 16);
      expect(find.ancestor(of: key('public-utility-bar-controls'), matching: find.byWidgetPredicate((w) => w is Padding && w.padding == const EdgeInsets.symmetric(horizontal: 24))), findsOneWidget);

      await tester.tap(key('public-language-tamil'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('public-management-login'), matching: find.text(PublicStrings.of(PublicLanguage.tamil).login)), findsOneWidget);
      await tester.tap(key('public-language-english'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('public-management-login'), matching: find.text(PublicStrings.of(PublicLanguage.english).login)), findsOneWidget);

      await tester.tap(key('public-management-login'));
      await tester.pumpAndSettle();
      expect(find.text('Send OTP'), findsOneWidget, reason: 'login still opens');
    });

    // Where the controls are drawn, not only the Wrap's setting: a Wrap
    // alone is only as wide as its controls, and is centred.
    testWidgets('alignment moves the controls on screen; unset, they stay centred as before', (tester) async {
      Future<(double, double)> span(SiteHeaderStyle header) async {
        await publishLayout(SiteLayout(header: header));
        await pumpSite(tester, '/');
        return (tester.getRect(key('public-language-switch')).left, tester.getRect(key('public-management-login')).right);
      }

      final (defaultLeft, defaultRight) = await span(const SiteHeaderStyle());
      expect((defaultLeft + defaultRight) / 2, closeTo(_desktop.width / 2, 1), reason: 'today’s look: centred');
      expect(const SiteHeaderStyle().toMap().containsKey('utilityAlign'), isFalse);
      expect((await span(const SiteHeaderStyle(utilityAlign: 'center'))).$1, defaultLeft);

      final (startLeft, _) = await span(const SiteHeaderStyle(utilityAlign: 'start'));
      expect(startLeft, lessThan(defaultLeft - 100));
      final (_, endRight) = await span(const SiteHeaderStyle(utilityAlign: 'end'));
      expect(endRight, greaterThan(defaultRight + 100));
      expect(startLeft, greaterThanOrEqualTo(0));
      expect(endRight, lessThanOrEqualTo(_desktop.width));
    });

    group('login and logout stay readable', () {
      /// The colours of the top bar's account controls on [header]'s bar,
      /// signed out (Login) or signed in (Dashboard and Logout).
      Future<List<TextButton>> controls(WidgetTester tester, SiteHeaderStyle? header, {bool signedIn = false}) async {
        if (header != null) await publishLayout(SiteLayout(header: header));
        await size(tester, _desktop);
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            if (signedIn) currentUserProvider.overrideWith((ref) => _admin),
            websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
          ],
          child: const MontessoriApp(),
        ));
        await tester.pumpAndSettle();
        return [
          for (final k in signedIn ? ['public-dashboard', 'public-logout'] : ['public-management-login']) tester.widget<TextButton>(key(k)),
        ];
      }

      Color bar(WidgetTester tester) => tester.widget<Container>(key('public-utility-bar')).color!;
      Color fg(TextButton b, [Set<WidgetState> states = const {}]) => b.style!.foregroundColor!.resolve(states)!;

      testWidgets('no top bar styling: the site’s own green, as before', (tester) async {
        final login = (await controls(tester, null)).single;
        expect((bar(tester), fg(login)), (PublicColors.sageLight, PublicColors.forest));
      });

      testWidgets('a dark bar without a text colour: white, readable, in every state; login still opens', (tester) async {
        for (final signedIn in [false, true]) {
          for (final b in await controls(tester, const SiteHeaderStyle(utilityBackground: '#163829'), signedIn: signedIn)) {
            for (final states in [<WidgetState>{}, {WidgetState.hovered}, {WidgetState.pressed}, {WidgetState.focused}]) {
              expect(fg(b, states), Colors.white, reason: '$states');
              expect(contrastRatio(fg(b, states), bar(tester)), greaterThanOrEqualTo(4.5));
            }
            // The hover and press highlight is a tint of the text colour.
            final overlay = b.style!.overlayColor!.resolve({WidgetState.hovered})!;
            expect((overlay.r, overlay.g, overlay.b), (1.0, 1.0, 1.0));
          }
        }
        await controls(tester, null);
        await tester.tap(key('public-management-login'));
        await tester.pumpAndSettle();
        expect(find.text('Send OTP'), findsOneWidget);
      });

      testWidgets('a light bar without a text colour: the site’s own green', (tester) async {
        final login = (await controls(tester, const SiteHeaderStyle(utilityBackground: '#FFF4E0'))).single;
        expect(fg(login), PublicColors.forest);
        expect(contrastRatio(fg(login), bar(tester)), greaterThanOrEqualTo(4.5));
        expect(fg((await controls(tester, const SiteHeaderStyle(utilityBackground: 'token:white'))).single), PublicColors.forest);
      });

      testWidgets('a chosen text colour is kept, whatever the bar', (tester) async {
        final logout = (await controls(tester, const SiteHeaderStyle(utilityBackground: '#163829', utilityTextColor: 'token:gold'), signedIn: true)).last;
        expect(fg(logout), SiteDesign.defaults.colorOf('gold'));
        final login = (await controls(tester, const SiteHeaderStyle(utilityBackground: '#FFF4E0', utilityTextColor: '#163829'))).single;
        expect(fg(login), const Color(0xFF163829));
      });

      test('the choice: the preferred colour when readable, else the one that contrasts more', () {
        expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
        expect(readableTextOn(PublicColors.sageLight, preferred: PublicColors.forest, alternative: Colors.white), PublicColors.forest);
        expect(readableTextOn(PublicColors.forestDark, preferred: PublicColors.forest, alternative: Colors.white), Colors.white);
        // A mid-tone where neither reaches 4.5:1: the better of the two.
        const mid = Color(0xFF5E8A6E);
        final pick = readableTextOn(mid, preferred: PublicColors.forest, alternative: Colors.white);
        expect(contrastRatio(pick, mid), greaterThanOrEqualTo(contrastRatio(pick == Colors.white ? PublicColors.forest : Colors.white, mid)));
      });
    });

    testWidgets('phones: wraps, keeps its room, no overflow; login moves to the menu', (tester) async {
      await publishLayout(const SiteLayout(header: SiteHeaderStyle(utilityFontSize: 18, utilityPaddingX: 48, utilitySpacing: 40, utilityAlign: 'center')));
      for (final width in [360.0, 320.0]) {
        await pumpSite(tester, '/', at: Size(width, 1600));
        expect(tester.takeException(), isNull, reason: 'no overflow at $width');
        expect(key('public-management-login'), findsNothing);
        expect(find.ancestor(of: key('public-utility-bar-controls'), matching: find.byWidgetPredicate((w) => w is Padding && w.padding == const EdgeInsets.symmetric(horizontal: 16))), findsOneWidget);
        expect(tester.getRect(key('public-language-switch')).right, lessThanOrEqualTo(width));
      }
    });

    testWidgets('the header editor sets each option', (tester) async {
      SiteHeaderStyle style = const SiteHeaderStyle();
      await size(tester, _desktop);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteHeaderStyleEditor(style: style, design: SiteDesign.defaults, onChanged: (v) => setState(() => style = v)),
            ),
          ),
        ),
      ));
      await tester.tap(key('website-header-utility-align'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('website-header-utility-align-center')).last);
      await tester.pumpAndSettle();
      await tester.enterText(key('website-header-utility-font-size'), '15');
      await tester.pump();
      await tester.enterText(key('website-header-utility-spacing'), '20');
      await tester.pump();
      expect((style.utilityAlign, style.utilityFontSize, style.utilitySpacing), ('center', 15.0, 20.0));
      expect(tester.widget<Text>(key('website-header-utility-font-size-status')).data, 'Custom: 15 px');
      await tester.tap(key('website-header-utility-font-size-reset'));
      await tester.pump();
      expect(style.utilityFontSize, isNull);
      expect(tester.widget<Text>(key('website-header-utility-font-size-status')).data, 'Inherits the site’s own: 13 px');
      await tester.enterText(key('website-header-utility-padding-y'), '99');
      await tester.pump();
      expect(style.utilityPaddingY, isNull, reason: 'out of range: explained, not applied');
      expect(tester.widget<Text>(key('website-header-utility-padding-y-status')).data, 'Enter 0 to 24.');
    });
  });

  group('site typography', () {
    const design = SiteDesign(titleSize: 56, titleSizeMobile: 36, headingSize: 30, bodySize: 18, navSize: 18, buttonSize: 18);

    test('ranges, whole pixels, and reading back', () {
      expect(design.validationErrors(), isEmpty);
      expect(SiteDesign.fromMap(design.toMap()).toMap(), design.toMap());
      expect(const SiteDesign(bodySize: 30).validationErrors().single, contains('Body text size'));
      expect(const SiteDesign(titleSize: 100).validationErrors().single, contains('Page title size'));
      expect(const SiteDesign(navSize: 15.5).validationErrors().single, contains('whole number'));
      expect(const SiteDesign(headingSize: 10).validationErrors().single, contains('18 to 48'));
    });

    testWidgets('blocks, titles and buttons follow it, on desktop and phones', (tester) async {
      final buttons = BlockRegistry.create(BlockRegistry.buttons)
          .withValue('buttons', [const BlockItem(id: 'i_button01', values: {'label': LocalizedText(en: 'Enquire now'), 'target': '/admissions', 'variant': 'primary'})]);
      await pumpBlocks(tester, [_text('Heading B', 'Body B'), _hero('Hero B'), buttons], design: design);
      expect((_sizeOf(tester, 'Heading B'), _sizeOf(tester, 'Body B'), _sizeOf(tester, 'Hero B')), (30, 18, 56));
      expect(_sizeOf(tester, 'Enquire now'), 18);
      await pumpBlocks(tester, [_hero('Hero B')], design: design, at: _phone);
      expect(_sizeOf(tester, 'Hero B'), 36);
    });

    testWidgets('published: page titles and the header navigation follow it', (tester) async {
      final initial = await service.initialSiteLayout(requesterRole: 'admin');
      // Three links fit in the header row at 16 px (six only just fit at
      // the site's own 15 px: the row is at most 1160 px wide).
      await publishLayout(initial.copyWith(design: design.copyWith(navSize: () => 16), mainNav: initial.mainNav.take(3).toList()));
      await customPage('typed');
      await pumpSite(tester, '/pages/typed');
      expect(tester.widget<Text>(key('public-page-title')).style!.fontSize, 56);
      final first = PublicStrings.of(PublicLanguage.english).home;
      final nav = find.descendant(of: key('public-header'), matching: find.text(first));
      expect(tester.widget<Text>(nav.first).style!.fontSize, 16);
      await pumpSite(tester, '/pages/typed', at: _phone);
      expect(tester.widget<Text>(key('public-page-title')).style!.fontSize, 36);
      expect(tester.takeException(), isNull);

      // Links too wide for the row at their size: the header uses its menu
      // (as for long labels), never overflowing; the menu's links follow.
      await publishLayout(initial.copyWith(design: design.copyWith(navSize: () => 22)));
      await pumpSite(tester, '/pages/typed');
      expect(tester.takeException(), isNull);
      final gallery = PublicStrings.of(PublicLanguage.english).gallery;
      expect(find.descendant(of: key('public-header'), matching: find.text(gallery)), findsNothing);
      await tester.tap(key('public-menu-button'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.descendant(of: key('public-menu'), matching: find.text(gallery)).first).style!.fontSize, 24);
    });

    testWidgets('the design editor: number and slider, custom or inherited, reset', (tester) async {
      SiteDesign current = SiteDesign.defaults;
      await size(tester, _desktop);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(child: WebsiteDesignEditor(design: current, onChanged: (v) => setState(() => current = v))),
          ),
        ),
      ));
      expect(tester.widget<Text>(key('website-design-heading-size-status')).data, 'Inherits the site’s own size: 26 px');
      await tester.enterText(key('website-design-heading-size'), '32');
      await tester.pump();
      expect(current.headingSize, 32);
      expect(tester.widget<Text>(key('website-design-heading-size-status')).data, 'Custom: 32 px');
      await tester.tap(key('website-design-heading-size-reset'));
      await tester.pump();
      expect(current.headingSize, 26);

      // The slider sets whole pixels within the range.
      await tester.ensureVisible(key('website-design-title-size-slider'));
      await tester.drag(key('website-design-title-size-slider'), const Offset(400, 0));
      await tester.pump();
      expect(current.titleSize, isNotNull);
      expect(SiteDesign.titleRange.allows(current.titleSize), isTrue);
      await tester.tap(key('website-design-title-size-reset'));
      await tester.pump();
      expect(current.titleSize, isNull);
    });
  });

  group('a block’s own font sizes', () {
    test('only where they apply, validated, and kept with the block', () {
      for (final type in ['text', 'hero', 'cards', 'features', 'page_header', 'notice', 'events_feed', 'announcements_feed', 'cta']) {
        expect(BlockRegistry.definition(type)!.styleKeys, containsAll(['headingFontSize', 'bodyFontSize']), reason: type);
      }
      expect(BlockRegistry.definition('gallery')!.styleKeys, contains('headingFontSize'));
      for (final type in ['section', 'columns', 'image', 'divider', 'buttons', 'form', 'gallery_feed']) {
        expect(BlockRegistry.definition(type)!.styleKeys, isNot(contains('headingFontSize')), reason: type);
      }
      expect(BlockRegistry.blockProblems(_text('H', 'B', style: {'headingFontSize': 90})).join(), contains('14 to 72 px'));
      expect(BlockRegistry.blockProblems(_text('H', 'B', style: {'bodyFontSize': 'big'})).join(), contains('12 to 24 px'));
      final block = _text('H', 'B', style: {'headingFontSize': 40, 'bodyFontSize': 20});
      final again = BlockRegistry.parseList(BlockRegistry.toMapList([block])).single as StructuredBlock;
      expect(again.id, block.id);
      expect(again.style, equals(block.style));
    });

    testWidgets('the override wins over the site and the size option; only that block; clearing inherits again', (tester) async {
      final own = _text('Own heading', 'Own body', style: {'headingFontSize': 40, 'bodyFontSize': 20, 'fontSize': 'large'});
      final other = _text('Other heading', 'Other body');
      const design = SiteDesign(headingSize: 30, bodySize: 18);
      await pumpBlocks(tester, [own, other, _hero('Own hero', style: {'headingFontSize': 60})], design: design);
      expect((_sizeOf(tester, 'Own heading'), _sizeOf(tester, 'Own body')), (40, 20));
      expect((_sizeOf(tester, 'Other heading'), _sizeOf(tester, 'Other body')), (30, 18));
      expect(_sizeOf(tester, 'Own hero'), 60);
      await pumpBlocks(tester, [_hero('Own hero', style: {'headingFontSize': 60})], design: design, at: _phone);
      expect(_sizeOf(tester, 'Own hero'), (60 * 32 / 44).roundToDouble(), reason: 'scaled on phones as titles are');
      expect(tester.takeException(), isNull);

      final cleared = own.copyWith(style: Map.of(own.style)..remove('headingFontSize')..remove('bodyFontSize'));
      await pumpBlocks(tester, [cleared], design: design);
      expect((_sizeOf(tester, 'Own heading'), _sizeOf(tester, 'Own body')), (30 * 1.125, 18 * 1.125), reason: 'back to the site typography, with its size option');
    });

    testWidgets('the properties panel: inherited or custom, set, reset; the block keeps its id', (tester) async {
      var block = _text('Panel heading', 'Panel body');
      final id = block.id;
      await size(tester, _desktop);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: WebsiteStyleEditor(block: block, design: const SiteDesign(headingSize: 28), onChanged: (b) => setState(() => block = b as StructuredBlock)),
            ),
          ),
        ),
      ));
      final prefix = 'website-block-$id-style-headingFontSize';
      expect(tester.widget<Text>(key('$prefix-status')).data, 'Inherits the site typography: 28 px');
      await tester.enterText(key(prefix), '36');
      await tester.pump();
      expect((block.id, block.style['headingFontSize']), (id, 36));
      expect(tester.widget<Text>(key('$prefix-status')).data, 'Custom: 36 px');
      await tester.tap(key('$prefix-reset'));
      await tester.pump();
      expect(block.style.containsKey('headingFontSize'), isFalse);
      expect(block.id, id);
    });

    // Found in browser UAT: deleting digits of 236 applies 23 on the way,
    // and the box then showed an unapplied 366 beside a 23 px heading.
    testWidgets('the number box: leaving it with a number not applied shows the size in use; the slider shows its whole range', (tester) async {
      var block = _text('Box heading', 'Box body');
      await size(tester, _desktop);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: Column(children: [
                WebsiteStyleEditor(block: block, design: const SiteDesign(headingSize: 28), onChanged: (b) => setState(() => block = b as StructuredBlock)),
                const TextField(key: Key('elsewhere')),
              ]),
            ),
          ),
        ),
      ));
      final prefix = 'website-block-${block.id}-style-headingFontSize';
      final box = find.descendant(of: key(prefix), matching: find.byType(EditableText));
      await tester.enterText(key(prefix), '23');
      await tester.pump();
      await tester.enterText(key(prefix), '366');
      await tester.pump();
      expect(block.style['headingFontSize'], 23, reason: 'not applied');
      expect(tester.widget<Text>(key('$prefix-status')).data, 'Enter 14 to 72.');

      await tester.tap(key('elsewhere'));
      await tester.pump();
      expect(tester.widget<EditableText>(box).controller.text, '23');
      expect(tester.widget<Text>(key('$prefix-status')).data, 'Custom: 23 px');

      // Unset, after a reset: the inherited size again.
      await tester.tap(key('$prefix-reset'));
      await tester.pump();
      await tester.enterText(key(prefix), '9');
      await tester.pump();
      await tester.tap(key('elsewhere'));
      await tester.pump();
      expect((tester.widget<EditableText>(box).controller.text, block.style.containsKey('headingFontSize')), ('28', false));
      expect(tester.widget<Text>(key('$prefix-status')).data, 'Inherits the site typography: 28 px');

      // The theme's inactive track is the white card colour.
      final slider = tester.widget<Slider>(key('$prefix-slider'));
      expect(slider.inactiveColor, isNotNull);
      expect(slider.inactiveColor, isNot(Theme.of(tester.element(key('$prefix-slider'))).colorScheme.surface));
    });
  });

  group('the canvas and the website match', () {
    testWidgets('the same sizes and background in the editor canvas and on the published page', (tester) async {
      const style = {'headingFontSize': 34, 'bodyFontSize': 19};
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Match'), slug: 'match');
      final page = created.copyWith(blocks: () => [_text('Match heading', 'Match body', style: style)], pageStyle: const PageStyle(background: 'token:goldLight'));
      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: page);
      await pumpSite(tester, '/pages/match');
      final published = (_sizeOf(tester, 'Match heading'), _sizeOf(tester, 'Match body'), tester.widget<ColoredBox>(key('public-page-background')).color);
      expect(published, (34, 19, SiteDesign.defaults.colorOf('goldLight')));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: PageBackground(style: page.pageStyle, child: WebsiteBlocksView(blocks: page.blocks!, media: const {}, language: PublicLanguage.english, interactive: false, fullBleed: true)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect((_sizeOf(tester, 'Match heading'), _sizeOf(tester, 'Match body'), tester.widget<ColoredBox>(key('public-page-background')).color), published);
    });
  });
}
