import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../public_website_theme.dart';

/// A font size's allowed range (px, whole pixels) and the site's own size
/// ([standard], what is shown when nothing is set).
@immutable
class FontSizeRange {
  const FontSizeRange(this.min, this.max, this.standard);

  final double min;
  final double max;
  final double standard;

  bool allows(Object? value) => value is num && value >= min && value <= max && value == value.roundToDouble();

  double clamp(double value) => value.clamp(min, max).roundToDouble();
}

/// The WCAG 2 contrast ratio of [a] and [b]: 1 (none) to 21.
double contrastRatio(Color a, Color b) {
  final (la, lb) = (a.computeLuminance(), b.computeLuminance());
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Text on [background]: [preferred] when it is readable there (WCAG AA,
/// 4.5:1, for normal text), else whichever of it and [alternative]
/// contrasts more.
Color readableTextOn(Color background, {required Color preferred, required Color alternative}) {
  final own = contrastRatio(preferred, background);
  if (own >= 4.5) return preferred;
  return contrastRatio(alternative, background) > own ? alternative : preferred;
}

/// One named colour of the website's palette. [id] is what styles refer to
/// (`token:<id>`), so renaming a colour or changing its value never breaks
/// a reference.
@immutable
class DesignColor {
  const DesignColor({required this.id, required this.name, required this.hex});

  final String id;
  final String name;

  /// `#RRGGBB`.
  final String hex;

  Color get color => SiteDesign.parseHex(hex) ?? const Color(0xFF000000);

  DesignColor copyWith({String? name, String? hex}) => DesignColor(id: id, name: name ?? this.name, hex: hex ?? this.hex);

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'hex': hex};

  static DesignColor? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final hex = raw['hex'];
    if (id is! String || id.isEmpty || hex is! String) return null;
    return DesignColor(id: id, name: raw['name']?.toString() ?? id, hex: hex);
  }

  @override
  bool operator ==(Object other) => other is DesignColor && other.id == id && other.name == name && other.hex == hex;

  @override
  int get hashCode => Object.hash(id, name, hex);
}

/// The website's design tokens: a palette of named colours (the site's own
/// colours, editable, plus any the school adds) and its typography.
///
/// Styles refer to colours as `token:<id>` (follows the palette: change the
/// colour here and everything using it changes) or `#RRGGBB` (a fixed,
/// local colour). The site's own colours can be renamed and changed but not
/// removed, so the header, footer and built-in styles that use them always
/// resolve; added colours can be removed (anything using one then falls
/// back to its default).
///
/// Stored on the site layout (`design`); keys this version doesn't know
/// are kept.
@immutable
class SiteDesign {
  const SiteDesign({
    this.palette = defaultPalette,
    this.bodySize = 16,
    this.headingSize = 26,
    this.lineHeight = 1.6,
    this.titleSize,
    this.titleSizeMobile,
    this.navSize,
    this.buttonSize,
    this.preserved = const {},
  });

  static const defaults = SiteDesign();

  /// The site's own colours (`PublicColors`).
  static const defaultPalette = [
    DesignColor(id: 'forest', name: 'Forest green', hex: '#1F4D3A'),
    DesignColor(id: 'forestDark', name: 'Deep forest', hex: '#163829'),
    DesignColor(id: 'sage', name: 'Sage', hex: '#8FA98B'),
    DesignColor(id: 'sageLight', name: 'Light sage', hex: '#E6EDE2'),
    DesignColor(id: 'gold', name: 'Gold', hex: '#B8955A'),
    DesignColor(id: 'goldLight', name: 'Light gold', hex: '#F3EADB'),
    DesignColor(id: 'ink', name: 'Ink', hex: '#26302B'),
    DesignColor(id: 'muted', name: 'Muted text', hex: '#5F6B64'),
    DesignColor(id: 'background', name: 'Warm white', hex: '#FBF8F2'),
    DesignColor(id: 'surface', name: 'White', hex: '#FFFFFF'),
    DesignColor(id: 'line', name: 'Lines', hex: '#E4DED2'),
  ];

  static final Set<String> builtInIds = {for (final c in defaultPalette) c.id};

  static const maxColors = 32;
  static const maxNameLength = 40;
  static const lineHeights = [1.4, 1.5, 1.6, 1.7, 1.8];

