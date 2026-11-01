import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'website_content_models.dart';
import 'website_design.dart';

/// How the site header looks: shared by every page. Colours are palette
/// references or `#RRGGBB` ([SiteDesign]); unset means the site's own
/// look. Keys this version doesn't know are kept.
@immutable
class SiteHeaderStyle {
  const SiteHeaderStyle({
    this.background,
    this.linkColor,
    this.accentColor,
    this.brandColor,
    this.utilityBackground,
    this.utilityTextColor,
    this.utilityAlign = 'center',
    this.utilityVerticalAlign = 'center',
    this.utilityFontSize,
    this.utilityPaddingX,
    this.utilityPaddingY,
    this.utilitySpacing,
    this.navAlign = 'end',
    this.showLogo = true,
    this.height = 'normal',
    this.ctaLabel = const LocalizedText(),
    this.ctaTarget = '',
    this.ctaBackground,
    this.ctaTextColor,
    this.preserved = const {},
  });

  static const navAligns = ['end', 'center'];
  static const utilityAligns = ['start', 'center', 'end'];
  static const utilityVerticalAligns = ['top', 'center', 'bottom'];

  /// The top bar's ranges (px); each `standard` is today's look.
  static const utilityFontRange = FontSizeRange(11, 18, 13);
  static const utilityPaddingXRange = FontSizeRange(0, 48, 0);
  static const utilityPaddingYRange = FontSizeRange(0, 24, 6);
  static const utilitySpacingRange = FontSizeRange(0, 40, 12);
  static const heights = ['compact', 'normal', 'spacious'];
  static const maxCtaLabelLength = 40;

  final String? background;
  final String? linkColor;

  /// The current page's underline.
  final String? accentColor;

  /// The site name next to the logo.
  final String? brandColor;

  /// The slim bar above (language switch, login).
  final String? utilityBackground;

  /// Its login and logout text and icons (the language switch keeps its
  /// own pill colours, so it stays readable on any bar colour). Null: the
  /// site's own green, or white on a bar too dark for it.
  final String? utilityTextColor;

  /// Where its controls sit: `start`, `center` (today's) or `end`, and,
  /// when they differ in height, `top`, `center` (today's) or `bottom`.
  final String utilityAlign;
  final String utilityVerticalAlign;

  /// Its text size, extra space at the sides, space above and below, and
  /// between its controls (px); null: today's ([utilityFontRange] …).
  final double? utilityFontSize;
  final double? utilityPaddingX;
  final double? utilityPaddingY;
  final double? utilitySpacing;

  /// Where the links sit on wide screens: after the name (`end`), or
  /// centred between the name and the button.
  final String navAlign;
  final bool showLogo;

  /// The main row's height: compact, normal or spacious.
  final String height;

  /// An optional button at the end of the header (e.g. "Enquire now").
  final LocalizedText ctaLabel;

  /// Where it leads: a page of this website (`/admissions`,
  /// `/pages/open-day`), an https:// link, mailto: or tel:.
  final String ctaTarget;
  final String? ctaBackground;
  final String? ctaTextColor;
  final Map<String, Object?> preserved;

  bool get hasCta => ctaTarget.trim().isNotEmpty && ctaLabel.en.trim().isNotEmpty;

  static const _keys = {
    'background', 'linkColor', 'accentColor', 'brandColor', 'utilityBackground', 'navAlign', 'showLogo', 'height', 'ctaLabel', 'ctaTarget', 'ctaBackground', 'ctaTextColor', //
    'utilityTextColor', 'utilityAlign', 'utilityVerticalAlign', 'utilityFontSize', 'utilityPaddingX', 'utilityPaddingY', 'utilitySpacing',
  };

  static SiteHeaderStyle fromMap(Object? raw) {
    if (raw is! Map) return const SiteHeaderStyle();
    String? color(String key) => raw[key] is String && (raw[key] as String).isNotEmpty ? raw[key] as String : null;
    String choice(String key, List<String> options, String fallback) => options.contains(raw[key]) ? raw[key] as String : fallback;
    double? number(String key) => raw[key] is num ? (raw[key] as num).toDouble() : null;
    return SiteHeaderStyle(
      background: color('background'),
      linkColor: color('linkColor'),
      accentColor: color('accentColor'),
      brandColor: color('brandColor'),
      utilityBackground: color('utilityBackground'),
      utilityTextColor: color('utilityTextColor'),
      utilityAlign: choice('utilityAlign', utilityAligns, 'center'),
      utilityVerticalAlign: choice('utilityVerticalAlign', utilityVerticalAligns, 'center'),
      utilityFontSize: number('utilityFontSize'),
      utilityPaddingX: number('utilityPaddingX'),
      utilityPaddingY: number('utilityPaddingY'),
      utilitySpacing: number('utilitySpacing'),
      navAlign: choice('navAlign', navAligns, 'end'),
      showLogo: raw['showLogo'] != false,
      height: choice('height', heights, 'normal'),
      ctaLabel: LocalizedText.fromMap(raw['ctaLabel']),
      ctaTarget: raw['ctaTarget']?.toString() ?? '',
      ctaBackground: color('ctaBackground'),
      ctaTextColor: color('ctaTextColor'),
      preserved: {for (final e in raw.entries) if (!_keys.contains(e.key)) e.key.toString(): e.value},
    );
  }

