import 'package:flutter/material.dart';

import '../../content/blocks/website_icons.dart';

/// One icon of the website's icon library ([WebsiteIcons]), as the Icon
/// block and Text blocks draw it on the canvas, in the previews and on the
/// published page: [size] px in [color], optionally on [background] with
/// [padding] and [radius] (null: round), and optionally [onTap] (a link).
///
/// [semanticLabel] names it for screen readers; empty: decorative (left
/// out), unless it is a link, which then has no name (the editor asks for
/// one). An unknown [id] (a newer app's icon, or one removed) draws
/// nothing.
class WebsiteIconView extends StatelessWidget {
  const WebsiteIconView({
    super.key,
    required this.id,
    required this.size,
    required this.color,
    this.background,
    this.padding = 0,
    this.radius,
    this.semanticLabel = '',
    this.onTap,
  });

  final String id;
  final double size;
  final Color color;
  final Color? background;
  final double padding;
  final double? radius;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final icon = WebsiteIcons.lookup(id);
    if (icon == null) return const SizedBox.shrink(key: Key('website-icon-missing'));
    final outer = size + padding * 2;
    Widget drawn = Container(
      width: outer,
      height: outer,
      alignment: Alignment.center,
      decoration: background == null ? null : BoxDecoration(color: background, borderRadius: BorderRadius.circular(radius ?? outer / 2)),
      child: Icon(icon.data, size: size, color: color),
    );
    if (onTap != null) {
      drawn = Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius ?? outer / 2), child: drawn),
      );
    }
    final label = semanticLabel.trim();
    if (label.isEmpty && onTap == null) return ExcludeSemantics(child: drawn);
    return Semantics(
      container: true,
      label: label,
      link: onTap != null,
      image: onTap == null,
      onTap: onTap,
      excludeSemantics: true,
      child: drawn,
    );
  }
}
