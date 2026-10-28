import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'website_design.dart';

/// How one page looks, apart from its blocks: stored as `pageStyle` on the
/// page's draft and live documents (additional pages and built-in pages
/// built with blocks), published with the page. Optional: a page without
/// one looks as it always has. Keys this version doesn't know are kept.
@immutable
class PageStyle {
  const PageStyle({this.background, this.preserved = const {}});

  static const field = 'pageStyle';

  /// The page's content area, between the site header and footer (never
  /// the header, top bar, footer or a section's own background): a palette
  /// reference or `#RRGGBB` ([SiteDesign]); null: the site's own.
  final String? background;
  final Map<String, Object?> preserved;

  static const _keys = {'background'};

  static PageStyle fromMap(Object? raw) {
    if (raw is! Map) return const PageStyle();
    final background = raw['background'];
    return PageStyle(
      background: background is String && background.isNotEmpty ? background : null,
      preserved: {for (final e in raw.entries) if (!_keys.contains(e.key)) e.key.toString(): e.value},
    );
  }

  Map<String, dynamic> toMap() => {...preserved, 'background': ?background};

  bool get isDefault => toMap().isEmpty;

  PageStyle copyWith({String? Function()? background}) => PageStyle(background: background == null ? this.background : background(), preserved: preserved);

  List<String> validationErrors() => [
        if (background != null && !SiteDesign.isColorValue(background)) 'Page background: choose a colour from the palette or enter #RRGGBB.',
      ];

  /// The content area's colour under [design], or null for the site's own.
  Color? resolveBackground(SiteDesign design) => design.resolve(background);

  @override
  bool operator ==(Object other) => other is PageStyle && jsonEncode(other.toMap()) == jsonEncode(toMap());

  @override
  int get hashCode => jsonEncode(toMap()).hashCode;
}

/// The page's content area in [style]'s background, or [child] as it is
/// when there is none. The header, top bar and footer are outside it.
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.style, required this.child});

  final PageStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = style.resolveBackground(WebsiteDesignScope.of(context));
    if (color == null) return child;
    return ColoredBox(key: const Key('public-page-background'), color: color, child: child);
  }
}
