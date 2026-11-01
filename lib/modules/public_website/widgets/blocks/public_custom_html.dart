import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../content/blocks/custom_html.dart';
import 'website_blocks_view.dart' show followBlockLink;

/// A Custom HTML block's markup drawn as Flutter text and images, in the
/// site's typography. The source goes through [CustomHtml.sanitized]
/// first; then only [CustomHtml.blockElements] and
/// [CustomHtml.inlineElements] are drawn, a link only when
/// [CustomHtml.linkAllowed], and an image only when
/// [CustomHtml.imageAllowed] ([PublicCustomHtmlImage]). Nothing is ever
/// placed in the page as HTML, so no script, style or embed can run. The
/// editor's preview and canvas use this same widget; there
/// ([interactive] false) links don't open.
class PublicCustomHtml extends StatefulWidget {
  const PublicCustomHtml({
    super.key,
    required this.source,
    required this.bodyStyle,
    required this.headingStyle,
    required this.linkColor,
    required this.ruleColor,
    this.textAlign = TextAlign.start,
    this.interactive = true,
  });

  final String source;
  final TextStyle bodyStyle;
  final TextStyle headingStyle;
  final Color linkColor;
  final Color ruleColor;
  final TextAlign textAlign;
  final bool interactive;

  @override
  State<PublicCustomHtml> createState() => _PublicCustomHtmlState();
}

class _PublicCustomHtmlState extends State<PublicCustomHtml> {
  late List<Widget> _blocks;
  List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(PublicCustomHtml old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source ||
        old.bodyStyle != widget.bodyStyle ||
        old.headingStyle != widget.headingStyle ||
        old.linkColor != widget.linkColor ||
        old.ruleColor != widget.ruleColor ||
        old.textAlign != widget.textAlign ||
        old.interactive != widget.interactive) {
      final previous = _recognizers;
      _build();
      // The old text may still hold them until this frame is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in previous) {
          r.dispose();
        }
      });
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _build() {
    _recognizers = [];
    _blocks = _HtmlBuilder(this).blocks(CustomHtml.sanitized(widget.source), 0, widget.bodyStyle);
  }

  TapGestureRecognizer _link(String target) {
    final r = TapGestureRecognizer()..onTap = () => followBlockLink(context, target);
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: switch (widget.textAlign) { TextAlign.center => CrossAxisAlignment.center, TextAlign.end => CrossAxisAlignment.end, _ => CrossAxisAlignment.stretch },
        children: [for (final (i, b) in _blocks.indexed) ...[if (i > 0) const SizedBox(height: 12), b]],
      );
}

/// Reads sanitized markup into paragraphs, headings, lists, quotes and
/// rules.
class _HtmlBuilder {
  _HtmlBuilder(this.state);

  final _PublicCustomHtmlState state;
  PublicCustomHtml get w => state.widget;

  static const _mono = ['Menlo', 'Consolas', 'monospace'];

  TextStyle get _h3 => w.headingStyle.copyWith(fontSize: (w.headingStyle.fontSize ?? 26) * 0.8);

  /// The blocks in [node]: runs of text and inline elements become
  /// paragraphs in [style]; block elements their own widgets.
  List<Widget> blocks(dom.Node node, int depth, TextStyle style, {bool pre = false}) {
    final out = <Widget>[];
    var run = <dom.Node>[];
    void flush() {
      if (run.isEmpty) return;
      final spans = _inline(run, style, depth, href: null, pre: pre);
      run = [];
      if (_isBlank(spans)) return;
      // Blank space at the start and end of a paragraph isn't drawn (as
      // in a browser), so a lone image sits where the block aligns it.
      bool blank(InlineSpan s) => s is TextSpan && s.children == null && (s.text ?? '').trim().isEmpty;
      if (!pre) {
        while (blank(spans.first)) {
          spans.removeAt(0);
        }
        while (blank(spans.last)) {
          spans.removeLast();
        }
      }
      out.add(Text.rich(TextSpan(children: spans), textAlign: w.textAlign));
    }

    for (final child in node.nodes) {
      final tag = child is dom.Element ? child.localName ?? '' : '';
      if (child is dom.Element && CustomHtml.blockElements.contains(tag)) {
        flush();
        if (depth < CustomHtml.maxDepth) out.addAll(_block(child, tag, depth + 1, style));
      } else if (child is dom.Text || (child is dom.Element && (CustomHtml.inlineElements.contains(tag) || tag == 'img'))) {
        run.add(child);
      }
    }
    flush();
    return out;
  }