  /// Typography ranges (px). Each [FontSizeRange.standard] is the site's
  /// own size, used while nothing is set.
  static const bodyRange = FontSizeRange(12, 24, 16);
  static const headingRange = FontSizeRange(18, 48, 26);
  static const titleRange = FontSizeRange(24, 72, 44);
  static const titleMobileRange = FontSizeRange(20, 48, 32);
  static const navRange = FontSizeRange(12, 22, 15);
  static const buttonRange = FontSizeRange(12, 22, 14);

  final List<DesignColor> palette;

  /// Body text and descriptions (px), on every screen.
  final double bodySize;

  /// Section headings (px), on every screen.
  final double headingSize;
  final double lineHeight;

  /// Page titles and the largest headings (hero, page header), on wide
  /// screens and on phones (px); null: the site's own (44 and 32).
  final double? titleSize;
  final double? titleSizeMobile;

  /// The header's navigation links (px); null: the site's own (15).
  final double? navSize;

  /// Buttons on pages and in the header (px); null: the site's own.
  final double? buttonSize;

  /// Stored keys this version doesn't know, written back unchanged.
  final Map<String, Object?> preserved;

  static final _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// `#RRGGBB` as a colour, or null.
  static Color? parseHex(String value) {
    if (!_hex.hasMatch(value)) return null;
    return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
  }

