// Two block types: Accreditations & Recognition (the school's bodies,
// credentials, logos, certificates and dates, as entered: nothing
// inferred) and Custom HTML (a safe subset of HTML drawn as text and
// https images; scripts, event handlers, unsafe links and image addresses,
// and embeds never reach the page). Model,
// security, rendering at phone, tablet and desktop widths, the editor,
// and saving, publishing and drafts. Synthetic test data only.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/admin/website/data/website_content_admin_service.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_block_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/page_builder/website_visual_editor.dart';
import 'package:montessori_app/modules/admin/website/ui/website_custom_page_editor.dart';
import 'package:montessori_app/modules/auth/models/app_user.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/blocks/accreditation_date.dart';
import 'package:montessori_app/modules/public_website/content/blocks/block_registry.dart';
import 'package:montessori_app/modules/public_website/content/blocks/custom_html.dart';
import 'package:montessori_app/modules/public_website/content/blocks/website_block.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/content/website_design.dart';
import 'package:montessori_app/modules/public_website/public_strings.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/public_custom_html.dart';
import 'package:montessori_app/modules/public_website/widgets/blocks/website_blocks_view.dart';
import 'package:montessori_app/modules/public_website/widgets/public_website_image.dart';

final _admin = AppUser(id: '9000000002', phone: '9000000002', role: 'admin', isActive: true, name: 'Test admin');
const _desktop = Size(1400, 3000);
const _tablet = Size(820, 3000);
const _phone = Size(390, 3000);
const _narrow = Size(320, 3000);

WebsiteMedia _media(String id, {String alt = ''}) => WebsiteMedia(
      id: id,
      url: 'https://example.test/$id.jpg',
      storagePath: 'website_media/$id/d.jpg',
      alt: LocalizedText(en: alt),
      status: WebsiteMediaStatus.published,
      consentConfirmed: true,
    );

final _published = {for (final m in [_media('m_logo1'), _media('m_cert1', alt: 'Certificate on the school wall'), _media('m_logo2')]) m.id: m};

StructuredBlock _parse(Map<String, dynamic> raw) => BlockRegistry.parse(raw) as StructuredBlock;
Object? _plain(Object? v) => jsonDecode(jsonEncode(v));

Map<String, dynamic> _item(String id, {String name = 'Synthetic Montessori Council', Map<String, Object?> extra = const {}}) => {
      'id': id,
      'name': {'en': name, 'ta': ''},
      ...extra,
    };

Map<String, dynamic> _accreditations({List<Map<String, dynamic>>? items, Map<String, Object?> extra = const {}}) => {
      'id': 'b_accred0001',
      'type': 'accreditations',
      'v': 1,
      'heading': {'en': 'Accreditations', 'ta': 'அங்கீகாரங்கள்'},
      'items': items ??
          [
            _item('i_accred0001', extra: {
              'title': {'en': 'Member school', 'ta': 'உறுப்பினர் பள்ளி'},
              'logoMediaId': 'm_logo1',
              'certificateMediaId': 'm_cert1',
              'description': {'en': 'Annual membership.'},
              'target': 'https://example.test/registry/123',
              'issued': {'en': '2024-03'},
              'expires': {'en': '2027-03'},
            }),
            _item('i_accred0002', name: 'Synthetic Teacher Training Board', extra: {'logoMediaId': 'm_logo2'}),
            _item('i_accred0003', name: 'Synthetic Early Years Forum'),
          ],
      ...extra,
    };

