// Public website managed content (lib/modules/public_website/content) and
// the Gallery page:
// - Gallery is reachable from the header, the mobile menu and the footer
//   (/gallery), keeping the short back stack.
// - Only published images listed in the gallery are shown — never drafts,
//   hidden images or page-only images — in gallery order, with captions and
//   alt text (Tamil when entered, else English).
// - Loading, empty, load-error (with retry) and per-image error states;
//   category filters (only for categories in use); "show more" paging;
//   the lightbox (position, caption, next/previous, close).
// - Responsive grid: 4/3/2 columns on desktop/tablet/mobile, no overflow.
// - Homepage hero, Admissions/Teacher Training/Programs and the Gallery
//   banner take their image and text from published page content, and fall
//   back to the built-in wording and decorative placeholder when nothing is
//   published, the image isn't published, or loading fails.
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:montessori_app/main.dart';
import 'package:montessori_app/modules/auth/providers/auth_state_provider.dart';
import 'package:montessori_app/modules/public_website/content/website_content_models.dart';
import 'package:montessori_app/modules/public_website/content/website_content_repository.dart';
import 'package:montessori_app/modules/public_website/public_routes.dart';
import 'package:montessori_app/modules/public_website/ui/public_gallery_page.dart';
import 'package:montessori_app/modules/public_website/ui/public_home_page.dart';

const _desktop = Size(1400, 1000);
const _tablet = Size(900, 1000);
const _mobile = Size(375, 800);

Map<String, dynamic> _media({
  String status = 'published',
  bool inGallery = true,
  int order = 0,
  String category = 'general',
  String alt = 'Alt text',
  String altTa = '',
  String caption = '',
  String captionTa = '',
}) =>
    {
      'url': 'https://example.test/display.jpg',
      'thumbUrl': 'https://example.test/thumb.jpg',
      'storagePath': 'website_media/x/display.jpg',
      'width': 1600,
      'height': 1200,
      'focalX': 0.5,
      'focalY': 0.5,
      'alt': {'en': alt, 'ta': altTa},
      'caption': {'en': caption, 'ta': captionTa},
      'category': category,
      'status': status,
      'inGallery': inGallery,
      'galleryOrder': order,
      'consentConfirmed': true,
    };

/// Fails (or never finishes) on demand, for the error/loading states.
class _ControlledRepository extends WebsiteContentRepository {
  _ControlledRepository(this.inner) : super(firestore: FakeFirebaseFirestore());

  final WebsiteContentRepository inner;
  bool fail = false;
  Completer<void>? hold;
  int mediaLoads = 0;

  @override
  Future<List<WebsiteMedia>> publishedMedia() async {
    mediaLoads++;
    if (hold != null) await hold!.future;
    if (fail) throw StateError('offline');
    return inner.publishedMedia();
  }

  @override
  Future<LiveWebsiteContent> liveContent() async {
    if (fail) throw StateError('offline');
    return inner.liveContent();
  }
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> addMedia(String id, Map<String, dynamic> data) => firestore.collection(WebsiteCollections.media).doc(id).set(data);
  Future<void> addLivePage(WebsitePageSlot slot, Map<String, dynamic> data) => firestore.collection(WebsiteCollections.livePages).doc(slot.id).set(data);

