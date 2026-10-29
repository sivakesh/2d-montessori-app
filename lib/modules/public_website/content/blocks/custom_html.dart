import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:sanitize_html/sanitize_html.dart' as sanitizer;

import '../website_custom_page.dart';

/// The HTML of a Custom HTML block, made safe to show.
///
/// Two layers, both allowlists:
/// 1. Google's `sanitize_html` (the HTML5 parser, then GitHub's
///    sanitization rules): scripts, styles, forms, iframes, embeds, event
///    handlers and unsafe URLs are removed.
/// 2. Of what it keeps, only [blockElements] and [inlineElements] are
///    drawn, as Flutter text (never as HTML in the page), and a link only
///    when its address passes [SafeLinkTarget] and the sanitizer keeps it
///    (https, mailto, or a page of this website; not tel:, which the
///    sanitizer removes). Elements outside both sets are left out with
///    their content; no attribute other than a link's `href` and `title`
///    and an image's `alt` is used. An image is never drawn or fetched:
///    inside an allowed link it reads as its description
///    ([imageLinkText]); elsewhere it is left out.
///
/// The stored source is kept exactly as typed; it is cleaned each time it
/// is shown, so a later, stricter version applies to existing blocks too.
class CustomHtml {
  CustomHtml._();

  /// Drawn as their own paragraphs or boxes.
  static const blockElements = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'blockquote', 'pre', 'hr', //
    'dl', 'dt', 'dd', 'figure', 'figcaption', 'details', 'summary',
  };

  /// Drawn inside a paragraph.
  static const inlineElements = {
    'a', 'b', 'strong', 'i', 'em', 's', 'strike', 'del', 'ins', 'small', 'sub', 'sup', 'code', 'kbd', //
    'samp', 'tt', 'var', 'q', 'span', 'mark', 'abbr', 'cite', 'dfn', 'time', 'bdo', 'ruby', 'br', 'wbr',
  };

  static bool isShown(String tag) => blockElements.contains(tag) || inlineElements.contains(tag);

  /// Deeper markup than this is not drawn (malformed or hostile nesting).
  static const maxDepth = 32;

  /// [source] after the sanitizer, parsed: what the renderer reads. The
  /// renderer still draws only [isShown] elements and safe links.
  static dom.DocumentFragment sanitized(String source) => html_parser.parseFragment(sanitizer.sanitizeHtml(source));

  /// Whether a link to [href] is followed (otherwise its text shows
  /// without a link).
  static bool linkAllowed(String? href) {
    final target = href?.trim() ?? '';
    return target.isNotEmpty && SafeLinkTarget.validate(target) == null && !target.toLowerCase().startsWith('tel:');
  }

  /// [text] with whitespace collapsed, or null when nothing is left.
  static String? _usable(String? text) {
    final t = text?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// What an image inside an allowed link reads as: the image's `alt`,
  /// else the link's `title`, as plain text (the image itself is never
  /// drawn or fetched). Null when neither has text: the image adds nothing.
  static String? imageLinkText(dom.Element image, {required String? linkTitle}) => _usable(image.attributes['alt']) ?? _usable(linkTitle);

  /// What happens to [source] when it is shown, for the editor.
  static CustomHtmlReport report(String source) {
    final removed = <String, int>{};
    final attributes = <String>{};
    final links = <String>[];
    void walk(dom.Node node, int depth) {
      for (final child in node.nodes) {
        if (child is! dom.Element) continue;
        final tag = child.localName ?? '';
        // Images are counted below, from what the sanitizer keeps.
        if (tag == 'img' && depth < maxDepth) continue;
        if (!isShown(tag) || depth >= maxDepth) {
          final key = depth >= maxDepth ? 'nested too deeply' : tag;
          removed[key] = (removed[key] ?? 0) + 1;
          continue;
        }
        for (final name in child.attributes.keys) {
          final key = name.toString().toLowerCase();
          // A link's title is its text when its image has no description.
          if (tag == 'a' && (key == 'href' || key == 'title')) continue;
          attributes.add(key.startsWith('on') ? 'on… (event handlers)' : key);
        }
        if (tag == 'a' && child.attributes.containsKey('href') && !linkAllowed(child.attributes['href'])) {
          final href = child.attributes['href']!.trim();
          links.add(href.length > 60 ? '${href.substring(0, 60)}…' : href);
        }
        walk(child, depth + 1);
      }
    }

    walk(html_parser.parseFragment(source), 0);

    // Images, and links with nothing to show, as the renderer sees them.
    var imagesAsText = 0;
    var imagesHidden = 0;
    final emptyLinks = <String>[];
    void images(dom.Node node, int depth, {String? linkTitle, bool inLink = false}) {
      for (final child in node.nodes) {
        if (child is! dom.Element || depth >= maxDepth) continue;
        final tag = child.localName ?? '';
        if (tag == 'img') {
          inLink && imageLinkText(child, linkTitle: linkTitle) != null ? imagesAsText++ : imagesHidden++;
          continue;
        }
        if (!isShown(tag)) continue;
        if (tag == 'a' && linkAllowed(child.attributes['href'])) {
          if (_visibleText(child, depth + 1, linkTitle: child.attributes['title'], inLink: true).isEmpty) {
            final href = child.attributes['href']!.trim();
            emptyLinks.add(href.length > 60 ? '${href.substring(0, 60)}…' : href);
          }
          images(child, depth + 1, linkTitle: child.attributes['title'], inLink: true);
        } else {
          images(child, depth + 1, linkTitle: linkTitle, inLink: inLink);
        }
      }
    }

    final clean = sanitized(source);
    images(clean, 0);
    final text = plainText(source);
    return CustomHtmlReport(
      removedElements: removed,
      ignoredAttributes: attributes.toList()..sort(),
      blockedLinks: links,
      imagesAsLinkText: imagesAsText,
      imagesNotShown: imagesHidden,
      emptyLinks: emptyLinks,
      hasContent: text.isNotEmpty || _hasRule(clean, 0),
      plainText: text,
    );
  }

  static bool _hasRule(dom.Node node, int depth) =>
      depth < maxDepth && node.nodes.any((n) => n is dom.Element && isShown(n.localName ?? '') && (n.localName == 'hr' || _hasRule(n, depth + 1)));

  /// The text visitors see inside [node] (images in allowed links as
  /// their [imageLinkText]), whitespace collapsed.
  static String _visibleText(dom.Node node, int depth, {String? linkTitle, bool inLink = false}) {
    final out = StringBuffer();
    void walk(dom.Node node, int depth, String? title, bool link) {
      for (final child in node.nodes) {
        if (child is dom.Text) out.write('${child.text} ');
        if (child is! dom.Element || depth >= maxDepth) continue;
        final tag = child.localName ?? '';
        if (tag == 'img') {
          if (link) out.write('${imageLinkText(child, linkTitle: title) ?? ''} ');
        } else if (tag == 'a' && linkAllowed(child.attributes['href'])) {
          walk(child, depth + 1, child.attributes['title'], true);
        } else if (isShown(tag)) {
          walk(child, depth + 1, title, link);
        }
      }
    }

    walk(node, depth, linkTitle, inLink);
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// The words visitors see, whitespace collapsed (for summaries and
  /// checks).
  static String plainText(String source) => _visibleText(sanitized(source), 0);
}

/// What [CustomHtml.report] found: what visitors won't see, and why.
@immutable
class CustomHtmlReport {
  const CustomHtmlReport({
    required this.removedElements,
    required this.ignoredAttributes,
    required this.blockedLinks,
    this.imagesAsLinkText = 0,
    this.imagesNotShown = 0,
    this.emptyLinks = const [],
    required this.hasContent,
    required this.plainText,
  });

  /// Elements left out with their content (tag → how many).
  final Map<String, int> removedElements;

  /// Attributes not used (styles, classes, event handlers …).
  final List<String> ignoredAttributes;

  /// Link addresses not followed (their text still shows).
  final List<String> blockedLinks;

  /// Images inside allowed links shown as their description (the link's
  /// text); the images themselves are never drawn.
  final int imagesAsLinkText;

  /// Images not shown at all (outside a link, or without a description).
  final int imagesNotShown;

  /// Allowed links not shown because nothing in them has text.
  final List<String> emptyLinks;

  /// Whether anything is shown at all.
  final bool hasContent;
  final String plainText;

  /// Nothing is shown and the markup was only images (and links around
  /// them): Custom HTML doesn't show images.
  bool get onlyImages => !hasContent && imagesNotShown > 0 && removedElements.isEmpty;

  bool get changesSomething =>
      removedElements.isNotEmpty || ignoredAttributes.isNotEmpty || blockedLinks.isNotEmpty || imagesAsLinkText > 0 || imagesNotShown > 0 || emptyLinks.isNotEmpty;
}
