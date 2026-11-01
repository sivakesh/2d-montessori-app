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
///    sanitizer removes). An image is drawn only when its own address
///    passes [imageAllowed] (https only), checked separately from links;
///    otherwise, inside an allowed link it reads as its description
///    ([imageLinkText]), elsewhere it is left out. Elements outside both
///    sets are left out with their content; no attribute other than a
///    link's `href` and `title` and an image's `src`, `alt`, `width` and
///    `height` ([imageAttributes]) is used.
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

  /// The attributes of an `<img>` that are used; any other (styles,
  /// classes, `srcset`, event handlers …) is ignored.
  static const imageAttributes = {'src', 'alt', 'width', 'height'};

  /// The longest image address used.
  static const maxImageUrlLength = 2048;

  /// Whether an image at [src] is loaded and drawn: an absolute `https:`
  /// address with a host, without a user name, password or non-default
  /// port, spaces or backslashes. Everything else (`http:`, relative and
  /// protocol-relative addresses, `data:`, `blob:`, `javascript:` and any
  /// other scheme) is never fetched. Independent of [linkAllowed].
  static bool imageAllowed(String? src) {
    final s = src?.trim() ?? '';
    if (s.isEmpty || s.length > maxImageUrlLength || s.contains(RegExp(r'[\s\\\x00-\x1f\x7f]'))) return false;
    final uri = Uri.tryParse(s);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty && !uri.hasPort;
  }

  /// The largest `width` or `height` used, in logical pixels.
  static const maxImageSide = 4000.0;

  /// An image's `width` and `height` attributes as logical pixels (a
  /// whole number, optionally with `px`, from 1 to [maxImageSide]); null
  /// for anything else (percentages, `auto`, CSS). The image is still
  /// scaled down to fit the space it is drawn in.
  static ({double? width, double? height}) imageSize(dom.Element image) {
    double? side(String name) {
      final m = RegExp(r'^(\d{1,5})(px)?$').firstMatch(image.attributes[name]?.trim().toLowerCase() ?? '');
      final v = m == null ? null : double.parse(m.group(1)!);
      return v != null && v >= 1 && v <= maxImageSide ? v : null;
    }

    return (width: side('width'), height: side('height'));
  }

  /// An image's description for screen readers (its `alt`), or null.
  static String? imageAlt(dom.Element image) => _usable(image.attributes['alt']);

  /// What an image reads as when it isn't drawn (its address isn't
  /// [imageAllowed]) inside an allowed link, or as a drawn image's label
  /// inside one: the image's `alt`, else the link's `title`, as plain
  /// text. Null when neither has text.
  static String? imageLinkText(dom.Element image, {required String? linkTitle}) => _usable(image.attributes['alt']) ?? _usable(linkTitle);

  /// What happens to [source] when it is shown, for the editor.
  static CustomHtmlReport report(String source) {
    final removed = <String, int>{};
    final attributes = <String>{};
    final links = <String>[];
    final blockedImages = <String>[];
    String short(String s) => s.length > 60 ? '${s.substring(0, 60)}…' : s;
    String attribute(String name) => name.startsWith('on') ? 'on… (event handlers)' : name;
    void walk(dom.Node node, int depth) {
      for (final child in node.nodes) {
        if (child is! dom.Element) continue;
        final tag = child.localName ?? '';
        // Images are counted below, from what the sanitizer keeps; their
        // addresses are checked here, as typed.
        if (tag == 'img' && depth < maxDepth) {
          for (final name in child.attributes.keys) {
            final key = name.toString().toLowerCase();
            if (!imageAttributes.contains(key)) attributes.add(attribute(key));
          }
          final src = child.attributes['src']?.trim() ?? '';
          if (src.isNotEmpty && !imageAllowed(src)) blockedImages.add(short(src));
          continue;
        }
        if (!isShown(tag) || depth >= maxDepth) {
          final key = depth >= maxDepth ? 'nested too deeply' : tag;
          removed[key] = (removed[key] ?? 0) + 1;
          continue;
        }
        for (final name in child.attributes.keys) {
          final key = name.toString().toLowerCase();
          // A link's title is its text when its image has no description.
          if (tag == 'a' && (key == 'href' || key == 'title')) continue;
          attributes.add(attribute(key));
        }
        if (tag == 'a' && child.attributes.containsKey('href') && !linkAllowed(child.attributes['href'])) {
          links.add(short(child.attributes['href']!.trim()));
        }
        walk(child, depth + 1);
      }
    }

    walk(html_parser.parseFragment(source), 0);

    // Images, and links with nothing to show, as the renderer sees them.
    var imagesShown = 0;
    var imagesWithoutAlt = 0;
    var imagesAsText = 0;
    var imagesHidden = 0;
    final emptyLinks = <String>[];
    void images(dom.Node node, int depth, {String? linkTitle, bool inLink = false}) {
      for (final child in node.nodes) {
        if (child is! dom.Element || depth >= maxDepth) continue;
        final tag = child.localName ?? '';
        if (tag == 'img') {
          if (imageAllowed(child.attributes['src'])) {
            imagesShown++;
            if ((inLink ? imageLinkText(child, linkTitle: linkTitle) : imageAlt(child)) == null) imagesWithoutAlt++;
          } else {
            inLink && imageLinkText(child, linkTitle: linkTitle) != null ? imagesAsText++ : imagesHidden++;
          }
          continue;
        }
        if (!isShown(tag)) continue;
        if (tag == 'a' && linkAllowed(child.attributes['href'])) {
          if (_visibleText(child, depth + 1, linkTitle: child.attributes['title'], inLink: true).isEmpty && !_hasShownImage(child, depth + 1)) {
            emptyLinks.add(short(child.attributes['href']!.trim()));
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
      imagesShown: imagesShown,
      imagesWithoutAlt: imagesWithoutAlt,
      blockedImages: blockedImages,
      imagesAsLinkText: imagesAsText,
      imagesNotShown: imagesHidden,
      emptyLinks: emptyLinks,
      hasContent: text.isNotEmpty || imagesShown > 0 || _hasRule(clean, 0),
      plainText: text,
    );
  }

  /// Whether [node] holds an image that is drawn ([imageAllowed]).
  static bool _hasShownImage(dom.Node node, int depth) =>
      depth < maxDepth &&
      node.nodes.any((n) => n is dom.Element && (n.localName == 'img' ? imageAllowed(n.attributes['src']) : isShown(n.localName ?? '') && _hasShownImage(n, depth + 1)));

  static bool _hasRule(dom.Node node, int depth) =>
      depth < maxDepth && node.nodes.any((n) => n is dom.Element && isShown(n.localName ?? '') && (n.localName == 'hr' || _hasRule(n, depth + 1)));

  /// The text visitors see or hear inside [node] (a drawn image as its
  /// description; an image not drawn, inside an allowed link, as its
  /// [imageLinkText]), whitespace collapsed.
  static String _visibleText(dom.Node node, int depth, {String? linkTitle, bool inLink = false}) {
    final out = StringBuffer();
    void walk(dom.Node node, int depth, String? title, bool link) {
      for (final child in node.nodes) {
        if (child is dom.Text) out.write('${child.text} ');
        if (child is! dom.Element || depth >= maxDepth) continue;
        final tag = child.localName ?? '';
        if (tag == 'img') {
          if (imageAllowed(child.attributes['src'])) {
            out.write('${imageAlt(child) ?? ''} ');
          } else if (link) {
            out.write('${imageLinkText(child, linkTitle: title) ?? ''} ');
          }
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

  /// The words visitors see (and drawn images' descriptions), whitespace
  /// collapsed (for summaries and checks).
  static String plainText(String source) => _visibleText(sanitized(source), 0);
}

/// What [CustomHtml.report] found: what visitors won't see, and why.
@immutable
class CustomHtmlReport {
  const CustomHtmlReport({
    required this.removedElements,
    required this.ignoredAttributes,
    required this.blockedLinks,
    this.imagesShown = 0,
    this.imagesWithoutAlt = 0,
    this.blockedImages = const [],
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

  /// Images drawn ([CustomHtml.imageAllowed]).
  final int imagesShown;

  /// Of [imagesShown], those without a description (no `alt`, and inside
  /// a link no `title` either): screen readers can't describe them.
  final int imagesWithoutAlt;

  /// Image addresses never fetched (not https, or otherwise unsafe), as
  /// typed.
  final List<String> blockedImages;

  /// Images not drawn (their address isn't allowed) inside allowed links,
  /// shown as their description (the link's text) instead.
  final int imagesAsLinkText;

  /// Images not drawn and not shown as text (outside a link, or without a
  /// description), including those without an address.
  final int imagesNotShown;

  /// Allowed links not shown because nothing in them has text.
  final List<String> emptyLinks;

  /// Whether anything is shown at all.
  final bool hasContent;
  final String plainText;

  /// Nothing is shown and the markup was only images that can't be drawn
  /// (and links around them).
  bool get onlyImages => !hasContent && imagesNotShown > 0 && removedElements.isEmpty;

  bool get changesSomething =>
      removedElements.isNotEmpty ||
      ignoredAttributes.isNotEmpty ||
      blockedLinks.isNotEmpty ||
      blockedImages.isNotEmpty ||
      imagesAsLinkText > 0 ||
      imagesNotShown > 0 ||
      emptyLinks.isNotEmpty;
}
