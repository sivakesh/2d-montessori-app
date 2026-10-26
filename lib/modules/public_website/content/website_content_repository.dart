import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../public_strings.dart';
import 'blocks/block_registry.dart';
import 'blocks/website_block.dart';
import 'built_in_pages.dart';
import 'website_content_models.dart';
import 'website_custom_page.dart';
import 'website_languages.dart';
import 'website_site_layout.dart';

/// Everything published in the live pages collection: the built-in pages'
/// managed content, the additional pages, the site layout and the
/// language registry.
class LiveWebsiteContent {
  const LiveWebsiteContent({this.pages = const {}, this.customPages = const [], this.layout, this.languages, this.builtInBlocks = const {}});

  final Map<WebsitePageSlot, WebsitePageContent> pages;

  /// The built-in pages published as blocks, by [BuiltInPage.id]. A page
  /// not listed shows its built-in content, as before.
  final Map<String, List<WebsiteBlock>> builtInBlocks;

  /// Published additional pages, in navigation order.
  final List<CustomPage> customPages;

  /// The published header/footer layout; null when none is published or it
  /// can't be read (the site then uses its built-in layout).
  final SiteLayout? layout;

  /// The published language registry; null when none is published or it
  /// can't be used (visitors then get English and Tamil).
  final SiteLanguageRegistry? languages;
}

/// Read-only access to the website's *published* content, as visitors see
/// it. Two queries serve the whole public site: published media (the
/// gallery and every page image) and the live page documents (built-in
/// pages' content and additional pages). Drafts are never read here.
class WebsiteContentRepository {
  WebsiteContentRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  // Resolved lazily so building the public site never needs Firebase until
  // content is actually requested (and a missing Firebase app just becomes
  // a failed load, which the pages treat as "no managed content").
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  /// Every published image, in gallery order. The query is constrained to
  /// `status == 'published'` (a single-field filter, so no composite index
  /// is needed); records missing an image URL, or without confirmed consent
  /// (which publishing requires, so this only guards against an
  /// inconsistent record), are skipped. Every public image — gallery, page
  /// banners, sections — is resolved from this list, so an image left out
  /// here is shown nowhere and pages fall back to their placeholder.
  Future<List<WebsiteMedia>> publishedMedia() async {
    final snapshot = await _db
        .collection(WebsiteCollections.media)
        .where('status', isEqualTo: WebsiteMediaStatus.published.name)
        .get();
    final media = [
      for (final doc in snapshot.docs) WebsiteMedia.fromMap(doc.id, doc.data()),
    ].where((m) => m.isPublished && m.consentConfirmed && m.url.isNotEmpty).toList();
    return sortForGallery(media);
  }

  /// Every live page document, split into built-in page content,
  /// additional pages (only well-formed, non-archived ones) and the site
  /// layout (only a well-formed one).
  Future<LiveWebsiteContent> liveContent() async {
    final snapshot = await _db.collection(WebsiteCollections.livePages).get();
    final pages = <WebsitePageSlot, WebsitePageContent>{};
    final custom = <CustomPage>[];
    SiteLayout? layout;
    SiteLanguageRegistry? languages;
    final builtInBlocks = <String, List<WebsiteBlock>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (BuiltInPage.parse(doc.id) != null) {
        if (builtInPageBlocks(data) case final blocks?) builtInBlocks[doc.id] = blocks;
      }
      if (doc.id == SiteLayout.docId) {
        layout = SiteLayout.tryParse(data);
        continue;
      }
      if (doc.id == SiteLanguageRegistry.docId) {
        languages = SiteLanguageRegistry.tryParse(data);
        continue;
      }
      if (CustomPage.isCustomDoc(data)) {
        final page = CustomPage.fromMap(doc.id, data);
        if (!page.archived && CustomPage.validateSlugFormat(page.slug) == null && page.title.en.trim().isNotEmpty) custom.add(page);
        continue;
      }
      final slot = WebsitePageSlot.parse(doc.id);
      if (slot != null) pages[slot] = WebsitePageContent.fromMap(slot, data);
    }
    custom.sort((a, b) => a.navOrder != b.navOrder ? a.navOrder.compareTo(b.navOrder) : a.slug.compareTo(b.slug));
    return LiveWebsiteContent(pages: pages, customPages: custom, layout: layout, languages: languages, builtInBlocks: builtInBlocks);
  }

  /// The published content of every built-in page that has some.
  Future<Map<WebsitePageSlot, WebsitePageContent>> livePages() async => (await liveContent()).pages;

  /// Published additional pages, in navigation order.
  Future<List<CustomPage>> liveCustomPages() async => (await liveContent()).customPages;
}

/// The blocks a built-in page's document holds (`schemaVersion: 2` and a
/// `blocks` list), or null when it is still the built-in page.
List<WebsiteBlock>? builtInPageBlocks(Map<String, dynamic>? data) =>
    data != null && data['schemaVersion'] == 2 && data['blocks'] is List ? BlockRegistry.parseList(data['blocks']) : null;

