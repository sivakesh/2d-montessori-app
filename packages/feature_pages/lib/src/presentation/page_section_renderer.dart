import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../domain/page_section.dart';
import '../domain/public_page_view.dart';

/// Renders one [PageSection] responsively, shared by both the admin
/// preview screen and `apps/public_web` — a single accessible
/// implementation instead of two renderers that could drift apart.
/// Every heading uses `Semantics(header: true)` so screen readers get a
/// real heading, and every image requires (non-empty, enforced upstream
/// by `PageCompletenessValidator`/server validation) alt text passed
/// straight through as the semantic label — "preserve heading hierarchy"
/// and "use image alternative text" are implemented here, in one place,
/// for every section type and both apps.
class PageSectionRenderer extends StatelessWidget {
  const PageSectionRenderer({
    super.key,
    required this.section,
    this.resolvedRelatedPages = const {},
  });

  final PageSection section;

  /// Only populated on the public site, where related-page references
  /// are resolved server-side at publish time (see [PublicPageView]'s
  /// doc comment). In the admin preview this is always empty — related
  /// pages there are shown by id only, with a note that resolution
  /// happens on publish.
  final Map<String, RelatedPageSummary> resolvedRelatedPages;

  @override
  Widget build(BuildContext context) {
    if (!section.isVisible) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SpacingTokens.lg,
        horizontal: SpacingTokens.md,
      ),
      child: switch (section) {
        final RichTextSection s => _richText(s),
        final ImageSection s => _image(s),
        final ImageTextSection s => _imageText(s),
        final CtaSection s => _cta(s),
        final HighlightsSection s => _highlights(s),
        final FaqSection s => _faq(s),
        final GallerySection s => _gallery(s),
        final TestimonialSection s => _testimonial(s),
        final RelatedContentSection s => _relatedContent(s),
      },
    );
  }

  Widget _heading(String text) => Semantics(
    header: true,
    child: Padding(
      padding: EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Text(text, style: TypographyTokens.headingMedium),
    ),
  );

  Widget _accessibleImage(String url, String altText, {double? height}) =>
      Semantics(
        image: true,
        label: altText,
        child: url.isEmpty
            ? Container(height: height ?? 200, color: ColorTokens.surfaceAlt)
            : Image.network(
                url,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: height ?? 200,
                  color: ColorTokens.surfaceAlt,
                ),
              ),
      );

  Widget _richText(RichTextSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (s.heading != null && s.heading!.isNotEmpty) _heading(s.heading!),
      Text(s.body, style: TypographyTokens.bodyMedium),
    ],
  );

  Widget _image(ImageSection s) =>
      _accessibleImage(s.image.url, s.image.altText);

  Widget _imageText(ImageTextSection s) {
    final image = Expanded(
      child: _accessibleImage(s.image.url, s.image.altText, height: 240),
    );
    final text = Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: SpacingTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.heading != null && s.heading!.isNotEmpty)
              _heading(s.heading!),
            Text(s.body, style: TypographyTokens.bodyMedium),
          ],
        ),
      ),
    );
    return Row(
      children: s.imageSide == ImageSide.left ? [image, text] : [text, image],
    );
  }

  Widget _cta(CtaSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (s.heading != null && s.heading!.isNotEmpty) _heading(s.heading!),
      if (s.body != null && s.body!.isNotEmpty)
        Text(s.body!, style: TypographyTokens.bodyMedium),
      SizedBox(height: SpacingTokens.sm),
      Wrap(
        spacing: SpacingTokens.sm,
        children: [
          FilledButton(onPressed: () {}, child: Text(s.primaryCta.label)),
          if (s.secondaryCta != null)
            OutlinedButton(
              onPressed: () {},
              child: Text(s.secondaryCta!.label),
            ),
        ],
      ),
    ],
  );

  Widget _highlights(HighlightsSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (s.heading != null && s.heading!.isNotEmpty) _heading(s.heading!),
      if (s.introduction != null && s.introduction!.isNotEmpty)
        Text(s.introduction!, style: TypographyTokens.bodyMedium),
      SizedBox(height: SpacingTokens.sm),
      Wrap(
        spacing: SpacingTokens.md,
        runSpacing: SpacingTokens.md,
        children: s.cards
            .map(
              (c) => SizedBox(
                width: 240,
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(SpacingTokens.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title, style: TypographyTokens.headingMedium),
                        Text(c.body, style: TypographyTokens.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ],
  );

  Widget _faq(FaqSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (s.heading != null && s.heading!.isNotEmpty) _heading(s.heading!),
      for (final item in s.items)
        ExpansionTile(
          title: Text(item.question),
          children: [
            Padding(
              padding: EdgeInsets.all(SpacingTokens.md),
              child: Text(item.answer),
            ),
          ],
        ),
    ],
  );

  Widget _gallery(GallerySection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (s.heading != null && s.heading!.isNotEmpty) _heading(s.heading!),
      Wrap(
        spacing: SpacingTokens.sm,
        runSpacing: SpacingTokens.sm,
        children: s.items
            .map(
              (m) => SizedBox(
                width: 160,
                height: 160,
                child: _accessibleImage(m.url, m.altText, height: 160),
              ),
            )
            .toList(),
      ),
    ],
  );

  Widget _testimonial(TestimonialSection s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (s.heading != null && s.heading!.isNotEmpty) _heading(s.heading!),
      for (final t in s.items)
        Padding(
          padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('"${t.quote}"', style: TypographyTokens.bodyLarge),
              Text(
                '— ${t.attributionName?.isNotEmpty == true ? t.attributionName : 'A 2D Montessori parent'}',
                style: TypographyTokens.label,
              ),
            ],
          ),
        ),
    ],
  );

  Widget _relatedContent(RelatedContentSection s) {
    final resolved = s.relatedPageIds
        .map((id) => resolvedRelatedPages[id])
        .whereType<RelatedPageSummary>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.heading != null && s.heading!.isNotEmpty) _heading(s.heading!),
        if (resolved.isEmpty && resolvedRelatedPages.isEmpty)
          Text(
            '${s.relatedPageIds.length} related page(s) selected — resolved once published.',
            style: TypographyTokens.label,
          ),
        Wrap(
          spacing: SpacingTokens.md,
          runSpacing: SpacingTokens.md,
          children: resolved
              .map(
                (r) => SizedBox(
                  width: 220,
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(SpacingTokens.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title, style: TypographyTokens.headingMedium),
                          Text(r.summary, style: TypographyTokens.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