  Map<String, dynamic> toMap() => {
        ...preserved,
        'background': ?background,
        'linkColor': ?linkColor,
        'accentColor': ?accentColor,
        'brandColor': ?brandColor,
        'utilityBackground': ?utilityBackground,
        'utilityTextColor': ?utilityTextColor,
        // Written only when changed, so a header saved before these
        // existed is stored exactly as before.
        if (utilityAlign != 'center') 'utilityAlign': utilityAlign,
        if (utilityVerticalAlign != 'center') 'utilityVerticalAlign': utilityVerticalAlign,
        'utilityFontSize': ?utilityFontSize,
        'utilityPaddingX': ?utilityPaddingX,
        'utilityPaddingY': ?utilityPaddingY,
        'utilitySpacing': ?utilitySpacing,
        'navAlign': navAlign,
        'showLogo': showLogo,
        'height': height,
        if (!ctaLabel.isEmpty) 'ctaLabel': ctaLabel.toMap(),
        if (ctaTarget.trim().isNotEmpty) 'ctaTarget': ctaTarget.trim(),
        'ctaBackground': ?ctaBackground,
        'ctaTextColor': ?ctaTextColor,
      };

  bool get isDefault => jsonEncode(toMap()) == jsonEncode(const SiteHeaderStyle().toMap());

  SiteHeaderStyle copyWith({
    String? Function()? background,
    String? Function()? linkColor,
    String? Function()? accentColor,
    String? Function()? brandColor,
    String? Function()? utilityBackground,
    String? Function()? utilityTextColor,
    String? utilityAlign,
    String? utilityVerticalAlign,
    double? Function()? utilityFontSize,
    double? Function()? utilityPaddingX,
    double? Function()? utilityPaddingY,
    double? Function()? utilitySpacing,
    String? navAlign,
    bool? showLogo,
    String? height,
    LocalizedText? ctaLabel,
    String? ctaTarget,
    String? Function()? ctaBackground,
    String? Function()? ctaTextColor,
  }) =>
      SiteHeaderStyle(
        background: background == null ? this.background : background(),
        linkColor: linkColor == null ? this.linkColor : linkColor(),
        accentColor: accentColor == null ? this.accentColor : accentColor(),
        brandColor: brandColor == null ? this.brandColor : brandColor(),
        utilityBackground: utilityBackground == null ? this.utilityBackground : utilityBackground(),
        utilityTextColor: utilityTextColor == null ? this.utilityTextColor : utilityTextColor(),
        utilityAlign: utilityAlign ?? this.utilityAlign,
        utilityVerticalAlign: utilityVerticalAlign ?? this.utilityVerticalAlign,
        utilityFontSize: utilityFontSize == null ? this.utilityFontSize : utilityFontSize(),
        utilityPaddingX: utilityPaddingX == null ? this.utilityPaddingX : utilityPaddingX(),
        utilityPaddingY: utilityPaddingY == null ? this.utilityPaddingY : utilityPaddingY(),
        utilitySpacing: utilitySpacing == null ? this.utilitySpacing : utilitySpacing(),
        navAlign: navAlign ?? this.navAlign,
        showLogo: showLogo ?? this.showLogo,
        height: height ?? this.height,
        ctaLabel: ctaLabel ?? this.ctaLabel,
        ctaTarget: ctaTarget ?? this.ctaTarget,
        ctaBackground: ctaBackground == null ? this.ctaBackground : ctaBackground(),
        ctaTextColor: ctaTextColor == null ? this.ctaTextColor : ctaTextColor(),
        preserved: preserved,
      );