  List<Widget> _block(dom.Element e, String tag, int depth, TextStyle style) {
    Widget column(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(height: 12), c]],
        );
    List<Widget> heading(TextStyle s) {
      final spans = _inline(e.nodes, s, depth, href: null);
      if (_isBlank(spans)) return const [];
      return [Semantics(header: true, child: Text.rich(TextSpan(children: spans), textAlign: w.textAlign))];
    }

    switch (tag) {
      case 'h1' || 'h2':
        return heading(w.headingStyle);
      case 'h3':
        return heading(_h3);
      case 'h4' || 'h5' || 'h6':
        return heading(style.copyWith(fontWeight: FontWeight.w700));
      case 'hr':
        return [Divider(height: 16, thickness: 1, color: w.ruleColor)];
      case 'ul' || 'ol':
        final items = [for (final li in e.children) if (li.localName == 'li') li];
        if (items.isEmpty) return const [];
        final ordered = tag == 'ol';
        return [
          column([
            for (final (i, li) in items.indexed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 24, child: ExcludeSemantics(child: Text(ordered ? '${i + 1}.' : '•', style: style))),
                  Expanded(child: column(blocks(li, depth + 1, style))),
                ],
              ),
          ]),
        ];
      case 'blockquote':
        final inner = blocks(e, depth, style.copyWith(fontStyle: FontStyle.italic));
        if (inner.isEmpty) return const [];
        return [
          Container(
            padding: const EdgeInsets.only(left: 16),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: w.ruleColor, width: 3))),
            child: column(inner),
          ),
        ];
      case 'pre':
        final spans = _inline(e.nodes, style.copyWith(fontFamilyFallback: _mono, fontSize: (style.fontSize ?? 16) * 0.9), depth, href: null, pre: true);
        if (_isBlank(spans)) return const [];
        return [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: w.ruleColor.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8)),
            child: Text.rich(TextSpan(children: spans)),
          ),
        ];
      case 'dt' || 'summary':
        return blocks(e, depth, style.copyWith(fontWeight: FontWeight.w700));
      case 'dd':
        final inner = blocks(e, depth, style);
        return inner.isEmpty ? const [] : [Padding(padding: const EdgeInsets.only(left: 16), child: column(inner))];
      default:
        // p, div, li outside a list, dl, figure, figcaption, details.
        return blocks(e, depth, style);
    }
  }

  /// The text and images of [nodes] in [style], links followed only when
  /// allowed. An image whose address is allowed is drawn (inside an
  /// allowed link [href], it opens the link); otherwise, inside an allowed
  /// link it reads as its description, else the link's [linkTitle]
  /// ([CustomHtml.imageLinkText]), and adds nothing anywhere else. In a
  /// link around a drawn image, blank text is left out ([imageLink]): no
  /// underlined spaces beside the picture.
  List<InlineSpan> _inline(List<dom.Node> nodes, TextStyle style, int depth, {required String? href, String? linkTitle, bool pre = false, bool imageLink = false}) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final text = pre ? node.text : node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isEmpty || (imageLink && text.trim().isEmpty)) continue;
        spans.add(TextSpan(text: text, style: style, recognizer: href != null && w.interactive ? state._link(href) : null));
        continue;
      }
      if (node is! dom.Element || depth >= CustomHtml.maxDepth) continue;
      final tag = node.localName ?? '';
      if (tag == 'img') {
        final label = href == null ? null : CustomHtml.imageLinkText(node, linkTitle: linkTitle);
        if (CustomHtml.imageAllowed(node.attributes['src'])) {
          spans.add(WidgetSpan(alignment: PlaceholderAlignment.middle, child: _image(node, style, href: href, label: label)));
        } else if (label != null) {
          spans.add(TextSpan(text: label, style: style, recognizer: w.interactive ? state._link(href!) : null));
        }
        continue;
      }
      if (!CustomHtml.isShown(tag)) continue;
      if (tag == 'br') {
        spans.add(TextSpan(text: '\n', style: style));
        continue;
      }
      var s = style;
      var link = href;
      var title = linkTitle;
      var aroundImage = imageLink;
      switch (tag) {
        case 'a':
          final target = node.attributes['href']?.trim();
          if (CustomHtml.linkAllowed(target)) {
            link = target;
            title = node.attributes['title'];
            aroundImage = node.querySelectorAll('img').any((i) => CustomHtml.imageAllowed(i.attributes['src']));
            s = s.copyWith(color: w.linkColor, decoration: TextDecoration.underline, decorationColor: w.linkColor);
          }
        case 'b' || 'strong':
          s = s.copyWith(fontWeight: FontWeight.w700);
        case 'i' || 'em' || 'cite' || 'dfn' || 'var':
          s = s.copyWith(fontStyle: FontStyle.italic);
        case 's' || 'strike' || 'del':
          s = s.copyWith(decoration: TextDecoration.lineThrough);
        case 'ins':
          s = s.copyWith(decoration: TextDecoration.underline);
        case 'small' || 'sub' || 'sup':
          s = s.copyWith(fontSize: (s.fontSize ?? 16) * 0.85);
        case 'code' || 'kbd' || 'samp' || 'tt':
          s = s.copyWith(fontFamilyFallback: _mono, fontSize: (s.fontSize ?? 16) * 0.9);
        case 'mark':
          s = s.copyWith(backgroundColor: w.ruleColor.withValues(alpha: 0.5));
      }
      final inner = _inline(node.nodes, s, depth + 1, href: link, linkTitle: title, pre: pre, imageLink: aroundImage);
      if (tag == 'q') {
        spans.addAll([TextSpan(text: '“', style: s), ...inner, TextSpan(text: '”', style: s)]);
      } else if (CustomHtml.blockElements.contains(tag)) {
        // A block inside a line (malformed markup): its text on the line.
        spans.addAll([TextSpan(text: ' ', style: s), ...inner, TextSpan(text: ' ', style: s)]);
      } else {
        spans.addAll(inner);
      }
    }
    return spans;
  }

  int _images = 0;

  /// A drawn image; inside an allowed link ([href]) it opens the link
  /// (on the website only) and is announced as a link named [label].
  Widget _image(dom.Element e, TextStyle style, {required String? href, required String? label}) {
    final n = _images++;
    final size = CustomHtml.imageSize(e);
    final alt = CustomHtml.imageAlt(e);
    final picture = PublicCustomHtmlImage(
      key: Key('public-html-image-$n'),
      src: e.attributes['src']!.trim(),
      width: size.width,
      height: size.height,
      // In a link the link carries the description.
      semanticLabel: href == null ? alt : null,
      fallbackText: href == null ? alt : label,
      fallbackStyle: style,
    );
    if (href == null) return picture;
    return Semantics(
      key: Key('public-html-image-$n-link'),
      container: true,
      link: true,
      label: label,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: w.interactive ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: w.interactive ? () => followBlockLink(state.context, href) : null,
            child: picture,
          ),
        ),
      ),
    );
  }

  static bool _isBlank(List<InlineSpan> spans) => spans.every((s) => s is TextSpan && (s.text ?? '').trim().isEmpty && (s.children ?? const []).isEmpty);
}

