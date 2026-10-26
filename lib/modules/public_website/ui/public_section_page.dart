import 'package:flutter/material.dart';
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

/// A public section page (Admissions, Teacher Training, Programs, Contact)
/// whose content isn't written yet: it keeps the site's navigation working
/// and says so plainly, rather than stating details that aren't confirmed.
/// Admissions, Teacher Training and Programs show their published banner
/// image (or a decorative placeholder) and any published heading/intro.
class PublicSectionPage extends ConsumerWidget {
  const PublicSectionPage({super.key, required this.route});

  final String route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Published as blocks (Settings → Website → Pages → Visual editor).
    if (BuiltInPage.forRoute(route) case final page?) {
      if (ref.watch(publicBuiltInBlocksProvider(page.id)) case final blocks?) return PublicBuiltInBlocksPage(page: page, blocks: blocks);
    }
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final slot = WebsitePageSlot.forRoute(route);
    final content = slot == null ? null : ref.watch(publicPageContentProvider(slot));
    final headline = content?.page?.headline.resolve(language) ?? '';
    final intro = content?.page?.intro.resolve(language) ?? '';
    final image = content?.image;
    return PublicScaffold(
      currentRoute: route,
      body: Padding(
        padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 48 : 96),
        child: PublicContentWidth(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(headline.isNotEmpty ? headline : strings.labelFor(route), key: const Key('public-section-title'), style: layout.isMobile ? PublicText.displayMobile : PublicText.display),
              const SizedBox(height: 16),
              Text(intro.isNotEmpty ? intro : strings.introFor(route), key: const Key('public-section-intro'), style: PublicText.body.copyWith(fontSize: 17)),
              if (slot != null) ...[
                const SizedBox(height: 32),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: PublicWebsiteImage(
                    key: Key(image == null ? 'public-section-placeholder' : 'public-section-image'),
                    media: image,
                    aspectRatio: 16 / 9,
                    semanticLabel: image?.alt.resolve(language) ?? '',
                    errorLabel: strings.imageUnavailable,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: PublicColors.goldLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.comingSoonTitle, style: PublicText.title),
                    const SizedBox(height: 6),
                    Text(strings.comingSoonBody, style: PublicText.body),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              TextButton.icon(
                key: const Key('public-back-home'),
                onPressed: () => PublicRoutes.open(context, PublicRoutes.home),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text(strings.backHome),
                style: TextButton.styleFrom(foregroundColor: PublicColors.forest),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
