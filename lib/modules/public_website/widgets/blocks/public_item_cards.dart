import 'package:flutter/material.dart';

import '../../public_website_theme.dart';

/// How a list of website items (Upcoming events, Announcements) is laid
/// out: the same three layouts and responsive columns for every kind.
enum PublicItemsLayout {
  /// One item per row.
  list('list'),

  /// Cards in columns: image above the text.
  grid('grid'),

  /// Small cards in columns: a thumbnail beside the text.
  compactCards('compact_cards');

  const PublicItemsLayout(this.id);

  /// The stored `layout` value.
  final String id;

  /// The layout stored as [value]; [grid] for anything else.
  static PublicItemsLayout parse(String? value) {
    for (final layout in values) {
      if (layout.id == value) return layout;
    }
    return grid;
  }
}

/// The narrowest a card may be: fewer columns are used when the space is
/// too small for the number chosen (e.g. in a section column).
const publicItemMinCardWidth = 150.0;

/// How many card columns fit: the number chosen for the screen size at
/// [screenWidth] ([PublicLayout]: phones under 700 px, tablets under
/// 1,100 px, desktops), but at most as many as fit [available] at
/// [publicItemMinCardWidth], and at least one.
int publicItemColumns({
  required double screenWidth,
  required double available,
  required int desktop,
  required int tablet,
  required int mobile,
  required double gap,
}) {
  final wanted = switch (PublicLayout.of(screenWidth)) {
    PublicLayout.mobile => mobile,
    PublicLayout.tablet => tablet,
    PublicLayout.desktop => desktop,
  };
  final fit = ((available + gap) / (publicItemMinCardWidth + gap)).floor();
  return wanted.clamp(1, fit < 1 ? 1 : fit);
}

/// One card of a [PublicItemCardGrid]: its key and its content at a width.
typedef PublicItemCard = ({Key key, Widget Function(BuildContext context, double width) build});

/// Cards in [publicItemColumns] columns of equal width, never wider than
/// the space they are in. Keys: `<keyPrefix>-grid` or `-compact`, and
/// `<keyPrefix>-columns-<n>`.
class PublicItemCardGrid extends StatelessWidget {
  const PublicItemCardGrid({
    super.key,
    required this.keyPrefix,
    required this.compact,
    required this.desktopColumns,
    required this.tabletColumns,
    required this.mobileColumns,
    required this.cards,
  });

  final String keyPrefix;
  final bool compact;
  final int desktopColumns;
  final int tabletColumns;
  final int mobileColumns;
  final List<PublicItemCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        key: Key(compact ? '$keyPrefix-compact' : '$keyPrefix-grid'),
        builder: (context, constraints) {
          final screen = MediaQuery.sizeOf(context).width;
          final gap = PublicLayout.of(screen).isMobile ? 12.0 : (compact ? 16.0 : 20.0);
          final perRow = publicItemColumns(
            screenWidth: screen,
            available: constraints.maxWidth,
            desktop: desktopColumns,
            tablet: tabletColumns,
            mobile: mobileColumns,
            gap: gap,
          );
          final width = PublicLayout.tileWidth(constraints.maxWidth, perRow, gap);
          return KeyedSubtree(
            key: Key('$keyPrefix-columns-$perRow'),
            child: Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards)
                  Container(
                    key: card.key,
                    width: width,
                    decoration: BoxDecoration(
                      color: PublicColors.surface,
                      borderRadius: BorderRadius.circular(compact ? 12 : 16),
                      border: Border.all(color: PublicColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: card.build(context, width),
                  ),
              ],
            ),
          );
        },
      );
}

/// [child] as one button: hover and focus highlight in [accent], keyboard
/// activation (Enter or Space), and one [label] for screen readers.
/// Nothing inside it is clickable, so taps never conflict. Just [child]
/// when [onTap] is null (the editor's canvas).
Widget publicItemClickable({
  required Key key,
  required String label,
  required Color accent,
  required VoidCallback? onTap,
  required Widget child,
  double radius = 12,
}) {
  if (onTap == null) return child;
  return Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(radius),
        hoverColor: accent.withValues(alpha: 0.06),
        focusColor: accent.withValues(alpha: 0.14),
        highlightColor: accent.withValues(alpha: 0.08),
        onTap: onTap,
        child: Padding(padding: EdgeInsets.all(radius == 0 ? 0 : 8), child: child),
      ),
    ),
  );
}