  Future<void> pumpSite(
    WidgetTester tester, {
    Size size = _desktop,
    WebsiteContentRepository? repository,
    String initialRoute = PublicRoutes.home,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        websiteContentRepositoryProvider.overrideWithValue(repository ?? WebsiteContentRepository(firestore: firestore)),
      ],
      child: const MontessoriApp(),
    ));
    await tester.pumpAndSettle();
    if (initialRoute != PublicRoutes.home) {
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(initialRoute);
      // A loading spinner never settles; pump past the page transition.
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }
    }
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder item(String id) => find.byKey(Key('public-gallery-item-$id'));

  group('Gallery navigation', () {
    testWidgets('header link opens /gallery; Home returns with a short back stack', (tester) async {
      await pumpSite(tester);
      await tapAndSettle(tester, find.byKey(const Key('public-nav-/gallery')));
      expect(find.byType(PublicGalleryPage), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('public-section-title'))).data, 'Gallery');
      await tapAndSettle(tester, find.byKey(const Key('public-nav-/')));
      expect(find.byType(PublicHomePage), findsOneWidget);
      expect(tester.state<NavigatorState>(find.byType(Navigator).first).canPop(), isFalse);
    });

    testWidgets('mobile menu and footer reach the gallery', (tester) async {
      await pumpSite(tester, size: _mobile);
      await tapAndSettle(tester, find.byKey(const Key('public-menu-button')));
      expect(find.byKey(const Key('public-menu-/gallery')), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('public-menu-/gallery')));
      expect(find.byType(PublicGalleryPage), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('public-footer-/')));
      expect(find.byType(PublicHomePage), findsOneWidget);
      await tapAndSettle(tester, find.byKey(const Key('public-footer-/gallery')));
      expect(find.byType(PublicGalleryPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tamil navigation label', (tester) async {
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);
      await tapAndSettle(tester, find.text('தமிழ்'));
      expect(tester.widget<Text>(find.byKey(const Key('public-section-title'))).data, 'படத்தொகுப்பு');
    });
  });

  group('published vs unpublished', () {
    testWidgets('only published gallery images appear, in gallery order, with captions', (tester) async {
      await addMedia('second', _media(order: 2, alt: 'Second alt', caption: 'Second caption'));
      await addMedia('first', _media(order: 1, alt: 'First alt', caption: 'First caption'));
      await addMedia('draft', _media(status: 'draft', alt: 'Draft alt', caption: 'Draft caption'));
      await addMedia('hidden', _media(status: 'hidden', alt: 'Hidden alt', caption: 'Hidden caption'));
      await addMedia('pageOnly', _media(inGallery: false, alt: 'Page only alt', caption: 'Page only caption'));
      await addMedia('noFile', {..._media(alt: 'No file'), 'url': ''});
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);

      expect(item('first'), findsOneWidget);
      expect(item('second'), findsOneWidget);
      for (final id in ['draft', 'hidden', 'pageOnly', 'noFile']) {
        expect(item(id), findsNothing, reason: '$id must not be shown');
      }
      expect(find.text('Draft caption'), findsNothing);
      expect(find.text('Hidden caption'), findsNothing);
      expect(find.text('First caption'), findsOneWidget);
      expect(tester.getTopLeft(item('first')).dx, lessThan(tester.getTopLeft(item('second')).dx), reason: 'gallery order');
      expect(find.bySemanticsLabel('First alt'), findsWidgets, reason: 'alt text is the accessible label');
    });

    testWidgets('Tamil captions and alt text when entered, English otherwise', (tester) async {
      await addMedia('a', _media(order: 1, caption: 'English caption', captionTa: 'தமிழ் தலைப்பு'));
      await addMedia('b', _media(order: 2, caption: 'Only English'));
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);
      await tapAndSettle(tester, find.text('தமிழ்'));
      expect(find.text('தமிழ் தலைப்பு'), findsOneWidget);
      expect(find.text('English caption'), findsNothing);
      expect(find.text('Only English'), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('empty: a friendly message, no grid', (tester) async {
      await addMedia('draft', _media(status: 'draft'));
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);
      expect(find.byKey(const Key('public-gallery-empty')), findsOneWidget);
      expect(find.byKey(const Key('public-gallery-grid')), findsNothing);
    });

    testWidgets('loading, then the grid', (tester) async {
      await addMedia('a', _media());
      final repository = _ControlledRepository(WebsiteContentRepository(firestore: firestore))..hold = Completer<void>();
      await pumpSite(tester, repository: repository, initialRoute: PublicRoutes.gallery, settle: false);
      expect(find.byKey(const Key('public-gallery-loading')), findsOneWidget);
      repository.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('public-gallery-loading')), findsNothing);
      expect(item('a'), findsOneWidget);
    });

    testWidgets('load error: message and retry, which loads again', (tester) async {
      await addMedia('a', _media());
      final repository = _ControlledRepository(WebsiteContentRepository(firestore: firestore))..fail = true;
      await pumpSite(tester, repository: repository, initialRoute: PublicRoutes.gallery);
      expect(find.byKey(const Key('public-gallery-error')), findsOneWidget);
      expect(tester.takeException(), isNull);

      repository.fail = false;
      await tapAndSettle(tester, find.byKey(const Key('public-gallery-retry')));
      expect(find.byKey(const Key('public-gallery-error')), findsNothing);
      expect(item('a'), findsOneWidget);
    });

    testWidgets('an image that fails to load shows the placeholder, not an exception', (tester) async {
      await addMedia('a', _media());
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);
      // The test environment answers every network request with HTTP 400.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('public-image-error-a')), findsOneWidget);
      expect(find.descendant(of: item('a'), matching: find.byKey(const Key('public-image-placeholder'))), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('filters, paging and lightbox', () {
    testWidgets('category filters appear for categories in use and filter the grid', (tester) async {
      await addMedia('c1', _media(order: 1, category: 'classroom'));
      await addMedia('c2', _media(order: 2, category: 'classroom'));
      await addMedia('o1', _media(order: 3, category: 'outdoors'));
      await addMedia('e1', _media(order: 4, category: 'events', status: 'draft'));
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);

      expect(find.byKey(const Key('public-gallery-filter-all')), findsOneWidget);
      expect(find.byKey(const Key('public-gallery-filter-classroom')), findsOneWidget);
      expect(find.byKey(const Key('public-gallery-filter-outdoors')), findsOneWidget);
      expect(find.byKey(const Key('public-gallery-filter-events')), findsNothing, reason: 'only drafts there');
      expect(find.byKey(const Key('public-gallery-filter-campus')), findsNothing);

      await tapAndSettle(tester, find.byKey(const Key('public-gallery-filter-outdoors')));
      expect(item('o1'), findsOneWidget);
      expect(item('c1'), findsNothing);
      await tapAndSettle(tester, find.byKey(const Key('public-gallery-filter-all')));
      expect(item('c1'), findsOneWidget);
      expect(item('o1'), findsOneWidget);
    });

    testWidgets('no filters when every photograph is in one category', (tester) async {
      await addMedia('a', _media(order: 1));
      await addMedia('b', _media(order: 2));
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);
      expect(find.byKey(const Key('public-gallery-filters')), findsNothing);
    });

    testWidgets('shows ${PublicGalleryPage.pageSize} at a time, then more', (tester) async {
      for (var i = 0; i < 30; i++) {
        await addMedia('m$i', _media(order: i));
      }
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);
      expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('public-gallery-item-')), findsNWidgets(24));
      await tapAndSettle(tester, find.byKey(const Key('public-gallery-show-more')));
      expect(item('m29'), findsOneWidget);
      expect(find.byKey(const Key('public-gallery-show-more')), findsNothing);
    });

    testWidgets('lightbox: opens at the tapped photograph, moves next/previous, closes', (tester) async {
      await addMedia('a', _media(order: 1, caption: 'Caption A'));
      await addMedia('b', _media(order: 2, caption: 'Caption B'));
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);

      await tapAndSettle(tester, find.descendant(of: item('b'), matching: find.byType(InkWell)));
      expect(find.byKey(const Key('public-gallery-lightbox')), findsOneWidget);
      String text(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;
      expect(text('public-gallery-lightbox-position'), '2 of 2');
      expect(text('public-gallery-lightbox-caption'), 'Caption B');
      expect(find.byKey(const Key('public-gallery-lightbox-next')), findsNothing, reason: 'last photograph');

      await tapAndSettle(tester, find.byKey(const Key('public-gallery-lightbox-previous')));
      expect(text('public-gallery-lightbox-position'), '1 of 2');
      expect(text('public-gallery-lightbox-caption'), 'Caption A');

      await tapAndSettle(tester, find.byKey(const Key('public-gallery-lightbox-close')));
      expect(find.byKey(const Key('public-gallery-lightbox')), findsNothing);
      expect(find.byType(PublicGalleryPage), findsOneWidget);
    });
  });

  group('responsive layout', () {
    for (final (name, size, columns) in [('desktop', _desktop, 4), ('tablet', _tablet, 3), ('mobile', _mobile, 2), ('320px', const Size(320, 700), 2)]) {
      testWidgets('$name: $columns columns, consistent 4:3 tiles, no overflow', (tester) async {
        for (var i = 0; i < 6; i++) {
          await addMedia('m$i', _media(order: i, caption: 'A caption long enough to wrap onto a second line in a narrow tile', category: i.isEven ? 'classroom' : 'outdoors'));
        }
        await pumpSite(tester, size: size, initialRoute: PublicRoutes.gallery);
        expect(tester.takeException(), isNull);
        final firstRowY = tester.getTopLeft(item('m0')).dy;
        final inFirstRow = [for (var i = 0; i < 6; i++) tester.getTopLeft(item('m$i')).dy].where((y) => y == firstRowY).length;
        expect(inFirstRow, columns);
        final image = find.descendant(of: item('m0'), matching: find.byType(AspectRatio)).first;
        expect(tester.widget<AspectRatio>(image).aspectRatio, closeTo(4 / 3, 0.001));

        await tapAndSettle(tester, find.descendant(of: item('m0'), matching: find.byType(InkWell)));
        expect(find.byKey(const Key('public-gallery-lightbox')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'lightbox fits at $name');
      });
    }
  });

  group('content-driven page images', () {
    testWidgets('homepage hero: published image and text replace the built-in ones', (tester) async {
      await addMedia('hero', _media(inGallery: false, alt: 'Hero alt'));
      await addLivePage(WebsitePageSlot.home, {
        'imageMediaId': 'hero',
        'headline': {'en': 'Managed headline', 'ta': 'நிர்வகிக்கப்பட்ட தலைப்பு'},
        'intro': {'en': 'Managed intro', 'ta': ''},
      });
      await pumpSite(tester);
      expect(find.byKey(const Key('public-hero-image')), findsOneWidget);
      expect(find.byKey(const Key('public-hero-ornament')), findsNothing);
      expect(find.text('Managed headline'), findsOneWidget);
      expect(find.text('Managed intro'), findsOneWidget);

      await tapAndSettle(tester, find.text('தமிழ்'));
      expect(find.text('நிர்வகிக்கப்பட்ட தலைப்பு'), findsOneWidget);
      expect(find.text('Managed intro'), findsOneWidget, reason: 'no Tamil entered: the managed English text, not unrelated built-in Tamil');
    });

    testWidgets('homepage hero falls back when nothing is published', (tester) async {
      await pumpSite(tester);
      expect(find.byKey(const Key('public-hero-ornament')), findsOneWidget);
      expect(find.text('A calm, thoughtful place to learn and grow'), findsOneWidget);
    });

    testWidgets('a live page whose image is hidden falls back to the placeholder', (tester) async {
      await addMedia('hero', _media(status: 'hidden'));
      await addLivePage(WebsitePageSlot.home, {'imageMediaId': 'hero', 'headline': {'en': ''}, 'intro': {'en': ''}});
      await pumpSite(tester);
      expect(find.byKey(const Key('public-hero-image')), findsNothing);
      expect(find.byKey(const Key('public-hero-ornament')), findsOneWidget);
      expect(find.text('A calm, thoughtful place to learn and grow'), findsOneWidget, reason: 'blank managed text keeps the built-in wording');
    });

    testWidgets('mobile hero shows a published image below the text, and nothing extra without one', (tester) async {
      await pumpSite(tester, size: _mobile);
      expect(find.byKey(const Key('public-hero-ornament')), findsNothing);
      expect(find.byKey(const Key('public-hero-image')), findsNothing);
    });

    testWidgets('content that fails to load keeps the built-in site', (tester) async {
      final repository = _ControlledRepository(WebsiteContentRepository(firestore: firestore))..fail = true;
      await pumpSite(tester, repository: repository);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('public-hero-ornament')), findsOneWidget);
      expect(find.text('A calm, thoughtful place to learn and grow'), findsOneWidget);
    });

    testWidgets('section pages: managed image and text, placeholder otherwise; Contact has none', (tester) async {
      await addMedia('adm', _media(inGallery: false, alt: 'Admissions alt'));
      await addLivePage(WebsitePageSlot.admissions, {
        'imageMediaId': 'adm',
        'headline': {'en': 'Joining 2D Montessori'},
        'intro': {'en': ''},
      });
      await pumpSite(tester, initialRoute: PublicRoutes.admissions);
      expect(find.byKey(const Key('public-section-image')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('public-section-title'))).data, 'Joining 2D Montessori');
      expect(tester.widget<Text>(find.byKey(const Key('public-section-intro'))).data, 'Information about admissions will be published here.');

      await tapAndSettle(tester, find.byKey(const Key('public-nav-/programs')));
      expect(find.byKey(const Key('public-section-image')), findsNothing);
      expect(find.byKey(const Key('public-section-placeholder')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('public-section-title'))).data, 'Programs');

      await tapAndSettle(tester, find.byKey(const Key('public-nav-/teacher-training')));
      expect(find.byKey(const Key('public-section-placeholder')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(const Key('public-nav-/contact')));
      expect(find.byKey(const Key('public-section-placeholder')), findsNothing);
      expect(find.byKey(const Key('public-section-image')), findsNothing);
    });

    testWidgets('gallery banner and intro come from the gallery page content', (tester) async {
      await addMedia('banner', _media(inGallery: false));
      await addMedia('g', _media());
      await addLivePage(WebsitePageSlot.gallery, {'imageMediaId': 'banner', 'headline': {'en': ''}, 'intro': {'en': 'Our year in pictures'}});
      await pumpSite(tester, initialRoute: PublicRoutes.gallery);
      expect(find.byKey(const Key('public-gallery-banner')), findsOneWidget);
      expect(find.text('Our year in pictures'), findsOneWidget);
      expect(item('banner'), findsNothing, reason: 'page-only image is not in the grid');
      expect(item('g'), findsOneWidget);
    });

    test('drafts are never read by the public repository', () async {
      await firestore.collection(WebsiteCollections.pageDrafts).doc('home').set({'headline': {'en': 'Secret draft'}});
      final pages = await WebsiteContentRepository(firestore: firestore).livePages();
      expect(pages, isEmpty);
    });

    test('the image URL matches the space it is drawn in', () {
      final media = WebsiteMedia.fromMap('x', _media());
      expect(media.urlForWidth(400), 'https://example.test/thumb.jpg');
      expect(media.urlForWidth(1200), 'https://example.test/display.jpg');
      expect(WebsiteMedia.fromMap('y', {..._media(), 'thumbUrl': ''}).urlForWidth(200), 'https://example.test/display.jpg');
      expect(WebsiteMedia.fromMap('z', {..._media(), 'focalX': 1.0, 'focalY': 0.0}).alignment, const Alignment(1, -1));
    });
  });
}