/// An image in a Custom HTML block, loaded from its https address
/// ([CustomHtml.imageAllowed]; the caller checks). Drawn at its `width`
/// and `height` when given (keeping their shape), else at its own size,
/// and always scaled down to fit the line it is on and [maxHeight]: never
/// wider than the block. While loading it takes no space; if it can't be
/// loaded, [fallbackText] (its description) shows instead.
class PublicCustomHtmlImage extends StatelessWidget {
  const PublicCustomHtmlImage({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.semanticLabel,
    this.fallbackText,
    required this.fallbackStyle,
  });

  final String src;
  final double? width;
  final double? height;

  /// Read by screen readers; null for a decorative image (or one whose
  /// link is labelled instead).
  final String? semanticLabel;
  final String? fallbackText;
  final TextStyle fallbackStyle;

  /// The tallest an image is drawn.
  static const maxHeight = 960.0;

  @override
  Widget build(BuildContext context) {
    final (width, height) = (this.width, this.height);
    final image = Image.network(
      src,
      width: width != null && height != null ? double.infinity : width,
      height: width != null && height != null ? double.infinity : height,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      // Other sites rarely allow canvas decoding (CORS); then the browser
      // draws it as a plain <img> element. Nothing else from the markup
      // reaches that element.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (context, error, stackTrace) => switch (fallbackText) {
        final text? => Text(text, style: fallbackStyle),
        null => const SizedBox.shrink(),
      },
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: width ?? double.infinity),
      // Both sides given: keep their shape at any width.
      child: width != null && height != null ? AspectRatio(aspectRatio: width / height, child: image) : image,
    );
  }
}
