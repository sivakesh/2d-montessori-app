import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../content/website_content_models.dart';
import '../content/website_content_repository.dart';
import '../content/website_custom_page.dart';
import '../public_routes.dart';
import '../public_strings.dart';
import '../public_website_theme.dart';
import '../widgets/public_scaffold.dart';
import '../widgets/blocks/website_blocks_view.dart';
import '../widgets/public_website_image.dart';
import 'public_gallery_page.dart';

/// An additional public page at `/pages/<slug>`, open without signing in.
/// Shows only the published copy: an unknown, unpublished or archived slug
/// gets "page not found" (drafts are never fetched by the public site).
class PublicCustomPage extends ConsumerWidget {
  const PublicCustomPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final page = ref.watch(publicCustomPageProvider(slug));
    final media = ref.watch(publishedWebsiteMediaProvider).valueOrNull ?? const <WebsiteMedia>[];

    Widget message({required Key key, required IconData icon, required String title, required String body, Widget? action}) => PublicContentWidth(
          maxWidth: 760,
          child: Column(
            key: key,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 36, color: PublicColors.gold),
              const SizedBox(height: 16),
              Text(title, style: layout.isMobile ? PublicText.displayMobile : PublicText.display),
              const SizedBox(height: 12),
              Text(body, style: PublicText.body.copyWith(fontSize: 17)),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ?action,
                  TextButton.icon(
                    key: const Key('public-back-home'),
                    onPressed: () => PublicRoutes.open(context, PublicRoutes.home),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text(strings.backHome),
                    style: TextButton.styleFrom(foregroundColor: PublicColors.forest),
                  ),
                ],
              ),
            ],
          ),
        );

    return PublicScaffold(
      currentRoute: PublicRoutes.customPage(slug),
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 48 : 88),
        child: page.when(
          skipLoadingOnRefresh: false,
          loading: () => Semantics(
            key: const Key('public-page-loading'),
            label: strings.pageLoading,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 64),
              child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: PublicColors.sage))),
            ),
          ),
          error: (_, _) => message(
            key: const Key('public-page-error'),
            icon: Icons.cloud_off_outlined,
            title: strings.pageLoadErrorTitle,
            body: strings.pageLoadErrorBody,
            action: OutlinedButton.icon(
              key: const Key('public-page-retry'),
              onPressed: () => ref.invalidate(liveWebsiteContentProvider),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(strings.galleryRetry),
              style: OutlinedButton.styleFrom(foregroundColor: PublicColors.forest, side: const BorderSide(color: PublicColors.line)),
            ),
          ),
          data: (page) => page == null
              ? message(key: const Key('public-page-not-found'), icon: Icons.search_off_rounded, title: strings.pageNotFoundTitle, body: strings.pageNotFoundBody)
              : PublicCustomPageBody(page: page, media: {for (final m in media) m.id: m}, language: language),
        ),
      ),
    );
  }
}

/// The content of an additional page: title, introduction, optional banner
/// and its sections. Used by the public page (with published media only)
/// and by the admin preview (with the whole library, [interactive] false so
/// buttons and the lightbox don't navigate away). Images missing from
/// [media] are left out.
class PublicCustomPageBody extends StatelessWidget {
  const PublicCustomPageBody({super.key, required this.page, required this.media, required this.language, this.interactive = true});