  /// `#RRGGBB` for [color] (opaque).
  static String hexOf(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static bool isHex(String value) => _hex.hasMatch(value);

  /// A reference to palette colour [id].
  static String token(String id) => 'token:$id';

  /// The palette id [value] refers to, or null when it isn't a reference.
  static String? tokenId(String value) => value.startsWith('token:') ? value.substring(6) : null;

  /// Whether [value] is a colour a style can hold: a palette reference (to
  /// any id: a removed colour falls back) or `#RRGGBB`.
  static bool isColorValue(Object? value) => value is String && (isHex(value) || (tokenId(value)?.isNotEmpty ?? false));

  DesignColor? colorById(String id) {
    for (final c in palette) {
      if (c.id == id) return c;
    }
    for (final c in defaultPalette) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The colour [value] means: a palette colour, a `#RRGGBB` colour, or
  /// null (not set, malformed, or a removed palette colour).
  Color? resolve(Object? value) {
    if (value is! String) return null;
    if (isHex(value)) return parseHex(value);
    final id = tokenId(value);
    if (id == null) return null;
    for (final c in palette) {
      if (c.id == id) return c.color;
    }
    return null;
  }

  /// Palette colour [id] (the site's own colours always resolve).
  Color colorOf(String id) => colorById(id)?.color ?? const Color(0xFF000000);

  /// Who [value] is, for the editor: the palette colour's name, "Custom
  /// #RRGGBB", or null.
  String? describe(Object? value) {
    if (value is! String) return null;
    if (isHex(value)) return 'Custom ${value.toUpperCase()}';
    final id = tokenId(value);
    if (id == null) return null;
    for (final c in palette) {
      if (c.id == id) return c.name;
    }
    return 'Removed colour';
  }

  SiteDesign copyWith({
    List<DesignColor>? palette,
    double? bodySize,
    double? headingSize,
    double? lineHeight,
    double? Function()? titleSize,
    double? Function()? titleSizeMobile,
    double? Function()? navSize,
    double? Function()? buttonSize,
  }) =>
      SiteDesign(
        palette: palette ?? this.palette,
        bodySize: bodySize ?? this.bodySize,
        headingSize: headingSize ?? this.headingSize,
        lineHeight: lineHeight ?? this.lineHeight,
        titleSize: titleSize == null ? this.titleSize : titleSize(),
        titleSizeMobile: titleSizeMobile == null ? this.titleSizeMobile : titleSizeMobile(),
        navSize: navSize == null ? this.navSize : navSize(),
        buttonSize: buttonSize == null ? this.buttonSize : buttonSize(),
        preserved: preserved,
      );

  /// A page title's or hero's size: [titleSize] on wide screens,
  /// [titleSizeMobile] on phones, else the site's own.
  double titleSizeFor({required bool mobile}) => mobile ? titleSizeMobile ?? titleMobileRange.standard : titleSize ?? titleRange.standard;

  /// The page-title style ([PublicText.display] or its phone size) at this
  /// design's sizes.
  TextStyle titleStyle({required bool mobile}) => (mobile ? PublicText.displayMobile : PublicText.display).copyWith(fontSize: titleSizeFor(mobile: mobile));

  /// The header's navigation link style.
  TextStyle get navStyle => navSize == null ? PublicText.nav : PublicText.nav.copyWith(fontSize: navSize);

  /// Body text at this design's size and line height ([PublicText.body]).
  TextStyle get bodyStyle => PublicText.body.copyWith(fontSize: bodySize, height: lineHeight);

  /// A new palette colour id.
  static String newColorId() => 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  bool get isDefault => jsonEncode(toMap()) == jsonEncode(defaults.toMap());

  Map<String, dynamic> toMap() => {
        ...preserved,
        'palette': [for (final c in palette) c.toMap()],
        'bodySize': bodySize,
        'headingSize': headingSize,
        'lineHeight': lineHeight,
        'titleSize': ?titleSize,
        'titleSizeMobile': ?titleSizeMobile,
        'navSize': ?navSize,
        'buttonSize': ?buttonSize,
      };

  static const _keys = {'palette', 'bodySize', 'headingSize', 'lineHeight', 'titleSize', 'titleSizeMobile', 'navSize', 'buttonSize'};

  /// The design stored in [raw]; the defaults when there is none. Malformed
  /// colours are left out; the site's own colours are always present.
  static SiteDesign fromMap(Object? raw) {
    if (raw is! Map) return defaults;
    final stored = [for (final c in raw['palette'] is List ? raw['palette'] as List : const []) ?DesignColor.fromMap(c)];
    final ids = {for (final c in stored) c.id};
    final palette = [...stored, for (final c in defaultPalette) if (!ids.contains(c.id)) c];
    double number(Object? v, double fallback) => v is num ? v.toDouble() : fallback;
    double? optional(Object? v) => v is num ? v.toDouble() : null;
    return SiteDesign(
      palette: palette,
      bodySize: number(raw['bodySize'], 16),
      headingSize: number(raw['headingSize'], 26),
      lineHeight: number(raw['lineHeight'], 1.6),
      titleSize: optional(raw['titleSize']),
      titleSizeMobile: optional(raw['titleSizeMobile']),
      navSize: optional(raw['navSize']),
      buttonSize: optional(raw['buttonSize']),
      preserved: {for (final e in raw.entries) if (!_keys.contains(e.key)) e.key.toString(): e.value},
    );
  }

  /// Every problem that would stop this design being saved.
  List<String> validationErrors() {
    final errors = <String>[];
    if (palette.length > maxColors) errors.add('The palette can have at most $maxColors colours.');
    final ids = <String>{};
    for (final c in palette) {
      if (!ids.add(c.id)) errors.add('The colour “${c.name}” is listed twice.');
      if (c.name.trim().isEmpty) errors.add('Every colour needs a name.');
      if (c.name.trim().length > maxNameLength) errors.add('Colour names must be $maxNameLength characters or fewer.');
      if (!isHex(c.hex)) errors.add('“${c.name}”: enter the colour as # and six hexadecimal digits, for example #1F4D3A.');
    }
    for (final id in builtInIds) {
      if (!ids.contains(id)) errors.add('The site’s own colours can’t be removed.');
    }
    String range(String what, FontSizeRange r) => '$what: choose a whole number of pixels from ${r.min.round()} to ${r.max.round()}.';
    if (!bodyRange.allows(bodySize)) errors.add(range('Body text size', bodyRange));
    if (!headingRange.allows(headingSize)) errors.add(range('Section heading size', headingRange));
    for (final (what, value, r) in [
      ('Page title size', titleSize, titleRange),
      ('Page title size on phones', titleSizeMobile, titleMobileRange),
      ('Navigation text size', navSize, navRange),
      ('Button text size', buttonSize, buttonRange),
    ]) {
      if (value != null && !r.allows(value)) errors.add(range(what, r));
    }
    if (!lineHeights.contains(lineHeight)) errors.add('Choose a line height from the list.');
    return errors.toSet().toList();
  }
}

/// The design in force for the widgets below it (the published design on
/// the public site; the draft in the editors). Without one, the site's own
/// design.
class WebsiteDesignScope extends InheritedWidget {
  const WebsiteDesignScope({super.key, required this.design, required super.child});

  final SiteDesign design;

  static SiteDesign of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<WebsiteDesignScope>()?.design ?? SiteDesign.defaults;

  @override
  bool updateShouldNotify(WebsiteDesignScope oldWidget) => oldWidget.design != design && jsonEncode(oldWidget.design.toMap()) != jsonEncode(design.toMap());
}