  /// Problems with these settings; [validateLink] checks the button's
  /// target (returns a message, or null when it is allowed).
  List<String> validationErrors(String? Function(String target) validateLink) {
    final errors = <String>[];
    for (final (name, value) in [
      ('background', background),
      ('link colour', linkColor),
      ('current page colour', accentColor),
      ('site name colour', brandColor),
      ('top bar colour', utilityBackground),
      ('top bar text colour', utilityTextColor),
      ('button colour', ctaBackground),
      ('button text colour', ctaTextColor),
    ]) {
      if (value != null && !SiteDesign.isColorValue(value)) errors.add('Header $name: choose a colour from the palette or enter #RRGGBB.');
    }
    for (final (name, value, range) in [
      ('text size', utilityFontSize, utilityFontRange),
      ('side padding', utilityPaddingX, utilityPaddingXRange),
      ('top and bottom padding', utilityPaddingY, utilityPaddingYRange),
      ('space between controls', utilitySpacing, utilitySpacingRange),
    ]) {
      if (value != null && !range.allows(value)) errors.add('Top bar $name: choose a whole number of pixels from ${range.min.round()} to ${range.max.round()}.');
    }
    errors.addAll(ctaLabel.problems(maxCtaLabelLength, 'The header button label'));
    if (ctaTarget.trim().isNotEmpty) {
      if (ctaLabel.en.trim().isEmpty) errors.add('Enter an English label for the header button.');
      if (validateLink(ctaTarget.trim()) case final error?) errors.add('Header button: $error');
    } else if (!ctaLabel.isEmpty) {
      errors.add('Choose where the header button leads, or clear its label.');
    }
    return errors;
  }
}

/// How the site footer looks, and the school's contact details shown in
/// it: shared by every page.
@immutable
class SiteFooterStyle {
  const SiteFooterStyle({
    this.background,
    this.textColor,
    this.linkColor,
    this.headingColor,
    this.align = 'start',
    this.address = const LocalizedText(),
    this.phone = '',
    this.email = '',
    this.preserved = const {},
  });

  static const aligns = ['start', 'center'];
  static const maxAddressLength = 300;
  static final _phone = RegExp(r'^\+?[0-9 ()-]{6,20}$');
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  final String? background;
  final String? textColor;
  final String? linkColor;

  /// The site name in the footer.
  final String? headingColor;
  final String align;
  final LocalizedText address;
  final String phone;
  final String email;
  final Map<String, Object?> preserved;

  bool get hasContact => !address.isEmpty || phone.trim().isNotEmpty || email.trim().isNotEmpty;

  static const _keys = {'background', 'textColor', 'linkColor', 'headingColor', 'align', 'address', 'phone', 'email'};

  static SiteFooterStyle fromMap(Object? raw) {
    if (raw is! Map) return const SiteFooterStyle();
    String? color(String key) => raw[key] is String && (raw[key] as String).isNotEmpty ? raw[key] as String : null;
    return SiteFooterStyle(
      background: color('background'),
      textColor: color('textColor'),
      linkColor: color('linkColor'),
      headingColor: color('headingColor'),
      align: aligns.contains(raw['align']) ? raw['align'] as String : 'start',
      address: LocalizedText.fromMap(raw['address']),
      phone: raw['phone']?.toString() ?? '',
      email: raw['email']?.toString() ?? '',
      preserved: {for (final e in raw.entries) if (!_keys.contains(e.key)) e.key.toString(): e.value},
    );
  }

  Map<String, dynamic> toMap() => {
        ...preserved,
        'background': ?background,
        'textColor': ?textColor,
        'linkColor': ?linkColor,
        'headingColor': ?headingColor,
        'align': align,
        if (!address.isEmpty) 'address': address.toMap(),
        if (phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (email.trim().isNotEmpty) 'email': email.trim(),
      };

  bool get isDefault => jsonEncode(toMap()) == jsonEncode(const SiteFooterStyle().toMap());

  SiteFooterStyle copyWith({
    String? Function()? background,
    String? Function()? textColor,
    String? Function()? linkColor,
    String? Function()? headingColor,
    String? align,
    LocalizedText? address,
    String? phone,
    String? email,
  }) =>
      SiteFooterStyle(
        background: background == null ? this.background : background(),
        textColor: textColor == null ? this.textColor : textColor(),
        linkColor: linkColor == null ? this.linkColor : linkColor(),
        headingColor: headingColor == null ? this.headingColor : headingColor(),
        align: align ?? this.align,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        preserved: preserved,
      );

  List<String> validationErrors() {
    final errors = <String>[];
    for (final (name, value) in [('background', background), ('text colour', textColor), ('link colour', linkColor), ('site name colour', headingColor)]) {
      if (value != null && !SiteDesign.isColorValue(value)) errors.add('Footer $name: choose a colour from the palette or enter #RRGGBB.');
    }
    errors.addAll(address.problems(maxAddressLength, 'The footer address'));
    if (phone.trim().isNotEmpty && !_phone.hasMatch(phone.trim())) errors.add('Enter the phone number with digits only (spaces, +, - and brackets allowed).');
    if (email.trim().isNotEmpty && !_email.hasMatch(email.trim())) errors.add('Enter a valid email address, for example office@example.org.');
    return errors;
  }
}
