import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../content/built_in_pages.dart';
import '../content/website_content_models.dart';
import '../content/website_content_repository.dart';
import '../public_routes.dart';
import '../public_strings.dart';
import '../public_website_theme.dart';
import '../widgets/public_scaffold.dart';
import '../widgets/public_website_image.dart';
import 'public_built_in_blocks_page.dart';

/// The public Gallery at `/gallery`: the school's published photographs in
/// a responsive grid (2 columns on mobile, 3 on tablet, 4 on desktop),
/// optional category filters, captions, and a lightbox for a larger view.
/// Only published images are ever listed. Grid tiles load the small
/// thumbnail; the larger image loads only when opened, and the grid shows
/// [pageSize] photographs at a time.
class PublicGalleryPage extends ConsumerWidget {
  const PublicGalleryPage({super.key});

  static const pageSize = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Published as blocks (Settings → Website → Pages → Visual editor).
    if (ref.watch(publicBuiltInBlocksProvider(BuiltInPage.gallery.id)) case final blocks?) return PublicBuiltInBlocksPage(page: BuiltInPage.gallery, blocks: blocks);
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final content = ref.watch(publicPageContentProvider(WebsitePageSlot.gallery));
    final headline = content.page?.headline.resolve(language) ?? '';
    final intro = content.page?.intro.resolve(language) ?? '';
    final banner = content.image;

    return PublicScaffold(
      currentRoute: PublicRoutes.gallery,
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 48 : 88),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PublicContentWidth(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(headline.isNotEmpty ? headline : strings.gallery, key: const Key('public-section-title'), style: layout.isMobile ? PublicText.displayMobile : PublicText.display),
                  const SizedBox(height: 16),
                  Text(intro.isNotEmpty ? intro : strings.galleryIntro, key: const Key('public-section-intro'), style: PublicText.body.copyWith(fontSize: 17)),
                  if (banner != null) ...[
                    const SizedBox(height: 32),
                    PublicWebsiteImage(key: const Key('public-gallery-banner'), media: banner, aspectRatio: 16 / 9, semanticLabel: banner.alt.resolve(language), errorLabel: strings.imageUnavailable),
                  ],
                ],
              ),
            ),
            SizedBox(height: layout.isMobile ? 32 : 48),
            const PublicContentWidth(child: PublicGalleryFeed()),
          ],
        ),
      ),
    );
  }
}

/// The published gallery photographs: category filters, the grid (2, 3 or
/// 4 per row), "show more" and the lightbox, with loading, empty and error
/// states. The Gallery page shows it, and so does the School gallery block.
class PublicGalleryFeed extends ConsumerStatefulWidget {
  const PublicGalleryFeed({super.key});

  @override
  ConsumerState<PublicGalleryFeed> createState() => _PublicGalleryFeedState();
}

class _PublicGalleryFeedState extends ConsumerState<PublicGalleryFeed> {
  GalleryCategory? _filter;
  int _visible = PublicGalleryPage.pageSize;

  void _select(GalleryCategory? category) => setState(() {
    _filter = category;
    _visible = PublicGalleryPage.pageSize;
  });

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final gallery = ref.watch(publicGalleryProvider);
    return gallery.when(
      skipLoadingOnRefresh: false,
      loading: () => _GalleryLoading(label: strings.galleryLoading),
      error: (_, _) => _GalleryMessage(
        key: const Key('public-gallery-error'),
        icon: Icons.cloud_off_outlined,
        title: strings.galleryErrorTitle,
        body: strings.galleryErrorBody,
        action: OutlinedButton.icon(
          key: const Key('public-gallery-retry'),
          onPressed: () => ref.invalidate(publishedWebsiteMediaProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(strings.galleryRetry),
          style: OutlinedButton.styleFrom(
            foregroundColor: PublicColors.forest,
            side: const BorderSide(color: PublicColors.line),
          ),
        ),
      ),
      data: (items) => items.isEmpty
          ? _GalleryMessage(key: const Key('public-gallery-empty'), icon: Icons.photo_library_outlined, title: strings.galleryEmptyTitle, body: strings.galleryEmptyBody)
          : _galleryBody(context, items, strings, language, layout),
    );
  }

