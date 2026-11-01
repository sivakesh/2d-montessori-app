// Third-party embeds: YouTube, Vimeo, Google Forms and Google Calendar.
// A pasted link or <iframe> code is read for its ids only and the frame's
// address is rebuilt; nothing pasted is run; exact hosts and paths; each
// provider's own sandbox and features; a required title; click to load;
// never a frame in the editor. Parser, security, sizing, accessibility,
// editor, saving and publishing. Synthetic test data only.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/embed_providers.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_embed_frame.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _yt = 'dQw4w9WgXcQ';
const _form = '1FAIpQLSf_synthetic_form_id_000000000000';
const _calendar = 'synthetic.school%40group.calendar.google.com';

StructuredBlock _embed(String source, {String id = 'b_embed00001', Map<String, Object?> extra = const {}}) => BlockRegistry.parse({
      'id': id,
      'type': 'embed',
      'v': 1,
      'source': {'en': source},
      'title': {'en': 'A morning in the classroom', 'ta': 'வகுப்பறையில் ஒரு காலை'},
      ...extra,
    }) as StructuredBlock;

String _url(String source) => EmbedSource.parse(source).embedUrl.toString();

void main() {
  group('parser: accepted links, rebuilt addresses', () {
    test('YouTube: watch, short, embed, shorts, mobile and no-scheme links; start time; nothing else kept', () {
      const canonical = 'https://www.youtube-nocookie.com/embed/$_yt?rel=0';
      for (final link in [
        'https://www.youtube.com/watch?v=$_yt',
        'https://youtube.com/watch?v=$_yt&feature=share&autoplay=1&onload=alert(1)',
        'https://m.youtube.com/watch?v=$_yt',
        'https://youtu.be/$_yt',
        'youtu.be/$_yt',
        'https://www.youtube.com/embed/$_yt',
        'https://www.youtube-nocookie.com/embed/$_yt?autoplay=1&controls=0',
        'https://www.youtube.com/shorts/$_yt',
      ]) {
        expect(_url(link), canonical, reason: link);
      }
      expect(_url('https://youtu.be/$_yt?t=1m30s'), '$canonical&start=90');
      expect(_url('https://www.youtube.com/watch?v=$_yt&t=45'), '$canonical&start=45');
      expect(EmbedSource.parse('https://youtu.be/$_yt').openUrl.toString(), 'https://www.youtube.com/watch?v=$_yt');
    });

    test('Vimeo: public and unlisted links, player links', () {
      expect(_url('https://vimeo.com/123456789'), 'https://player.vimeo.com/video/123456789?dnt=1');
      expect(_url('https://vimeo.com/123456789/abcdef1234'), 'https://player.vimeo.com/video/123456789?dnt=1&h=abcdef1234');
      expect(_url('https://player.vimeo.com/video/123456789?h=abcdef1234&autoplay=1'), 'https://player.vimeo.com/video/123456789?dnt=1&h=abcdef1234');
    });

    test('Google Forms: the form link; editing and short links explained', () {
      expect(_url('https://docs.google.com/forms/d/e/$_form/viewform?usp=sf_link'), 'https://docs.google.com/forms/d/e/$_form/viewform?embedded=true');
      expect(EmbedSource.parse('https://docs.google.com/forms/d/1AbCdEfGhIjKlMnOpQrStUvWxYz/edit').error, contains('editing link'));
      expect(EmbedSource.parse('https://forms.gle/AbCdEf123').error, contains('Short form links'));
    });

    test('Google Calendar: embed links; only calendars, time zone and view are kept', () {
      expect(_url('https://calendar.google.com/calendar/embed?src=$_calendar&ctz=Asia%2FKolkata&mode=WEEK&bgcolor=%23ffffff&onload=x'),
          'https://calendar.google.com/calendar/embed?src=synthetic.school%40group.calendar.google.com&ctz=Asia%2FKolkata&mode=WEEK');
      expect(_url('https://calendar.google.com/calendar/u/0/embed?src=$_calendar'), 'https://calendar.google.com/calendar/embed?src=synthetic.school%40group.calendar.google.com');
      expect(EmbedSource.parse('https://calendar.google.com/calendar/embed?src=not-a-calendar').error, contains('no valid calendar'));
    });

    test('<iframe> code: only its address is read; scripts and attributes are reported, never used', () {
      const snippet = '<iframe width="560" height="315" src="https://www.youtube.com/embed/$_yt?autoplay=1" title="x" frameborder="0" '
          'allow="autoplay; camera; microphone" onload="alert(1)" allowfullscreen></iframe><script src="https://evil.example/x.js"></script><iframe src="https://evil.example"></iframe>';
      final parsed = EmbedSource.parse(snippet);
      expect(parsed.embedUrl.toString(), 'https://www.youtube-nocookie.com/embed/$_yt?rel=0');
      expect(parsed.ignored, containsAll(['allow', 'on… (event handlers)', 'allowfullscreen', '<script>', 'more <iframe> elements (one embed per block)']));
    });
  });

  group('parser: rejected', () {
    test('lookalike hosts, ports, credentials, other schemes, homographs and path tricks', () {
      for (final bad in [
        'https://youtube.com.evil.example/watch?v=$_yt',
        'https://evil-youtube.com/watch?v=$_yt',
        'https://www.youtube.com@evil.example/watch?v=$_yt',
        'https://user:pass@www.youtube.com/watch?v=$_yt',
        'https://www.youtube.com:8443/watch?v=$_yt',
        'https://youtube.com./watch?v=$_yt',
        'https://yоutube.com/watch?v=$_yt', // Cyrillic "о"
        'http://www.youtube.com/watch?v=$_yt',
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        '//www.youtube.com/embed/$_yt',
        'https://www.youtube.com/embed/../../evil',
        'https://www.youtube.com/embed/$_yt/extra',
        'https://www.youtube.com/embed/${_yt}x',
        'https://www.youtube.com/playlist?list=PL123',
        'https://www.youtube.com/@school',
        'https://vimeo.com/channels/staffpicks',
        'https://player.vimeo.com/video/123?h=<script>',
        'https://docs.google.com/document/d/abc/edit',
        'https://calendar.google.com/calendar/u/0?cid=abc',
        'https://www.google.com/maps/embed?pb=abc',
        'not a link',
      ]) {
        expect(EmbedSource.parse(bad).isValid, isFalse, reason: bad);
      }
    });

    test('script embeds, badges, srcdoc and javascript frames are explained', () {
      expect(EmbedSource.parse('<blockquote class="twitter-tweet"><a href="https://x.com/s/1">x</a></blockquote><script src="https://platform.twitter.com/widgets.js"></script>').error,
          contains('needs a script'));
      expect(EmbedSource.parse('<a href="https://www.iao.org/x"><img src="https://www.iao.org/seal.png" alt="IAO"></a>').error, contains('No link or <iframe> found'));
      expect(EmbedSource.parse('<iframe srcdoc="<script>alert(1)</script>"></iframe>').error, contains('no address'));
      expect(EmbedSource.parse('<iframe src="javascript:alert(1)"></iframe>').isValid, isFalse);
    });

    test('every provider: never top navigation, downloads or modals; never camera, microphone, location, payment or autoplay', () {
      for (final p in EmbedProvider.all) {
        expect(p.sandbox.where((t) => t.startsWith('allow-top-navigation') || t == 'allow-downloads' || t == 'allow-modals' || t == 'allow-pointer-lock'), isEmpty, reason: p.id);
        expect(p.allow.where((f) => ['camera', 'microphone', 'geolocation', 'payment', 'autoplay', 'usb', 'display-capture'].contains(f)), isEmpty, reason: p.id);
      }
      expect(EmbedProvider.googleForms.sandbox, contains('allow-forms'));
      expect(EmbedProvider.youtube.sandbox, isNot(contains('allow-forms')));
    });
  });

  group('the block', () {
    test('valid with a link and a title; problems otherwise; saved exactly', () {
      final ok = _embed('https://youtu.be/$_yt');
      expect(BlockRegistry.blockProblems(ok), isEmpty);
      expect(ok.toMap()['source'], {'en': 'https://youtu.be/$_yt', 'ta': ''});
      expect(BlockRegistry.blockProblems(_embed('https://evil.example/x')).single, contains('isn’t a supported provider'));
      final untitled = BlockRegistry.parse({'id': 'b_embed00001', 'type': 'embed', 'v': 1, 'source': {'en': 'https://youtu.be/$_yt'}}) as StructuredBlock;
      expect(BlockRegistry.blockProblems(untitled).single, contains('title for screen readers'));
      expect(BlockRegistry.blockProblems(BlockRegistry.create(BlockRegistry.embed)), hasLength(2), reason: 'a new block needs a link and a title');
      expect(BlockRegistry.create(BlockRegistry.embed).toggle('loadOnClick'), isTrue, reason: 'click to load by default');
    });
  });

  group('drawn', () {
    Future<void> size(WidgetTester tester, Size s) async {
      tester.view.physicalSize = s;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> pump(WidgetTester tester, List<WebsiteBlock> blocks, {Size at = const Size(1400, 2400), bool interactive = true, PublicLanguage language = PublicLanguage.english}) async {
      await size(tester, at);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WebsiteDesignScope(design: SiteDesign.defaults, child: WebsiteBlocksView(blocks: blocks, media: const {}, language: language, interactive: interactive, fullBleed: true)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Finder key(String k) => find.byKey(Key(k));

    testWidgets('click to load: nothing from the provider until the visitor asks; then the rebuilt address, sandbox and title', (tester) async {
      await pump(tester, [_embed('https://www.youtube.com/watch?v=$_yt&autoplay=1')]);
      expect(find.byType(PublicEmbedFrame), findsNothing);
      expect(find.text('Loads content from www.youtube-nocookie.com.'), findsOneWidget);
      await tester.tap(key('public-embed-b_embed00001-load'));
      await tester.pumpAndSettle();
      final frame = tester.widget<PublicEmbedFrame>(find.byType(PublicEmbedFrame));
      expect(frame.src.toString(), 'https://www.youtube-nocookie.com/embed/$_yt?rel=0');
      expect(frame.title, 'A morning in the classroom');
      expect(frame.sandbox, EmbedProvider.youtube.sandbox);
      expect(frame.allow, ['encrypted-media', 'picture-in-picture']);
      expect(frame.allowFullscreen, isFalse, reason: 'off unless the block allows it');
    });

    testWidgets('loading straight away, full screen when allowed; never for forms', (tester) async {
      await pump(tester, [_embed('https://vimeo.com/123456789', extra: {'loadOnClick': false, 'allowFullscreen': true})]);
      expect(tester.widget<PublicEmbedFrame>(find.byType(PublicEmbedFrame)).allowFullscreen, isTrue);
      await pump(tester, [_embed('https://docs.google.com/forms/d/e/$_form/viewform', extra: {'loadOnClick': false, 'allowFullscreen': true})]);
      final form = tester.widget<PublicEmbedFrame>(find.byType(PublicEmbedFrame));
      expect((form.allowFullscreen, form.sandbox.contains('allow-forms')), (false, true));
    });

    testWidgets('in the editor: never a frame, and nothing to press', (tester) async {
      await pump(tester, [_embed('https://youtu.be/$_yt', extra: {'loadOnClick': false})], interactive: false);
      expect(find.byType(PublicEmbedFrame), findsNothing);
      expect(key('public-embed-b_embed00001-placeholder'), findsOneWidget);
      expect(tester.widget<FilledButton>(key('public-embed-b_embed00001-load')).onPressed, isNull);
      expect(tester.widget<TextButton>(key('public-embed-b_embed00001-open')).onPressed, isNull);
    });

    testWidgets('accessible: the load button names the provider and title; the frame carries the title', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, [_embed('https://youtu.be/$_yt')]);
      expect(find.bySemanticsLabel('Load YouTube: A morning in the classroom'), findsOneWidget);
      await tester.tap(key('public-embed-b_embed00001-load'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^A morning in the classroom')), findsWidgets);
      handle.dispose();
    });

    testWidgets('sizes: videos 16:9, forms and calendars their height, fixed heights; within the screen at every width', (tester) async {
      final blocks = [
        _embed('https://youtu.be/$_yt'),
        _embed('https://docs.google.com/forms/d/e/$_form/viewform', id: 'b_embed00002'),
        _embed('https://calendar.google.com/calendar/embed?src=$_calendar', id: 'b_embed00003', extra: {'height': '480'}),
        _embed('https://vimeo.com/123456789', id: 'b_embed00004', extra: {'shape': 'fixed', 'height': '320'}),
      ];
      for (final at in const [Size(1400, 4000), Size(820, 4000), Size(390, 4000), Size(320, 4000)]) {
        await pump(tester, blocks, at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        final video = tester.getRect(key('public-embed-b_embed00001-frame-area'));
        expect(video.width / video.height, closeTo(16 / 9, 0.01));
        expect(tester.getRect(key('public-embed-b_embed00002-frame-area')).height, closeTo(800, 0.01));
        expect(tester.getRect(key('public-embed-b_embed00003-frame-area')).height, closeTo(480, 0.01));
        expect(tester.getRect(key('public-embed-b_embed00004-frame-area')).height, closeTo(320, 0.01));
        for (var i = 1; i <= 4; i++) {
          expect(tester.getRect(key('public-embed-b_embed0000$i-frame-area')).right, lessThanOrEqualTo(at.width));
        }
      }
    });

    testWidgets('Tamil: the title, and the button and notice in Tamil', (tester) async {
      await pump(tester, [_embed('https://youtu.be/$_yt')], language: PublicLanguage.tamil);
      expect(find.text('வகுப்பறையில் ஒரு காலை'), findsOneWidget);
      expect(find.text('YouTube ஐ ஏற்று'), findsOneWidget);
    });

    testWidgets('an unsupported source is not shown to visitors', (tester) async {
      await pump(tester, [_embed('<script src="https://evil.example/x.js"></script>')]);
      expect(key('public-embed-b_embed00001'), findsNothing);
    });
  });

  group('editor and publishing', () {
    late FakeFirebaseFirestore firestore;
    late WebsiteContentAdminService service;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      service = WebsiteContentAdminService(firestore: firestore, storage: MockFirebaseStorage());
    });

    Finder key(String k) => find.byKey(Key(k));
    Finder field(String prefix) => find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true);

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

    Future<void> type(WidgetTester tester, String prefix, String text) async {
      await tester.ensureVisible(field(prefix));
      await tester.pumpAndSettle();
      await tester.enterText(field(prefix), text);
      await tester.pumpAndSettle();
    }

    testWidgets('add from the menu; recognised address or the reason; a placeholder on the canvas; saved and reopened', (tester) async {
      final created = (await tester.runAsync(() => service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Scratch'), slug: 'scratch')))!;
      await tester.runAsync(() => firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'sections': [], 'schemaVersion': 2, 'blocks': []}));
      await open(tester, created.id);
      await tap(tester, key('website-blocks-add'));
      expect(find.descendant(of: key('website-blocks-add-embed'), matching: find.text('Video, form or calendar embed')), findsOneWidget);
      await tester.tap(key('website-blocks-add-embed'));
      await tester.pumpAndSettle();
      final id = tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.single.id;
      expect(key('website-block-$id-embed-info'), findsOneWidget);

      await type(tester, 'website-block-$id-source-en', '<blockquote>x</blockquote><script src="https://platform.twitter.com/widgets.js"></script>');
      expect(find.descendant(of: key('website-block-$id-embed-problem'), matching: find.textContaining('needs a script')), findsOneWidget);

      await type(tester, 'website-block-$id-source-en', '<iframe src="https://www.youtube.com/embed/$_yt" onload="x()"></iframe>');
      await type(tester, 'website-block-$id-title-en', 'Our garden');
      expect(find.descendant(of: key('website-block-$id-embed-recognised'), matching: find.textContaining('youtube-nocookie.com/embed/$_yt')), findsOneWidget);
      expect(find.descendant(of: key('website-block-$id-embed-recognised'), matching: find.textContaining('event handlers')), findsOneWidget);
      expect(find.byType(PublicEmbedFrame), findsNothing, reason: 'the canvas never loads the provider');

      await tap(tester, key('website-custom-save-draft'));
      await open(tester, created.id);
      final block = tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks.single as StructuredBlock;
      expect(block.text('source').en, '<iframe src="https://www.youtube.com/embed/$_yt" onload="x()"></iframe>', reason: 'kept as pasted, for editing');
      expect(BlockRegistry.blockProblems(block), isEmpty);
    });

    testWidgets('a draft never reaches visitors; published it shows (click to load); unpublished it is gone', (tester) async {
      final created = (await tester.runAsync(() => service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Videos'), slug: 'videos')))!;
      final blocks = [_embed('https://youtu.be/$_yt'), _embed('https://vimeo.com/123456789', id: 'b_embed00002')];
      await tester.runAsync(() => service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => blocks)));

      Future<void> visit() async {
        tester.view.physicalSize = const Size(1400, 2600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
            websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
          ],
          child: const MontessoriApp(),
        ));
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/pages/videos');
        await tester.pumpAndSettle();
      }

      await visit();
      expect(key('public-embed-b_embed00001'), findsNothing);

      final draft = (await tester.runAsync(() => service.getCustomPage(requesterRole: 'admin', pageId: created.id)))!.draft;
      await tester.runAsync(() => service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: draft.copyWith(blocks: () => draft.blocks!.reversed.toList())));
      await visit();
      expect(key('public-embed-b_embed00001-placeholder'), findsOneWidget);
      expect(tester.getTopLeft(key('public-embed-b_embed00002')).dy, lessThan(tester.getTopLeft(key('public-embed-b_embed00001')).dy), reason: 'published in the new order');
      expect(find.byType(PublicEmbedFrame), findsNothing);

      await tester.runAsync(() => service.unpublishCustomPage(requesterRole: 'admin', actor: _admin, pageId: created.id));
      await visit();
      expect(key('public-embed-b_embed00001'), findsNothing);
      final state = (await tester.runAsync(() => service.getCustomPage(requesterRole: 'admin', pageId: created.id)))!;
      expect(state.draft.blocks, hasLength(2), reason: 'unpublishing keeps the draft');
    });
  });
}
