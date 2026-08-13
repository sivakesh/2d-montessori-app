import 'package:design_system/design_system.dart';
import 'package:feature_pages/feature_pages.dart';
import 'package:flutter/material.dart';

import 'not_found_screen.dart';
import 'seo_head.dart';

/// Resolves a public route's slug against [PublicPagesRepository] and
/// renders the result — the only code path that decides what an
/// unauthenticated visitor sees for a CMS-managed page. There is no
/// "preview" or "admin override" branch here: this repository can only
/// ever return a currently-published page or [ContentNotFoundFailure],
/// which is what makes "render only published and currently valid
/// content" true structurally, not just by convention.
class PageBySlugScreen extends StatefulWidget {
  const PageBySlugScreen({
    super.key,
    required this.slug,
    required this.repository,
  });

  final String slug;
  final PublicPagesRepository repository;

  @override
  State<PageBySlugScreen> createState() => _PageBySlugScreenState();
}

class _PageBySlugScreenState extends State<PageBySlugScreen> {
  PublicPageView? _page;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PageBySlugScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) _load();
  }

  Future<void> _load() async {
    setState(() {
      _page = null;
      _notFound = false;
    });
    final result = await widget.repository.getBySlug(widget.slug);
    if (!mounted) return;
    result.fold((page) {
      setState(() => _page = page);
      SeoHead.apply(
        title: page.seo.title?.isNotEmpty == true
            ? page.seo.title!
            : page.title,
        description: page.seo.metaDescription ?? page.summary,
        canonicalUrl: page.seo.canonicalUrl,
        indexable: page.seo.indexing == PageIndexingControl.indexFollow,
        ogTitle: page.seo.social.title,
        ogDescription: page.seo.social.description,
        ogImageUrl: page.seo.social.image?.url ?? page.featuredImage?.url,
      );
    }, (_) => setState(() => _notFound = true));
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) return const NotFoundScreen();
    final page = _page;
    if (page == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sections = [...page.sections]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(SpacingTokens.lg),
              child: Semantics(
                header: true,
                child: Text(page.title, style: TypographyTokens.displayLarge),
              ),
            ),
            for (final section in sections)
              PageSectionRenderer(
                section: section,
                resolvedRelatedPages: page.resolvedRelatedPages,
              ),
          ],
        ),
      ),
    );
  }
}