  Widget _galleryBody(BuildContext context, List<WebsiteMedia> items, PublicStrings strings, PublicLanguage language, PublicLayout layout) {
    final categories = [
      for (final category in GalleryCategory.values)
        if (items.any((m) => m.category == category)) category,
    ];
    final filter = categories.contains(_filter) ? _filter : null;
    final filtered = filter == null ? items : items.where((m) => m.category == filter).toList();
    final shown = filtered.take(_visible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (categories.length > 1) ...[
          Semantics(
            label: strings.galleryFilterLabel,
            container: true,
            child: Wrap(
              key: const Key('public-gallery-filters'),
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(key: const Key('public-gallery-filter-all'), label: strings.galleryAll, selected: filter == null, onTap: () => _select(null)),
                for (final category in categories)
                  _FilterChip(key: Key('public-gallery-filter-${category.id}'), label: category.label(language), selected: filter == category, onTap: () => _select(category)),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
        if (shown.isEmpty)
          _GalleryMessage(icon: Icons.photo_outlined, title: strings.galleryCategoryEmpty, body: '')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = switch (layout) {
                PublicLayout.mobile => 2,
                PublicLayout.tablet => 3,
                PublicLayout.desktop => 4,
              };
              final gap = layout.isMobile ? 12.0 : 20.0;
              final tileWidth = ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
              return Wrap(
                key: const Key('public-gallery-grid'),
                spacing: gap,
                runSpacing: layout.isMobile ? 20 : 28,
                children: [
                  for (var i = 0; i < shown.length; i++)
                    SizedBox(
                      width: tileWidth,
                      child: _GalleryTile(media: shown[i], language: language, strings: strings, onOpen: () => showPublicGalleryLightbox(context, filtered, i)),
                    ),
                ],
              );
            },
          ),
        if (filtered.length > shown.length) ...[
          const SizedBox(height: 32),
          Center(
            child: OutlinedButton(
              key: const Key('public-gallery-show-more'),
              onPressed: () => setState(() => _visible += PublicGalleryPage.pageSize),
              style: OutlinedButton.styleFrom(
                foregroundColor: PublicColors.forest,
                side: const BorderSide(color: PublicColors.line),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
              child: Text(strings.galleryShowMore),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? PublicColors.forest : PublicColors.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? PublicColors.forest : PublicColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Colors.white : PublicColors.forest),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({required this.media, required this.language, required this.strings, required this.onOpen});

  final WebsiteMedia media;
  final PublicLanguage language;
  final PublicStrings strings;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final caption = media.caption.resolve(language);
    final alt = media.alt.resolve(language);
    return Column(
      key: Key('public-gallery-item-${media.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: alt.isNotEmpty ? alt : strings.galleryOpenImage,
          hint: strings.galleryOpenImage,
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onOpen,
              child: PublicWebsiteImage(
                media: media,
                aspectRatio: 4 / 3,
                borderRadius: 16,
                semanticLabel: alt,
                errorLabel: strings.imageUnavailable,
                placeholder: const PublicImagePlaceholder(compact: true),
              ),
            ),
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: PublicText.body.copyWith(fontSize: 14, height: 1.45, color: PublicColors.ink),
          ),
        ],
      ],
    );
  }
}

class _GalleryLoading extends StatelessWidget {
  const _GalleryLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('public-gallery-loading'),
      label: label,
      liveRegion: true,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: PublicColors.sage)),
        ),
      ),
    );
  }
}

class _GalleryMessage extends StatelessWidget {
  const _GalleryMessage({super.key, required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(color: PublicColors.goldLight.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(icon, size: 32, color: PublicColors.gold),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: PublicText.title),
          if (body.isNotEmpty) ...[const SizedBox(height: 6), Text(body, textAlign: TextAlign.center, style: PublicText.body)],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

/// Opens the lightbox over the gallery at [index] of [items].
Future<void> showPublicGalleryLightbox(BuildContext context, List<WebsiteMedia> items, int index) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0xF0101A15),
    useSafeArea: false,
    builder: (_) => PublicGalleryLightbox(items: items, initialIndex: index),
  );
}

/// Full-screen view of one photograph at a time (the display-size image,
/// whole and uncropped) with its caption; previous/next buttons, swiping
/// and the arrow keys move through [items]; Close or Escape returns.
class PublicGalleryLightbox extends ConsumerStatefulWidget {
  const PublicGalleryLightbox({super.key, required this.items, required this.initialIndex});

  final List<WebsiteMedia> items;
  final int initialIndex;

  @override
  ConsumerState<PublicGalleryLightbox> createState() => _PublicGalleryLightboxState();
}

class _PublicGalleryLightboxState extends ConsumerState<PublicGalleryLightbox> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.items.length) return;
    _controller.animateToPage(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final isMobile = PublicLayout.of(MediaQuery.sizeOf(context).width).isMobile;
    final media = widget.items[_index];
    final caption = media.caption.resolve(language);

    Widget arrow(IconData icon, String tooltip, int delta, Key key) => IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: () => _go(delta),
      iconSize: 28,
      color: Colors.white,
      style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.12)),
      icon: Icon(icon),
    );

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1), const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1)},
      child: Focus(
        autofocus: true,
        child: Material(
          key: const Key('public-gallery-lightbox'),
          type: MaterialType.transparency,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.galleryPosition(_index + 1, widget.items.length),
                          key: const Key('public-gallery-lightbox-position'),
                          style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        key: const Key('public-gallery-lightbox-close'),
                        tooltip: strings.galleryClose,
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      if (!isMobile) SizedBox(width: 72, child: _index > 0 ? arrow(Icons.chevron_left_rounded, strings.galleryPrevious, -1, const Key('public-gallery-lightbox-previous')) : null),
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: widget.items.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (context, i) {
                            final item = widget.items[i];
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 8, vertical: 12),
                              child: Center(
                                child: PublicWebsiteImage(
                                  media: item,
                                  aspectRatio: item.aspectRatio,
                                  fit: BoxFit.contain,
                                  borderRadius: 8,
                                  semanticLabel: item.alt.resolve(language),
                                  errorLabel: strings.imageUnavailable,
                                  placeholder: const ColoredBox(color: Color(0x14FFFFFF)),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (!isMobile)
                        SizedBox(width: 72, child: _index < widget.items.length - 1 ? arrow(Icons.chevron_right_rounded, strings.galleryNext, 1, const Key('public-gallery-lightbox-next')) : null),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760, minHeight: 24),
                    child: Text(
                      caption,
                      key: const Key('public-gallery-lightbox-caption'),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.5),
                    ),
                  ),
                ),
                if (isMobile)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Opacity(opacity: _index > 0 ? 1 : 0.3, child: arrow(Icons.chevron_left_rounded, strings.galleryPrevious, -1, const Key('public-gallery-lightbox-previous'))),
                        const SizedBox(width: 24),
                        Opacity(opacity: _index < widget.items.length - 1 ? 1 : 0.3, child: arrow(Icons.chevron_right_rounded, strings.galleryNext, 1, const Key('public-gallery-lightbox-next'))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
