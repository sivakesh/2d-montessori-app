import 'package:flutter/material.dart';

import '../../content/blocks/faq_accordion.dart';
import '../../content/blocks/field_spec.dart';
import '../../content/blocks/website_block.dart';
import '../../content/blocks/website_icons.dart';
import '../../content/website_design.dart';
import '../../public_strings.dart';
import '../../public_website_theme.dart';
import 'website_icon_view.dart';

/// An FAQ block ([FaqAccordion]) as visitors (and the editor) see it: an
/// optional heading and description, then each question as a card whose
/// question row is a button opening its answer below. One answer at a time
/// or several ([FaqAccordion.multipleOpen]); all closed at first or the
/// first open ([FaqAccordion.firstOpen]), afterwards as the visitor opens
/// and closes them. A question may start a category (a small heading).
///
/// Only the question row is a button (the answer and the rest of the card
/// are not): announced as a button with its question and whether it is
/// expanded, reachable with Tab and opened with Enter or Space. The icon is
/// decorative.
///
/// Keys (with [keyPrefix], `public-faq` on the page): `<prefix>-<block id>`,
/// `<prefix>-<item id>`, with `-question`, `-answer`, `-icon`, `-category`.
class PublicFaqAccordion extends StatefulWidget {
  const PublicFaqAccordion({
    super.key,
    required this.block,
    required this.language,
    required this.layout,
    required this.headingStyle,
    required this.bodyStyle,
    required this.headingColor,
    required this.textColor,
    this.keyPrefix = 'public-faq',
  });

  final StructuredBlock block;
  final PublicLanguage language;
  final PublicLayout layout;
  final TextStyle headingStyle;
  final TextStyle bodyStyle;
  final Color headingColor;
  final Color textColor;
  final String keyPrefix;

  /// The questions visitors see: those with a question in [language] (or
  /// the English it falls back to).
  static List<BlockItem> shown(StructuredBlock block, PublicLanguage language) => [
        for (final item in block.items('items'))
          if (item.text('question').resolve(language).trim().isNotEmpty) item,
      ];

  /// Whether visitors would see anything: a question, or the text above.
  static bool hasContent(StructuredBlock block, PublicLanguage language) =>
      shown(block, language).isNotEmpty || ['heading', 'description'].any((k) => block.text(k).resolve(language).trim().isNotEmpty);

  @override
  State<PublicFaqAccordion> createState() => _PublicFaqAccordionState();
}

class _PublicFaqAccordionState extends State<PublicFaqAccordion> {
  late Set<String> _open = _initial();

  StructuredBlock get _block => widget.block;

  Set<String> _initial() {
    final shown = PublicFaqAccordion.shown(_block, widget.language);
    return FaqAccordion.firstOpen(_block) && shown.isNotEmpty ? {shown.first.id} : <String>{};
  }

  @override
  void didUpdateWidget(PublicFaqAccordion old) {
    super.didUpdateWidget(old);
    // A changed behaviour starts again from its initial state (the editor
    // shows it at once); otherwise what the visitor opened stays open.
    if (old.block.string('mode') != _block.string('mode') || old.block.string('initiallyOpen') != _block.string('initiallyOpen')) {
      _open = _initial();
      return;
    }
    final ids = {for (final i in PublicFaqAccordion.shown(_block, widget.language)) i.id};
    _open = {for (final id in _open) if (ids.contains(id)) id};
  }

  void _toggle(String id) => setState(() {
        if (_open.contains(id)) {
          _open.remove(id);
        } else if (FaqAccordion.multipleOpen(_block)) {
          _open.add(id);
        } else {
          _open = {id};
        }
      });

  Color? _color(SiteDesign design, String key) => switch (_block.string(key)) {
        ColorFieldSpec.automatic || '' => null,
        ColorFieldSpec.transparent => Colors.transparent,
        final v => design.resolve(v),
      };

  static FontWeight _weight(int w) => FontWeight.values[((w ~/ 100) - 1).clamp(0, FontWeight.values.length - 1)];

  /// [id] if this version has it, else [fallback] (never a blank icon).
  static String _iconId(String id, String fallback) => WebsiteIcons.lookup(id) == null ? fallback : id;