Map<String, dynamic> _html(String source, {String id = 'b_html000001'}) => {'id': id, 'type': 'html', 'v': 1, 'html': {'en': source}};

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

  Future<void> pumpBlocks(WidgetTester tester, List<WebsiteBlock> blocks, {Size at = _desktop, bool interactive = true, PublicLanguage language = PublicLanguage.english, Map<String, WebsiteMedia>? media}) async {
    await size(tester, at);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: WebsiteDesignScope(
            design: SiteDesign.defaults,
            child: WebsiteBlocksView(blocks: blocks, media: media ?? _published, language: language, interactive: interactive, fullBleed: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The text spans drawn by [finder]'s RichTexts.
  List<TextSpan> spans(WidgetTester tester, Finder finder) {
    final out = <TextSpan>[];
    for (final rich in tester.widgetList<RichText>(find.descendant(of: finder, matching: find.byType(RichText)))) {
      rich.text.visitChildren((s) {
        if (s is TextSpan) out.add(s);
        return true;
      });
    }
    return out;
  }

  String drawnText(WidgetTester tester, Finder finder) => [for (final s in spans(tester, finder)) s.text ?? ''].join();

  group('Custom HTML: sanitizing', () {
    test('scripts are removed with their content; the rest shows', () {
      const source = '<h2>Visit us</h2><script>alert(document.cookie)</script><p>Hello</p>';
      final out = CustomHtml.sanitized(source).outerHtml;
      expect(out, isNot(contains('script')));
      expect(out, isNot(contains('alert')));
      final report = CustomHtml.report(source);
      expect(report.removedElements, {'script': 1});
      expect(report.plainText, 'Visit us Hello');
    });

    test('event handlers, styles, classes and ids are never kept', () {
      const source = '<p onclick="steal()" onmouseover="x()" style="color:red" class="c" id="i">Hi</p><img src=x onerror=alert(1)>';
      final out = CustomHtml.sanitized(source).outerHtml;
      for (final bad in ['onclick', 'onmouseover', 'onerror', 'style=', 'class=', 'id=']) {
        expect(out, isNot(contains(bad)), reason: bad);
      }
      final report = CustomHtml.report(source);
      expect(report.ignoredAttributes, containsAll(['on… (event handlers)', 'style', 'class', 'id']));
      expect(report.removedElements, isEmpty);
      expect(report.imagesNotShown, 1, reason: 'a relative image address is never loaded');
      expect(report.blockedImages, ['x']);
    });

    test('unsafe link addresses are not followed; safe ones are', () {
      for (final bad in [
        'javascript:alert(1)',
        'JaVaScRiPt:alert(1)',
        ' javascript:alert(1)',
        'vbscript:msgbox(1)',
        'data:text/html,<script>alert(1)</script>',
        'http://example.test/',
        '//evil.example/',
        'file:///etc/passwd',
        'https://user:pass@example.test/',
        'tel:+911234567890',
      ]) {
        expect(CustomHtml.linkAllowed(bad), isFalse, reason: bad);
      }
      expect(CustomHtml.report('<a href="&#106;avascript:alert(1)">x</a>').blockedLinks, ['javascript:alert(1)'], reason: 'entities are decoded first');
      // tel: is removed by the sanitizer, so it isn't offered (the Buttons
      // block has phone links).
      for (final good in ['https://example.test/x', 'mailto:office@example.test', '/admissions', '/pages/open-day']) {
        expect(CustomHtml.linkAllowed(good), isTrue, reason: good);
      }
    });

    test('embeds, forms and other unsafe elements are removed', () {
      const source = '<iframe src="https://example.test"></iframe><object data="x"></object><embed src="x"><svg onload="alert(1)"><text>t</text></svg>'
          '<math><mi>x</mi></math><style>body{display:none}</style><form action="https://example.test"><input name="a"></form>'
          '<link rel="stylesheet" href="x"><meta http-equiv="refresh" content="0;url=https://example.test"><base href="https://example.test/"><p>Safe</p>';
      final out = CustomHtml.sanitized(source).outerHtml;
      for (final bad in ['<iframe', '<object', '<embed', '<svg', '<math', '<style', '<form', '<input', '<link', '<meta', '<base']) {
        expect(out, isNot(contains(bad)), reason: bad);
      }
      expect(CustomHtml.report(source).plainText, 'Safe');
    });

    test('malformed markup is repaired, not trusted; deep nesting stops', () {
      expect(CustomHtml.report('<p><b>bold<p>next').plainText, 'bold next');
      expect(CustomHtml.report('<scr<script>ipt>alert(1)</script>').plainText, isEmpty);
      expect(CustomHtml.report('a < b and c > d').plainText, 'a < b and c > d');
      final deep = '${'<div>' * 200}deep${'</div>' * 200}';
      final report = CustomHtml.report(deep);
      expect(report.removedElements.keys, contains('nested too deeply'));
    });

    test('the block: source kept as saved; required; nothing-visible is a problem; mixed is allowed', () {
      const source = '<h2>Our day</h2>\n<ul>\n  <li>Arrival</li>\n  <li onclick="x()">Work cycle</li>\n</ul>';
      final block = _parse(_html(source));
      expect(block.toMap()['html'], {'en': source, 'ta': ''}, reason: 'saved exactly as typed');
      expect(BlockRegistry.blockProblems(block), isEmpty);
      expect(BlockRegistry.blockProblems(_parse(_html(''))).single, contains('enter html in English'));
      expect(BlockRegistry.blockProblems(_parse(_html('<script>alert(1)</script>'))).single, contains('nothing in this HTML can be shown'));
      expect((BlockRegistry.html.field('html')! as dynamic).translatable, isFalse, reason: 'one markup for every language');
    });
  });

  group('Custom HTML: drawn as text', () {
    const source = '<h2>Visiting</h2><p>Write to <a href="mailto:office@example.test">the office</a> or <a href="javascript:alert(1)">this</a>.</p>'
        '<ul><li>Bring <strong>shoes</strong></li><li><em>Arrive</em> early</li></ul><script>document.write("x")</script><hr><blockquote>Quiet please</blockquote>';

    testWidgets('headings, lists, quotes and links in the site styles; scripts never drawn; unsafe links are plain text', (tester) async {
      await pumpBlocks(tester, [_parse(_html(source))]);
      final html = key('public-html-b_html000001');
      expect(html, findsOneWidget);
      final text = drawnText(tester, html);
      expect(text, allOf(contains('Visiting'), contains('the office'), contains('shoes'), contains('Quiet please')));
      expect(text, isNot(contains('document.write')));
      expect(find.descendant(of: html, matching: find.text('•')), findsNWidgets(2));
      final links = [for (final s in spans(tester, html)) if (s.recognizer != null) s.text];
      expect(links, ['the office'], reason: 'only the safe link is followed');
      expect(tester.widget<Semantics>(find.ancestor(of: find.descendant(of: html, matching: find.textContaining('Visiting')).first, matching: find.byType(Semantics)).first).properties.header, isTrue);
    });

    testWidgets('in the editor (not interactive) no link is followed', (tester) async {
      await pumpBlocks(tester, [_parse(_html(source))], interactive: false);
      expect([for (final s in spans(tester, key('public-html-b_html000001'))) if (s.recognizer != null) s], isEmpty);
    });

    testWidgets('phone, tablet and desktop: no overflow or exception', (tester) async {
      final long = '<p>${'Averyveryverylongwordwithoutanyspaces' * 4} and text</p><pre>${'x' * 300}</pre>';
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pumpBlocks(tester, [_parse(_html(long))], at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        expect(tester.getRect(key('public-html-b_html000001')).right, lessThanOrEqualTo(at.width));
      }
    });

    testWidgets('a script-only block is not shown to visitors', (tester) async {
      await pumpBlocks(tester, [_parse(_html('<script>alert(1)</script>'))]);
      expect(key('public-html-b_html000001'), findsNothing);
    });
  });

  group('Custom HTML: images', () {
    // The snippet from the browser check: an accreditation badge.
    const iao = '''<div style="background-color: #fff!important;padding: 5px!important;width: 120px!important;height: 120px!important;border-radius: 50%!important;box-shadow: 0 0 10px 5px rgba(0,0,0,.1)!important;z-index: 999!important;">
<a href="https://www.iao.org/India-TamilNadu/2D-Montessori" target="_blank" title="International Accreditation Organization - IAO">
<img src="https://www.iao.org/assets/images/email/seal/iao-seal.png" alt="International Accreditation Organization - IAO" width="110" height="110" style="width: 100%!important;height: 100%!important;">
</a>
</div>''';
    const label = 'International Accreditation Organization - IAO';
    const seal = 'https://www.iao.org/assets/images/email/seal/iao-seal.png';
    const html = 'public-html-b_html000001';

    /// Puts a loaded [width]×[height] picture in the image cache for each
    /// address, as if downloaded (tests never use the network).
    Future<void> serve(WidgetTester tester, Map<String, (int, int)> images) async {
      for (final MapEntry(key: url, value: (width, height)) in images.entries) {
        final image = (await tester.runAsync(() => createTestImage(width: width, height: height)))!;
        imageCache.putIfAbsent(NetworkImage(url), () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image))));
      }
      addTearDown(() => imageCache
        ..clear()
        ..clearLiveImages());
    }

    /// The addresses of the images drawn under [finder], in order.
    List<String> drawn(WidgetTester tester, Finder finder) => [
          for (final i in tester.widgetList<Image>(find.descendant(of: finder, matching: find.byType(Image))))
            if (i.image case final NetworkImage n) n.url,
        ];

    bool loaded(WidgetTester tester, Finder image) => tester.widget<RawImage>(find.descendant(of: image, matching: find.byType(RawImage))).image != null;

    List<String> linked(WidgetTester tester, Finder finder) => [for (final s in spans(tester, finder)) if (s.recognizer != null) (s.text ?? '').trim()]..removeWhere((t) => t.isEmpty);

    /// Records what url_launcher is asked to open.
    List<String> launches() {
      final opened = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') opened.add((call.arguments as Map)['url'] as String);
        return call.method == 'canLaunch' || call.method == 'launch';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      return opened;
    }

    testWidgets('1. a normal https image is drawn as an image, at its width and height, with its description for screen readers', (tester) async {
      const source = '<p>Our seal:</p><p><img src="https://example.test/logo.png" alt="Our logo" width="200" height="100"></p>';
      final report = CustomHtml.report(source);
      expect([report.hasContent, report.imagesShown, report.imagesWithoutAlt, report.imagesNotShown], [true, 1, 0, 0]);
      expect(report.blockedImages, isEmpty);
      expect(BlockRegistry.blockProblems(_parse(_html(source))), isEmpty);

      await serve(tester, {'https://example.test/logo.png': (400, 200)});
      final semantics = tester.ensureSemantics();
      await pumpBlocks(tester, [_parse(_html(source))]);
      expect(drawn(tester, key(html)), ['https://example.test/logo.png']);
      expect(loaded(tester, key('public-html-image-0')), isTrue, reason: 'the picture itself, not its description');
      expect(tester.getSize(key('public-html-image-0')), const Size(200, 100));
      expect(drawnText(tester, key(html)), isNot(contains('Our logo')), reason: 'alt text is not drawn in place of the image');
      expect(find.bySemanticsLabel('Our logo'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('2. the IAO snippet: the seal is drawn and opens the link on the website; no underlined text; announced as a link', (tester) async {
      final block = _parse(_html(iao));
      expect(BlockRegistry.blockProblems(block), isEmpty);
      final report = CustomHtml.report(iao);
      expect([report.hasContent, report.imagesShown, report.imagesAsLinkText, report.imagesNotShown, report.imagesWithoutAlt], [true, 1, 0, 0, 0]);
      expect(report.removedElements, isEmpty);
      expect(report.emptyLinks, isEmpty);
      expect(report.ignoredAttributes, containsAll(['style', 'target']));
      expect(report.plainText, label);

      final opened = launches();
      await serve(tester, {seal: (220, 220)});
      final semantics = tester.ensureSemantics();
      await pumpBlocks(tester, [block]);
      expect(drawn(tester, key(html)), [seal]);
      expect(loaded(tester, key('public-html-image-0')), isTrue);
      expect(tester.getSize(key('public-html-image-0')), const Size(110, 110), reason: 'its width and height attributes');
      expect(drawnText(tester, key(html)).trim(), isEmpty, reason: 'no text link, underlined or not');
      expect(linked(tester, key(html)), isEmpty);
      expect(tester.getSemantics(key('public-html-image-0-link')), isSemantics(isLink: true, label: label));

      await tester.tap(key('public-html-image-0'));
      await tester.pumpAndSettle();
      expect(opened, ['https://www.iao.org/India-TamilNadu/2D-Montessori']);
      semantics.dispose();
    });

    testWidgets('3. the editor’s preview, its canvas and the website draw the same images; links open only on the website', (tester) async {
      const source = '$iao<p><img src="http://example.test/plain.png" alt="Plain"><img src="https://example.test/second.png" alt="Second"></p>';
      final block = _parse(_html(source));
      await serve(tester, {seal: (220, 220), 'https://example.test/second.png': (300, 100)});
      final opened = launches();

      await pumpBlocks(tester, [block]);
      final published = drawn(tester, key(html));
      expect(published, [seal, 'https://example.test/second.png'], reason: 'http is never loaded');
      expect(tester.widget<GestureDetector>(find.descendant(of: key('public-html-image-0-link'), matching: find.byType(GestureDetector))).onTap, isNotNull);

      await pumpBlocks(tester, [block], interactive: false);
      expect(drawn(tester, key(html)), published);
      expect(tester.widget<GestureDetector>(find.descendant(of: key('public-html-image-0-link'), matching: find.byType(GestureDetector))).onTap, isNull, reason: 'the canvas doesn’t follow links');

      await size(tester, const Size(900, 3000));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WebsiteBlockForm(block: block, library: const [], generation: 0, onChanged: (_) {})))));
      await tester.pumpAndSettle();
      final preview = key('website-block-b_html000001-html-preview');
      expect(drawn(tester, preview), published);
      await tester.tap(find.descendant(of: preview, matching: key('public-html-image-0')));
      await tester.pumpAndSettle();
      expect(opened, isEmpty, reason: 'the preview doesn’t follow links');
      expect(find.descendant(of: key('website-block-b_html000001-html-removed'), matching: find.textContaining('http://example.test/plain.png')), findsOneWidget);
      expect(find.textContaining('images from https:// addresses'), findsOneWidget);
    });

    test('4. only absolute https image addresses are loaded, checked apart from links', () {
      for (final bad in [
        'javascript:alert(1)',
        'JaVaScRiPt:alert(1)',
        'data:image/png;base64,AAAA',
        'data:image/svg+xml,<svg onload=alert(1)>',
        'blob:https://example.test/0f1e',
        'http://example.test/a.png',
        '//example.test/a.png',
        '/assets/a.png',
        'a.png',
        'https:example.test/a.png',
        'https:///a.png',
        'https://user:pass@example.test/a.png',
        'https://example.test:8443/a.png',
        'ftp://example.test/a.png',
        'file:///etc/passwd',
        'https://exa mple.test/a.png',
        'https://example.test\\a.png',
        'https://example.test/${'a' * 2100}.png',
        '',
        null,
      ]) {
        expect(CustomHtml.imageAllowed(bad), isFalse, reason: bad);
      }
      for (final good in ['https://example.test/a.png', ' https://cdn.example.test/logo.png?v=2 ', 'HTTPS://example.test/a.png', 'https://example.test:443/a.png']) {
        expect(CustomHtml.imageAllowed(good), isTrue, reason: good);
      }
      // Links and images are checked separately: mailto and site pages
      // are links, never images.
      for (final linkOnly in ['mailto:office@example.test', '/admissions']) {
        expect((CustomHtml.linkAllowed(linkOnly), CustomHtml.imageAllowed(linkOnly)), (true, false), reason: linkOnly);
      }
      const source = '<p>x</p><img src="javascript:alert(1)"><img src="data:image/png;base64,AAAA"><img src="http://example.test/a.png"><img src="blob:https://example.test/0f1e">';
      final report = CustomHtml.report(source);
      expect(report.blockedImages, ['javascript:alert(1)', 'data:image/png;base64,AAAA', 'http://example.test/a.png', 'blob:https://example.test/0f1e']);
      expect((report.imagesShown, report.imagesNotShown), (0, 4));
    });

    testWidgets('5. unsafe images are never drawn; onerror, onclick, scripts and unsafe links are stripped', (tester) async {
      const source = '<a href="javascript:alert(1)"><img src="https://example.test/a.png" onerror="alert(2)" onclick="steal()" alt="A"></a>'
          '<script>alert(3)</script><img src="https://example.test/b.png" onload="alert(4)" style="position:fixed" alt="B">'
          '<img src="javascript:alert(5)" alt="C"><img src="data:image/png;base64,AAAA" alt="D"><img src=x onerror=alert(6)>';
      final out = CustomHtml.sanitized(source).outerHtml;
      for (final bad in ['onerror', 'onclick', 'onload', '<script', 'alert(3)', 'javascript:', 'style=']) {
        expect(out, isNot(contains(bad)), reason: bad);
      }
      final report = CustomHtml.report(source);
      expect(report.removedElements, {'script': 1});
      expect(report.ignoredAttributes, containsAll(['on… (event handlers)', 'style']));
      expect(report.blockedLinks, ['javascript:alert(1)']);
      expect(report.blockedImages, ['javascript:alert(5)', 'data:image/png;base64,AAAA', 'x']);

      await serve(tester, {'https://example.test/a.png': (50, 50), 'https://example.test/b.png': (50, 50)});
      final opened = launches();
      await pumpBlocks(tester, [_parse(_html(source))]);
      expect(drawn(tester, key(html)), ['https://example.test/a.png', 'https://example.test/b.png']);
      expect(key('public-html-image-0-link'), findsNothing, reason: 'the javascript: link is not a link');
      await tester.tap(key('public-html-image-0'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(drawnText(tester, key(html)), isNot(anyOf(contains('alert'), contains('C'), contains('D'))));
    });

    testWidgets('6. oversized images are scaled to fit, keeping their shape, at every width', (tester) async {
      const source = '<p><img src="https://example.test/wide.png" alt="Wide" width="3000" height="1500"></p>'
          '<p><img src="https://example.test/natural.png" alt="Natural"></p>'
          '<p><img src="https://example.test/tall.png" alt="Tall"></p>'
          '<p><img src="https://example.test/odd.png" alt="Odd" width="100%" height="auto"></p>';
      await serve(tester, {
        'https://example.test/wide.png': (300, 150),
        'https://example.test/natural.png': (4000, 500),
        'https://example.test/tall.png': (300, 5000),
        'https://example.test/odd.png': (2400, 1200),
      });
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pumpBlocks(tester, [_parse(_html(source))], at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        final block = tester.getRect(key(html));
        expect(block.right, lessThanOrEqualTo(at.width));
        for (final (i, ratio) in [(0, 2.0), (1, 8.0), (2, 0.06), (3, 2.0)]) {
          final rect = tester.getRect(key('public-html-image-$i'));
          expect(rect.left, greaterThanOrEqualTo(block.left - 0.01), reason: '$i at ${at.width}');
          expect(rect.right, lessThanOrEqualTo(block.right + 0.01), reason: '$i at ${at.width}');
          expect(rect.height, lessThanOrEqualTo(PublicCustomHtmlImage.maxHeight + 0.01));
          expect(rect.width / rect.height, closeTo(ratio, 0.01), reason: 'shape kept: $i at ${at.width}');
        }
      }
    });

    testWidgets('7. an image-only link without a description: the picture still shows and the editor asks for alt text', (tester) async {
      const bare = '<a href="https://example.test/"><img src="https://example.test/seal.png"></a>';
      final report = CustomHtml.report(bare);
      expect([report.hasContent, report.onlyImages, report.imagesShown, report.imagesWithoutAlt], [true, false, 1, 1]);
      expect(report.emptyLinks, isEmpty);
      expect(BlockRegistry.blockProblems(_parse(_html(bare))), isEmpty);
      await serve(tester, {'https://example.test/seal.png': (80, 80)});
      await pumpBlocks(tester, [_parse(_html(bare))]);
      expect(drawn(tester, key(html)), ['https://example.test/seal.png']);

      await size(tester, const Size(900, 3000));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WebsiteBlockForm(block: _parse(_html(bare)), library: const [], generation: 0, onChanged: (_) {})))));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('website-block-b_html000001-html-alt'), matching: find.textContaining('alt=')), findsOneWidget);
    });

    testWidgets('8. images that can’t be drawn: a description inside a safe link, else nothing; only such images is a clear problem', (tester) async {
      const blocked = '<a href="https://example.test/"><img src="http://example.test/seal.png"></a><img src="data:image/png;base64,AAAA" alt="Seal">';
      expect(CustomHtml.report(blocked).onlyImages, isTrue);
      expect(BlockRegistry.blockProblems(_parse(_html(blocked))).single, allOf(contains('https://'), contains('Accreditations & Recognition'), contains('Image block')));
      await pumpBlocks(tester, [_parse(_html(blocked))]);
      expect(key(html), findsNothing);

      const titled = '<a href="https://example.test/" title="Our accreditation"><img src="http://example.test/seal.png" alt="  "></a>';
      expect(CustomHtml.report(titled).plainText, 'Our accreditation');
      await pumpBlocks(tester, [_parse(_html(titled))]);
      expect(linked(tester, key(html)), ['Our accreditation']);
      expect(find.byType(Image), findsNothing);
    });

    test('9. script-only or style-only markup keeps “nothing can be shown”', () {
      for (final source in ['<script>alert(1)</script>', '<style>p{color:red}</style>', '<iframe src="https://example.test"></iframe>']) {
        final problems = BlockRegistry.blockProblems(_parse(_html(source)));
        expect(problems.single, contains('nothing in this HTML can be shown'), reason: source);
        expect(problems.single, isNot(contains('images')));
      }
    });

    testWidgets('10. a hostile description is plain text, never markup; a picture that fails to load shows its description', (tester) async {
      const hostile = '<a href="https://example.test/ok"><img alt="<script>alert(1)</script> javascript:alert(2)" onerror="alert(3)" src="javascript:alert(4)"></a>';
      expect(CustomHtml.sanitized(hostile).outerHtml, isNot(contains('onerror')));
      expect(CustomHtml.report(hostile).imagesAsLinkText, 1);
      await pumpBlocks(tester, [_parse(_html(hostile))]);
      expect(linked(tester, key(html)), ['<script>alert(1)</script> javascript:alert(2)'], reason: 'drawn as text, the link still goes to the https address');
      expect(find.byType(Image), findsNothing);

      // Not in the cache: the test network refuses it, as a broken image would.
      await pumpBlocks(tester, [_parse(_html('<p><img src="https://example.test/missing.png" alt="School seal"></p>'))]);
      await tester.pumpAndSettle();
      expect(drawn(tester, key(html)), ['https://example.test/missing.png']);
      expect(find.descendant(of: key('public-html-image-0'), matching: find.text('School seal')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Accreditations: model', () {
    test('fields, round trip and defaults', () {
      final d = BlockRegistry.accreditations;
      expect(d.label, 'Accreditations & Recognition');
      final raw = _plain(_accreditations()) as Map<String, dynamic>;
      final block = _parse(raw);
      expect(BlockRegistry.blockProblems(block), isEmpty);
      final saved = _plain(block.toMap()) as Map<String, dynamic>;
      expect(saved.containsKey('desktopColumns'), isFalse, reason: 'per-row settings stored only when set');
      expect(saved['heading'], {'en': 'Accreditations', 'ta': 'அங்கீகாரங்கள்'});
      expect([for (final i in saved['items'] as List) i['id']], ['i_accred0001', 'i_accred0002', 'i_accred0003'], reason: 'the order is the display order');
      expect(BlockRegistry.referencedMedia([block]), ['m_logo1', 'm_cert1', 'm_logo2'], reason: 'the library knows the images are used');
      final created = BlockRegistry.create(d);
      expect(created.items('items'), hasLength(1));
      expect(BlockRegistry.blockProblems(created).single, contains('organisation or accrediting body'));
    });

    test('dates: three forms, real days only, expiry not before issue', () {
      expect(AccreditationDate.tryParse('2024')?.format((m) => '$m'), '2024');
      expect(AccreditationDate.tryParse('2024-03')?.format((m) => 'M$m'), 'M3 2024');
      expect(AccreditationDate.tryParse('2024-03-05')?.format((m) => 'M$m'), '5 M3 2024');
      for (final bad in ['24', '2024-13', '2024-02-30', 'March 2024', '2024/03', '1800']) {
        expect(AccreditationDate.tryParse(bad), isNull, reason: bad);
      }
      List<String> problems(String issued, String expires) => BlockRegistry.blockProblems(_parse(_accreditations(items: [
            _item('i_accred0001', extra: {'issued': {'en': issued}, 'expires': {'en': expires}}),
          ])));
      expect(problems('2024-03', '2027'), isEmpty);
      expect(problems('2024-05', '2024'), isEmpty, reason: 'a year runs to its last day');
      expect(problems('2025', '2024-12').single, contains('expiry date is before the issue date'));
      expect(problems('next year', '').single, contains('write the issue date as'));
      expect(problems('', '2024-02-30').single, contains('write the expiry date as'));
      expect(problems('', ''), isEmpty, reason: 'dates are optional');
    });

    test('an unsafe link is a problem, as everywhere on the site', () {
      final block = _parse(_accreditations(items: [_item('i_accred0001', extra: {'target': 'javascript:alert(1)'})]));
      expect(BlockRegistry.blockProblems(block).single, contains('Accreditation 1'));
    });
  });

  group('Accreditations: drawn', () {
    testWidgets('cards: 3 per row on desktop, 2 on tablets, 1 on phones; no overflow at 320 px', (tester) async {
      final block = _parse(_accreditations());
      Rect card(int i) => tester.getRect(key('public-accreditation-i_accred000$i'));
      await pumpBlocks(tester, [block]);
      expect({card(1).top, card(2).top, card(3).top}.length, 1);
      await pumpBlocks(tester, [block], at: _tablet);
      expect((card(2).top, card(3).left), (card(1).top, card(1).left));
      for (final at in [_phone, _narrow]) {
        await pumpBlocks(tester, [block], at: at);
        expect(tester.takeException(), isNull);
        expect(card(2).top, greaterThan(card(1).bottom));
        expect(card(3).right, lessThanOrEqualTo(at.width));
      }
      await pumpBlocks(tester, [_parse(_accreditations(extra: {'desktopColumns': '2'}))]);
      expect((card(2).top, card(3).left), (card(1).top, card(1).left), reason: 'cards per row set to 2');
    });

    testWidgets('only what was entered: dates as entered, no verified mark; images with descriptions; no image is fine', (tester) async {
      await pumpBlocks(tester, [_parse(_accreditations())]);
      expect(find.text('Issued March 2024 · Expires March 2027'), findsOneWidget);
      expect(find.textContaining(RegExp('verified|valid|expired', caseSensitive: false)), findsNothing);
      final images = tester.widgetList<PublicWebsiteImage>(find.byType(PublicWebsiteImage)).toList();
      expect([for (final i in images) i.semanticLabel], ['Certificate on the school wall', 'Synthetic Montessori Council logo', 'Synthetic Teacher Training Board logo']);
      expect(find.descendant(of: key('public-accreditation-i_accred0003'), matching: find.byType(PublicWebsiteImage)), findsNothing);
      expect(find.descendant(of: key('public-accreditation-i_accred0003'), matching: find.byIcon(Icons.workspace_premium_outlined)), findsOneWidget);

      // Unpublished images (not among the published media) aren't shown.
      await pumpBlocks(tester, [_parse(_accreditations())], media: const {});
      expect(find.byType(PublicWebsiteImage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the link: labelled for screen readers, opens only on the website', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpBlocks(tester, [_parse(_accreditations())]);
      final link = key('public-accreditation-i_accred0001-link');
      expect(tester.widget<TextButton>(link).onPressed, isNotNull);
      expect(find.bySemanticsLabel('More information about Synthetic Montessori Council'), findsOneWidget);
      semantics.dispose();
      expect(key('public-accreditation-i_accred0002-link'), findsNothing, reason: 'no link entered');
      await pumpBlocks(tester, [_parse(_accreditations())], interactive: false);
      expect(tester.widget<TextButton>(link).onPressed, isNull);
    });

    testWidgets('logo strip: wraps at every width; names under logos; Tamil text and dates', (tester) async {
      final block = _parse(_accreditations(extra: {'display': 'logos'}));
      for (final at in [_desktop, _tablet, _phone, _narrow]) {
        await pumpBlocks(tester, [block], at: at);
        expect(tester.takeException(), isNull, reason: 'at ${at.width}');
        expect(key('public-accreditations-b_accred0001-logos'), findsOneWidget);
        for (var i = 1; i <= 3; i++) {
          expect(tester.getRect(key('public-accreditation-i_accred000$i')).right, lessThanOrEqualTo(at.width));
        }
      }
      expect(find.text('Synthetic Early Years Forum'), findsOneWidget);
      await pumpBlocks(tester, [_parse(_accreditations())], language: PublicLanguage.tamil);
      expect(find.text('அங்கீகாரங்கள்'), findsOneWidget);
      expect(find.text('உறுப்பினர் பள்ளி'), findsOneWidget);
      expect(find.text('வழங்கப்பட்டது: மார்ச் 2024 · காலாவதி: மார்ச் 2027'), findsOneWidget);
      expect(find.text('Synthetic Teacher Training Board'), findsOneWidget, reason: 'no Tamil: the English');
    });
  });

  group('in the editor', () {
    Future<String> page(List<Object?> blocks) async {
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'Scratch'), slug: 'scratch');
      await firestore.collection(WebsiteCollections.pageDrafts).doc(created.id).update({'sections': [], 'schemaVersion': 2, 'blocks': blocks});
      return created.id;
    }

    Future<void> open(WidgetTester tester, String id) async {
      await size(tester, const Size(1400, 2600));
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

    Finder field(String prefix) => find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith(prefix) == true);

    Future<void> type(WidgetTester tester, String prefix, String text) async {
      await tester.ensureVisible(field(prefix));
      await tester.pumpAndSettle();
      await tester.enterText(field(prefix), text);
      await tester.pumpAndSettle();
    }

    List<WebsiteBlock> blocks(WidgetTester tester) => tester.widget<WebsiteVisualEditor>(key('website-custom-blocks')).blocks;

    testWidgets('Add block offers both; Custom HTML: source, warning, what is removed, a preview; saved and reopened exactly', (tester) async {
      final id = await page([]);
      await open(tester, id);
      await tap(tester, key('website-blocks-add'));
      expect(find.descendant(of: key('website-blocks-add-accreditations'), matching: find.text('Accreditations & Recognition')), findsOneWidget);
      expect(find.descendant(of: key('website-blocks-add-html'), matching: find.text('Custom HTML')), findsOneWidget);
      await tester.tap(key('website-blocks-add-html'));
      await tester.pumpAndSettle();
      final htmlId = blocks(tester).single.id;
      expect(key('website-block-$htmlId-html-warning'), findsOneWidget);
      expect(find.textContaining('JavaScript is not supported'), findsOneWidget);

      const source = '<h2>Hours</h2><p onclick="x()">Open 8 to 3</p><script>alert(1)</script>';
      await type(tester, 'website-block-$htmlId-html-en', source);
      expect(find.descendant(of: key('website-block-$htmlId-html-preview'), matching: find.textContaining('Open 8 to 3')), findsOneWidget);
      expect(find.descendant(of: key('website-block-$htmlId-html-removed'), matching: find.textContaining('<script>')), findsOneWidget);
      expect(find.descendant(of: key('website-block-$htmlId-html-removed'), matching: find.textContaining('event handlers')), findsOneWidget);
      expect(find.textContaining('(Tamil)'), findsNothing);

      await tap(tester, key('website-custom-save-draft'));
      final stored = (await firestore.collection(WebsiteCollections.pageDrafts).doc(id).get()).data()!;
      expect(((stored['blocks'] as List).single as Map)['html'], {'en': source, 'ta': ''}, reason: 'the exact source');

      await open(tester, id);
      expect((blocks(tester).single as StructuredBlock).text('html').en, source);
    });

    testWidgets('Accreditations: add, fill, add another, reorder, remove; saved', (tester) async {
      final id = await page([]);
      await open(tester, id);
      await tap(tester, key('website-blocks-add'));
      await tester.tap(key('website-blocks-add-accreditations'));
      await tester.pumpAndSettle();
      StructuredBlock current() => blocks(tester).single as StructuredBlock;
      final blockId = current().id;
      final prefix = 'website-block-$blockId-items';
      final first = current().items('items').single.id;
      await type(tester, '$prefix-item-$first-name-en', 'Synthetic Montessori Council');
      await type(tester, '$prefix-item-$first-issued-en', '2024');
      await tap(tester, key('$prefix-add'));
      final second = current().items('items')[1].id;
      await type(tester, '$prefix-item-$second-name-en', 'Synthetic Forum');
      await tap(tester, key('$prefix-item-$second-up'));
      expect([for (final i in current().items('items')) i.text('name').en], ['Synthetic Forum', 'Synthetic Montessori Council']);
      expect(BlockRegistry.blockProblems(current()), isEmpty);

      await tap(tester, key('website-custom-save-draft'));
      await open(tester, id);
      expect([for (final i in current().items('items')) i.id], [second, first], reason: 'order and ids kept');
      await tap(tester, key('website-block-$blockId-select'));
      await tap(tester, key('$prefix-item-$second-remove'));
      expect([for (final i in current().items('items')) i.id], [first]);
    });
  });

  group('saved, published, drafts', () {
    // The images the page uses, published in the (fake) media library.
    Future<void> seedMedia() async {
      for (final m in _published.values) {
        await firestore.collection(WebsiteCollections.media).doc(m.id).set({
          'url': m.url, 'storagePath': m.storagePath, 'status': 'published', 'consentConfirmed': true,
          'alt': {'en': m.alt.en, 'ta': ''}, 'caption': {'en': '', 'ta': ''},
        });
      }
    }

    List<WebsiteBlock> pageBlocks() => [_parse(_accreditations()), _parse(_html('<h2>Our approach</h2><p>Calm, prepared rooms.</p>'))];

    test('draft, publish, reorder, unpublish: every value and id kept; Tamil kept', () async {
      await seedMedia();
      final created = await service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'About'), slug: 'about-us');
      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => pageBlocks()));
      var state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(_plain(BlockRegistry.toMapList(state.draft.blocks!)), _plain(BlockRegistry.toMapList(pageBlocks())));
      expect(state.live, isNull);

      await service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: state.draft);
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect(_plain(BlockRegistry.toMapList(state.live!.blocks!)), _plain(BlockRegistry.toMapList(pageBlocks())));

      await service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: state.draft.copyWith(blocks: () => pageBlocks().reversed.toList()));
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect([for (final b in state.draft.blocks!) b.type], ['html', 'accreditations']);
      expect([for (final b in state.live!.blocks!) b.type], ['accreditations', 'html'], reason: 'the published page is unchanged until published');
      expect((state.live!.blocks!.first as StructuredBlock).text('heading').ta, 'அங்கீகாரங்கள்');

      await service.unpublishCustomPage(requesterRole: 'admin', actor: _admin, pageId: created.id);
      state = (await service.getCustomPage(requesterRole: 'admin', pageId: created.id))!;
      expect((state.live, state.draft.blocks!.length), (null, 2));
    });

    testWidgets('a draft never reaches visitors; once published, both blocks show', (tester) async {
      await tester.runAsync(seedMedia);
      final created = (await tester.runAsync(() => service.createCustomPage(requesterRole: 'admin', actor: _admin, title: const LocalizedText(en: 'About'), slug: 'about-us')))!;
      await tester.runAsync(() => service.saveCustomPageDraft(requesterRole: 'admin', actor: _admin, page: created.copyWith(blocks: () => pageBlocks())));

      Future<void> visit() async {
        await size(tester, _desktop);
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
            websiteContentRepositoryProvider.overrideWithValue(WebsiteContentRepository(firestore: firestore)),
          ],
          child: const MontessoriApp(),
        ));
        await tester.pumpAndSettle();
        tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed('/pages/about-us');
        await tester.pumpAndSettle();
      }

      await visit();
      expect(find.text('Our approach'), findsNothing);
      expect(key('public-accreditation-i_accred0001'), findsNothing);

      final draft = (await tester.runAsync(() => service.getCustomPage(requesterRole: 'admin', pageId: created.id)))!.draft;
      await tester.runAsync(() => service.publishCustomPage(requesterRole: 'admin', actor: _admin, page: draft));
      await visit();
      expect(find.text('Our approach'), findsOneWidget);
      expect(key('public-accreditation-i_accred0001'), findsOneWidget);
    });
  });
}
