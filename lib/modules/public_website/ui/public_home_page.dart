import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../content/built_in_pages.dart';
import '../content/website_content_models.dart';
import '../content/website_content_repository.dart';
import '../public_routes.dart';
import '../public_strings.dart';
import '../content/website_design.dart';
import '../public_website_theme.dart';
import '../widgets/blocks/public_feature_widgets.dart';
import '../widgets/public_scaffold.dart';
import 'public_built_in_blocks_page.dart';
import '../widgets/public_website_image.dart';

/// The public homepage at `/`: welcome, the two audience pathways
/// (Families -> Admissions, Educators -> Teacher Training) and a short note
/// on the Montessori approach. The hero's image and text come from the
/// published homepage content when there is some; otherwise it shows the
/// built-in wording and decorative shapes (never a stand-in photograph).
class PublicHomePage extends ConsumerWidget {
  const PublicHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Published as blocks (Settings → Website → Pages → Visual editor).
    if (ref.watch(publicBuiltInBlocksProvider(BuiltInPage.home.id)) case final blocks?) return PublicBuiltInBlocksPage(page: BuiltInPage.home, blocks: blocks);
    final language = ref.watch(publicLanguageProvider);
    final strings = PublicStrings.of(language);
    final content = ref.watch(publicPageContentProvider(WebsitePageSlot.home));
    return PublicScaffold(
      currentRoute: PublicRoutes.home,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(strings: strings, language: language, content: content),
          _Pathways(strings: strings),
          _Approach(strings: strings),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.strings, required this.language, required this.content});

  final PublicStrings strings;
  final PublicLanguage language;
  final PublicPageContent content;

  @override
  Widget build(BuildContext context) {
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final page = content.page;
    final headline = page?.headline.resolve(language) ?? '';
    final intro = page?.intro.resolve(language) ?? '';
    final image = content.image;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.heroEyebrow, style: PublicText.eyebrow),
        const SizedBox(height: 16),
        Text(headline.isNotEmpty ? headline : strings.heroTitle, key: const Key('public-hero-title'), style: WebsiteDesignScope.of(context).titleStyle(mobile: layout.isMobile)),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(intro.isNotEmpty ? intro : strings.heroBody, key: const Key('public-hero-body'), style: PublicText.body.copyWith(fontSize: 17)),
        ),
      ],
    );
    // A published photograph replaces the decorative shapes (same square
    // frame, so nothing shifts when it arrives); on mobile it sits below the
    // text, and only when there is one.
    Widget visual(double aspectRatio) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: image == null
              ? const PublicHeroOrnament(key: Key('public-hero-ornament'))
              : PublicWebsiteImage(
                  key: const Key('public-hero-image'),
                  media: image,
                  aspectRatio: aspectRatio,
                  borderRadius: 32,
                  semanticLabel: image.alt.resolve(language),
                  errorLabel: strings.imageUnavailable,
                  placeholder: const PublicImagePlaceholder(),
                ),
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 48 : 88),
      child: PublicContentWidth(
        child: layout.isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  text,
                  if (image != null) ...[const SizedBox(height: 32), visual(4 / 3)],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 3, child: text),
                  const SizedBox(width: 48),
                  Expanded(flex: 2, child: visual(1)),
                ],
              ),
      ),
    );
  }
}

class _Pathways extends StatelessWidget {
  const _Pathways({required this.strings});

  final PublicStrings strings;

  @override
  Widget build(BuildContext context) {
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final cards = [
      PublicPathwayCard(
        key: const Key('public-pathway-families'),
        icon: Icons.family_restroom_outlined,
        title: strings.familiesTitle,
        body: strings.familiesBody,
        cta: strings.familiesCta,
        route: PublicRoutes.admissions,
        accent: PublicColors.forest,
      ),
      PublicPathwayCard(
        key: const Key('public-pathway-educators'),
        icon: Icons.school_outlined,
        title: strings.educatorsTitle,
        body: strings.educatorsBody,
        cta: strings.educatorsCta,
        route: PublicRoutes.teacherTraining,
        accent: PublicColors.gold,
      ),
    ];
    return Container(
      color: PublicColors.surface,
      padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 48 : 72),
      child: PublicContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.pathwaysTitle, style: PublicText.heading),
            const SizedBox(height: 24),
            if (layout.isMobile)
              Column(children: [cards[0], const SizedBox(height: 16), cards[1]])
            else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Expanded(child: cards[0]), const SizedBox(width: 24), Expanded(child: cards[1])],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Approach extends StatelessWidget {
  const _Approach({required this.strings});

  final PublicStrings strings;

  @override
  Widget build(BuildContext context) {
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    final principles = [
      (Icons.spa_outlined, strings.principleChildTitle, strings.principleChildBody),
      (Icons.grid_view_outlined, strings.principleEnvironmentTitle, strings.principleEnvironmentBody),
      (Icons.volunteer_activism_outlined, strings.principleIndependenceTitle, strings.principleIndependenceBody),
    ];
    final items = [
      for (final (icon, title, body) in principles)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: PublicColors.sage, size: 28),
            const SizedBox(height: 12),
            Text(title, style: PublicText.title),
            const SizedBox(height: 6),
            Text(body, style: PublicText.body),
          ],
        ),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(vertical: layout.isMobile ? 48 : 80),
      child: PublicContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.approachEyebrow, style: PublicText.eyebrow),
            const SizedBox(height: 12),
            Text(strings.approachTitle, style: PublicText.heading),
            const SizedBox(height: 32),
            if (layout.isMobile)
              Column(children: [for (final item in items) Padding(padding: const EdgeInsets.only(bottom: 28), child: item)])
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(width: 32),
                    Expanded(child: items[i]),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