  @override
  Widget build(BuildContext context) {
    final design = WebsiteDesignScope.of(context);
    final b = _block;
    final p = widget.keyPrefix;
    final screen = switch (widget.layout) { PublicLayout.mobile => 'mobile', PublicLayout.tablet => 'tablet', PublicLayout.desktop => 'desktop' };
    final heading = b.text('heading').resolve(widget.language).trim();
    final description = b.text('description').resolve(widget.language).trim();
    final items = PublicFaqAccordion.shown(b, widget.language);

    final questionColor = _color(design, 'questionColor') ?? widget.headingColor;
    final questionStyle = widget.bodyStyle.copyWith(
      fontSize: FaqAccordion.questionSize(b, screen),
      fontWeight: _weight(FaqAccordion.questionWeight(b)),
      color: questionColor,
      height: 1.35,
    );
    final answerStyle = widget.bodyStyle.copyWith(
      fontSize: FaqAccordion.answerSize(b, screen),
      fontWeight: _weight(FaqAccordion.answerWeight(b)),
      color: _color(design, 'answerColor') ?? widget.textColor,
      height: FaqAccordion.lineHeight(b),
    );
    final align = switch (b.string('questionAlign')) { 'center' => TextAlign.center, 'end' => TextAlign.end, _ => TextAlign.start };
    final itemBackground = _color(design, 'itemBackground') ?? design.colorOf('surface');
    final borderColor = _color(design, 'borderColor') ?? design.colorOf('line');
    final openBorderColor = _color(design, 'openBorderColor') ?? design.colorOf('gold');
    final borderWidth = FaqAccordion.borderWidth(b).clamp(0.0, 3.0);
    final radius = FaqAccordion.radius(b);
    final padding = FaqAccordion.padding(b, screen);
    final gap = FaqAccordion.gap(b, screen);
    final iconColor = _color(design, 'iconColor') ?? questionColor;
    final iconSize = FaqAccordion.iconSize(b);
    final circle = b.values['iconCircle'] != false;
    final circleColor = _color(design, 'iconCircleColor') ?? design.colorOf('line');
    final expandIcon = _iconId(FaqAccordion.expandIconOf(b), FaqAccordion.expandIcon);
    final collapseIcon = _iconId(FaqAccordion.collapseIconOf(b), FaqAccordion.collapseIcon);

    Widget item(BlockItem it) {
      final open = _open.contains(it.id);
      final icon = WebsiteIconView(key: Key('$p-${it.id}-icon'), id: open ? collapseIcon : expandIcon, size: iconSize, color: iconColor);
      final question = Semantics(
        container: true,
        button: true,
        expanded: open,
        child: InkWell(
          key: Key('$p-${it.id}-question'),
          onTap: () => _toggle(it.id),
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Row(
              children: [
                Expanded(child: Text(it.text('question').resolve(widget.language).trim(), textAlign: align, style: questionStyle)),
                SizedBox(width: padding < 16 ? 10 : 16),
                ExcludeSemantics(
                  child: circle
                      ? Container(
                          width: iconSize + 14,
                          height: iconSize + 14,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: open ? openBorderColor : circleColor, width: 1.5)),
                          child: icon,
                        )
                      : icon,
                ),
              ],
            ),
          ),
        ),
      );
      final answer = it.text('answer').resolve(widget.language).trim();
      return AnimatedContainer(
        key: Key('$p-${it.id}'),
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: itemBackground,
          borderRadius: BorderRadius.circular(radius),
          border: borderWidth <= 0 ? null : Border.all(color: open ? openBorderColor : borderColor, width: borderWidth),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                question,
                if (open && answer.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                    child: Text(answer, key: Key('$p-${it.id}-answer'), style: answerStyle),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];
    String? category;
    for (final (i, it) in items.indexed) {
      final c = it.text('category').resolve(widget.language).trim();
      if (c.isNotEmpty && c != category) {
        if (i > 0) children.add(SizedBox(height: gap + 12));
        children.add(Semantics(
          header: true,
          child: Text(
            c,
            key: Key('$p-${it.id}-category'),
            style: widget.bodyStyle.copyWith(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: questionColor),
          ),
        ));
        children.add(const SizedBox(height: 12));
      } else if (i > 0) {
        children.add(SizedBox(height: gap));
      }
      if (c.isNotEmpty) category = c;
      children.add(item(it));
    }

    final outer = switch (widget.layout) { PublicLayout.mobile => 16.0, PublicLayout.tablet => 28.0, PublicLayout.desktop => 36.0 };
    // Its background clipped to its rounded corners (its own radius, apart
    // from the cards').
    return Container(
      key: Key('$p-${b.id}'),
      decoration: BoxDecoration(
        color: _color(design, 'sectionBackground') ?? design.colorOf('background'),
        borderRadius: BorderRadius.circular(FaqAccordion.containerRadius(b)),
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(outer),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading.isNotEmpty) Semantics(header: true, child: Text(heading, style: widget.headingStyle)),
          if (description.isNotEmpty) ...[
            if (heading.isNotEmpty) const SizedBox(height: 12),
            Text(description, style: widget.bodyStyle),
          ],
          if (heading.isNotEmpty || description.isNotEmpty) const SizedBox(height: 28),
          ...children,
        ],
      ),
    );
  }
}