/// Gallery order, then most recently updated first for ties.
List<WebsiteMedia> sortForGallery(Iterable<WebsiteMedia> media) {
  final list = media.toList();
  list.sort((a, b) {
    final byOrder = a.galleryOrder.compareTo(b.galleryOrder);
    if (byOrder != 0) return byOrder;
    final aTime = a.updatedAt?.millisecondsSinceEpoch ?? 0;
    final bTime = b.updatedAt?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  });
  return list;
}

final websiteContentRepositoryProvider = Provider<WebsiteContentRepository>((ref) => WebsiteContentRepository());

/// Published media, loaded once per session (and again after an admin
/// publishes a change, which invalidates it). Content changes reach new
/// visitors on their next page load, with no rebuild of the website.
final publishedWebsiteMediaProvider = FutureProvider<List<WebsiteMedia>>(
  (ref) => ref.watch(websiteContentRepositoryProvider).publishedMedia(),
);

/// All live page documents, loaded once per session (and again after an
/// admin publishes, which invalidates it).
final liveWebsiteContentProvider = FutureProvider<LiveWebsiteContent>(
  (ref) => ref.watch(websiteContentRepositoryProvider).liveContent(),
);

final liveWebsitePagesProvider = FutureProvider<Map<WebsitePageSlot, WebsitePageContent>>(
  (ref) async => (await ref.watch(liveWebsiteContentProvider.future)).pages,
);

/// The published additional page at [slug]: null when there is none (never
/// published, unpublished, archived, or a malformed slug), so visitors get
/// "page not found" and drafts are never shown.
final publicCustomPageProvider = FutureProvider.family<CustomPage?, String>((ref, slug) async {
  if (CustomPage.validateSlugFormat(slug) != null) return null;
  final content = await ref.watch(liveWebsiteContentProvider.future);
  for (final page in content.customPages) {
    if (page.slug == slug) return page;
  }
  return null;
});

/// The published blocks of built-in page [id] ([BuiltInPage.id]): null
/// while loading, if loading fails, or when the page isn't published as
/// blocks (it then shows its built-in content, as before).
final publicBuiltInBlocksProvider = Provider.family<List<WebsiteBlock>?, String>(
  (ref, id) => ref.watch(liveWebsiteContentProvider).valueOrNull?.builtInBlocks[id],
);

/// The public header, mobile menu and footer: the published site layout,
/// or — while content loads, if loading fails, or with no usable layout
/// published — the built-in layout (the built-in pages, then the published
/// additional pages listed in the navigation, Contact last).
final publicSiteChromeProvider = Provider<PublicSiteChrome>((ref) {
  final content = ref.watch(liveWebsiteContentProvider).valueOrNull;
  return PublicSiteChrome.resolve(content?.layout, content?.customPages ?? const <CustomPage>[]);
});

/// The languages of the public language switch, in order: the published
/// registry's enabled and public languages, or — while content loads, if
/// loading fails, or with no usable registry published — English and
/// Tamil, as before.
final publicLanguagesProvider = Provider<List<PublicLanguage>>((ref) {
  final list = ref.watch(liveWebsiteContentProvider).valueOrNull?.languages?.publicLanguages;
  return list == null || list.isEmpty ? PublicLanguage.builtIn : list;
});

/// The header and mobile menu links.
final publicNavigationProvider = Provider<List<PublicNavEntry>>((ref) => ref.watch(publicSiteChromeProvider).mainNav);

/// Published gallery images (published and listed in the gallery).
final publicGalleryProvider = FutureProvider<List<WebsiteMedia>>((ref) async {
  final media = await ref.watch(publishedWebsiteMediaProvider.future);
  return media.where((m) => m.inGallery).toList();
});

/// What a page shows from managed content: its published text (if any)
/// and its image when that image is itself published.
class PublicPageContent {
  const PublicPageContent({this.page, this.image, this.isLoading = false});

  final WebsitePageContent? page;
  final WebsiteMedia? image;

  /// Content is still being fetched (pages show their placeholder).
  final bool isLoading;
}

/// Managed content for [WebsitePageSlot], never an error: while loading,
/// or if loading fails, pages fall back to their built-in text and
/// placeholder imagery. An image that is no longer published (hidden or
/// deleted) also falls back, even if a live page still refers to it.
final publicPageContentProvider = Provider.family<PublicPageContent, WebsitePageSlot>((ref, slot) {
  final pages = ref.watch(liveWebsitePagesProvider);
  final page = pages.valueOrNull?[slot];
  final imageId = page?.imageMediaId;
  if (imageId == null) return PublicPageContent(page: page, isLoading: pages.isLoading);
  final media = ref.watch(publishedWebsiteMediaProvider);
  WebsiteMedia? image;
  for (final m in media.valueOrNull ?? const <WebsiteMedia>[]) {
    if (m.id == imageId) image = m;
  }
  return PublicPageContent(page: page, image: image, isLoading: media.isLoading);
});