  final CustomPage page;
  final Map<String, WebsiteMedia> media;
  final PublicLanguage language;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final hero = page.heroMediaId == null ? null : media[page.heroMediaId];
    final intro = page.intro.resolve(language);
    final header = PublicContentWidth(
      maxWidth: 960,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(page.title.resolve(language), key: const Key('public-page-title'), style: layout.isMobile ? PublicText.displayMobile : PublicText.display),
          if (intro.isNotEmpty) ...[
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(intro, key: const Key('public-page-intro'), style: PublicText.body.copyWith(fontSize: 17)),
            ),
          ],
          if (hero != null) ...[
            const SizedBox(height: 32),
            PublicWebsiteImage(
              key: const Key('public-page-hero'),
              media: hero,
              aspectRatio: 16 / 9,
              semanticLabel: hero.alt.resolve(language),
              errorLabel: strings.imageUnavailable,
            ),
          ],
          // A page made of sections shows them, exactly as before.
          if (!page.usesBlocks)
            for (final section in page.sections) ...[
              SizedBox(height: layout.isMobile ? 40 : 56),
              KeyedSubtree(
                key: Key('public-page-section-${section.id}'),
                child: _section(context, section, strings, layout),
              ),
            ],
        ],
      ),
    );
    if (!page.usesBlocks) return header;
    // A page built with blocks: its blocks at the page's full width, so
    // sections can run edge to edge (other blocks keep the 960 px width).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        WebsiteBlocksView(key: const Key('public-page-blocks'), blocks: page.blocks!, media: media, language: language, interactive: interactive, fullBleed: true),
      ],
    );
  }

  Widget _paragraphs(String text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, paragraph) in text.split(RegExp(r'\n\s*\n')).indexed)
            if (paragraph.trim().isNotEmpty)
              Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 14), child: Text(paragraph.trim(), style: PublicText.body)),
        ],
      );

  Widget _textBlock(String heading, String body) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading.isNotEmpty) ...[Text(heading, style: PublicText.heading), const SizedBox(height: 12)],
          if (body.isNotEmpty) _paragraphs(body),
        ],
      );

  Widget _section(BuildContext context, CustomPageSection section, PublicStrings strings, PublicLayout layout) {
    final heading = section.heading.resolve(language);
    final body = section.body.resolve(language);
    switch (section.type) {
      case CustomSectionType.text:
        return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: _textBlock(heading, body));
      case CustomSectionType.imageText:
        final image = section.mediaId == null ? null : media[section.mediaId];
        final text = _textBlock(heading, body);
        if (image == null) return text;
        final picture = PublicWebsiteImage(media: image, aspectRatio: 4 / 3, semanticLabel: image.alt.resolve(language), errorLabel: strings.imageUnavailable);
        if (layout.isMobile) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [picture, const SizedBox(height: 20), text]);
        final children = [Expanded(child: picture), const SizedBox(width: 40), Expanded(child: text)];
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: section.imageOnRight ? children.reversed.toList() : children);
      case CustomSectionType.imageGrid:
        final images = [for (final id in section.mediaIds) ?media[id]];
        if (images.isEmpty && heading.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (heading.isNotEmpty) ...[Text(heading, style: PublicText.heading), const SizedBox(height: 20)],
            LayoutBuilder(builder: (context, constraints) {
              final columns = layout.isMobile ? 2 : 3;
              final gap = layout.isMobile ? 12.0 : 20.0;
              final width = ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < images.length; i++)
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            button: interactive,
                            label: images[i].alt.resolve(language),
                            excludeSemantics: true,
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: interactive ? () => showPublicGalleryLightbox(context, images, i) : null,
                                child: PublicWebsiteImage(
                                  media: images[i],
                                  aspectRatio: 4 / 3,
                                  borderRadius: 16,
                                  semanticLabel: images[i].alt.resolve(language),
                                  errorLabel: strings.imageUnavailable,
                                  placeholder: const PublicImagePlaceholder(compact: true),
                                ),
                              ),
                            ),
                          ),
                          if (images[i].caption.resolve(language) case final caption when caption.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(caption, maxLines: 2, overflow: TextOverflow.ellipsis, style: PublicText.body.copyWith(fontSize: 14, color: PublicColors.ink)),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            }),
          ],
        );
      case CustomSectionType.callToAction:
        final label = section.buttonLabel.resolve(language);
        // Re-checked here too: a link is only followed if it is safe.
        final target = section.target.trim();
        final safe = SafeLinkTarget.validate(target) == null;
        return Container(
          padding: EdgeInsets.all(layout.isMobile ? 24 : 36),
          decoration: BoxDecoration(color: PublicColors.sageLight, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _textBlock(heading, body),
              if (label.isNotEmpty && safe) ...[
                const SizedBox(height: 20),
                FilledButton(
                  key: Key('public-page-cta-${section.id}'),
                  onPressed: interactive ? () => _follow(context, target) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: PublicColors.forest,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(label),
                ),
              ],
            ],
          ),
        );
    }
  }

  Future<void> _follow(BuildContext context, String target) async {
    if (SafeLinkTarget.validate(target) != null) return;
    if (SafeLinkTarget.isInternal(target)) {
      PublicRoutes.open(context, target);
      return;
    }
    await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
  }
}
