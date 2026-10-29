import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../content/blocks/custom_html.dart';
import 'website_blocks_view.dart' show followBlockLink;

/// A Custom HTML block's markup drawn as Flutter text, in the site's
/// typography. The source goes through [CustomHtml.sanitized] first; then
/// only [CustomHtml.blockElements] and [CustomHtml.inlineElements] are
/// drawn, and a link only when [CustomHtml.linkAllowed]. Nothing is ever
/// placed in the page as HTML, so no script, style or embed can run. In
/// the editor ([interactive] false) links don't open.
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
      out.add(Text.rich(TextSpan(children: spans), textAlign: w.textAlign));
    }

    for (final child in node.nodes) {
      final tag = child is dom.Element ? child.localName ?? '' : '';
      if (child is dom.Element && CustomHtml.blockElements.contains(tag)) {
        flush();
        if (depth < CustomHtml.maxDepth) out.addAll(_block(child, tag, depth + 1, style));
      } else if (child is dom.Text || (child is dom.Element && CustomHtml.inlineElements.contains(tag))) {
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

  /// The text of [nodes] in [style], links followed only when allowed.
  /// Inside an allowed link ([href]) an image reads as its description,
  /// else the link's [linkTitle] ([CustomHtml.imageLinkText]); it is
  /// never drawn or fetched, and adds nothing anywhere else.
  List<InlineSpan> _inline(List<dom.Node> nodes, TextStyle style, int depth, {required String? href, String? linkTitle, bool pre = false}) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      if (node is dom.Text) {
        final text = pre ? node.text : node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isEmpty) continue;
        spans.add(TextSpan(text: text, style: style, recognizer: href != null && w.interactive ? state._link(href) : null));
        continue;
      }
      if (node is! dom.Element || depth >= CustomHtml.maxDepth) continue;
      final tag = node.localName ?? '';
      if (tag == 'img') {
        final label = href == null ? null : CustomHtml.imageLinkText(node, linkTitle: linkTitle);
        if (label != null) spans.add(TextSpan(text: label, style: style, recognizer: w.interactive ? state._link(href!) : null));
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
      switch (tag) {
        case 'a':
          final target = node.attributes['href']?.trim();
          if (CustomHtml.linkAllowed(target)) {
            link = target;
            title = node.attributes['title'];
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
      final inner = _inline(node.nodes, s, depth + 1, href: link, linkTitle: title, pre: pre);
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

  static bool _isBlank(List<InlineSpan> spans) => spans.every((s) => s is TextSpan && (s.text ?? '').trim().isEmpty && (s.children ?? const []).isEmpty);
}
