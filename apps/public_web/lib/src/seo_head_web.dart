import 'package:web/web.dart' as web;

/// Updates the document `<head>` (title, meta description, canonical
/// link, robots directive, Open Graph tags) on every route change.
///
/// **Known limitation (SRS SEO-01/NFR-09), stated explicitly rather than
/// silently assumed complete:** Flutter Web is client-side rendered —
/// there is no server-rendered or pre-rendered HTML for public routes in
/// this milestone (the SRS's Technical Architecture section allows for
/// "server-rendered or pre-rendered public pages where required for
/// SEO", which this milestone does not build). This class updates the
/// live DOM after the page loads and Dart runs, which:
///
/// - **Works** for user agents that execute JavaScript before reading
///   `<head>` — this includes modern Googlebot, which renders pages
///   before indexing them, so search indexing of per-page title/
///   description/canonical/robots is expected to work.
/// - **Does not work** for user agents that only read the static HTML
///   returned by the first request and never execute JavaScript — this
///   includes most social-preview/link-unfurling crawlers (Facebook,
///   Twitter/X, WhatsApp, LinkedIn, Slack). Those will only ever see
///   whatever is hard-coded in `web/index.html`'s `<head>` (the site-
///   wide defaults), never a specific page's Open Graph title/
///   description/image, until a prerendering or server-side-rendering
///   solution is added — a real gap, tracked as a follow-up in
///   decisions.md, not fixed in this milestone.
abstract final class SeoHead {
  static void apply({
    required String title,
    String? description,
    String? canonicalUrl,
    required bool indexable,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) {
    web.document.title = title;
    _setMeta('description', description);
    _setMeta('robots', indexable ? 'index,follow' : 'noindex,nofollow');
    _setMeta('og:title', ogTitle ?? title, isProperty: true);
    _setMeta('og:description', ogDescription ?? description, isProperty: true);
    if (ogImageUrl != null) _setMeta('og:image', ogImageUrl, isProperty: true);
    _setCanonical(canonicalUrl);
  }

  static void _setMeta(
    String name,
    String? content, {
    bool isProperty = false,
  }) {
    if (content == null || content.isEmpty) return;
    final attribute = isProperty ? 'property' : 'name';
    final selector = 'meta[$attribute="$name"]';
    var element = web.document.querySelector(selector) as web.HTMLMetaElement?;
    if (element == null) {
      element = web.document.createElement('meta') as web.HTMLMetaElement;
      element.setAttribute(attribute, name);
      web.document.head?.append(element);
    }
    element.content = content;
  }

  static void _setCanonical(String? url) {
    if (url == null || url.isEmpty) return;
    var link =
        web.document.querySelector('link[rel="canonical"]')
            as web.HTMLLinkElement?;
    if (link == null) {
      link = web.document.createElement('link') as web.HTMLLinkElement;
      link.rel = 'canonical';
      web.document.head?.append(link);
    }
    link.href = url;
  }
}
