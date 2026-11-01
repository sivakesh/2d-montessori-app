import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../public_routes.dart';
import '../public_strings.dart';

/// One language of the website's language registry.
@immutable
class SiteLanguage {
  const SiteLanguage({
    required this.code,
    required this.nativeName,
    required this.englishName,
    this.enabled = false,
    this.isPublic = false,
  });

  /// Null when [map] isn't a usable entry (it is then left out).
  static SiteLanguage? fromMap(Object? map) {
    if (map is! Map) return null;
    final code = map['code'];
    final nativeName = map['nativeName'];
    if (code is! String || code.isEmpty || nativeName is! String) return null;
    return SiteLanguage(
      code: code,
      nativeName: nativeName,
      englishName: map['englishName']?.toString() ?? code,
      enabled: map['enabled'] == true,
      isPublic: map['public'] == true,
    );
  }

  /// `en`, `ta`, `hi`, `pt-BR`, …
  final String code;

  /// The language's name in itself (shown on the public switch).
  final String nativeName;
  final String englishName;

  /// Offered in the website editors.
  final bool enabled;

  /// Offered in the public language switch (only when also [enabled]).
  final bool isPublic;

  /// Shown to visitors: enabled and public.
  bool get isVisible => enabled && isPublic;

  SiteLanguage copyWith({String? nativeName, String? englishName, bool? enabled, bool? isPublic}) => SiteLanguage(
        code: code,
        nativeName: nativeName ?? this.nativeName,
        englishName: englishName ?? this.englishName,
        enabled: enabled ?? this.enabled,
        isPublic: isPublic ?? this.isPublic,
      );

  Map<String, dynamic> toMap() => {'code': code, 'nativeName': nativeName.trim(), 'englishName': englishName.trim(), 'enabled': enabled, 'public': isPublic};

  /// This language for the public site, with the registry's fallback.
  PublicLanguage toPublic(String fallbackCode) {
    if (code == PublicLanguage.english.code) return PublicLanguage.english;
    final base = code == PublicLanguage.tamil.code
        ? PublicLanguage.tamil
        : PublicLanguage(code, nativeName: nativeName.trim(), englishName: englishName.trim());
    return base.withFallback(fallbackCode == code ? PublicLanguage.sourceCode : fallbackCode);
  }
}

/// The website's languages: which exist, which admins can edit (enabled)
/// and which visitors can choose (enabled and public), their order, and the
/// fallback language for text that isn't available in a visitor's language.
/// English is always the source language. Stored as one document,
/// `site_languages`, in the page drafts and live pages collections (read
/// with the live pages, no extra read). Turning a language off never
/// deletes text written in it. With nothing usable published, visitors get
/// English and Tamil, as before.
@immutable
class SiteLanguageRegistry {
  const SiteLanguageRegistry({required this.languages, this.fallbackCode = PublicLanguage.sourceCode});

  static const docId = 'site_languages';
  static const kind = 'languages';
  static const schemaVersion = 1;
  static const maxLanguages = 20;
  static const maxNameLength = 40;

  /// The initial registry: English and Tamil enabled and public; Hindi,
  /// Malayalam, Telugu, Kannada and French listed but off.
  static const defaults = SiteLanguageRegistry(languages: [
    SiteLanguage(code: 'en', nativeName: 'English', englishName: 'English', enabled: true, isPublic: true),
    SiteLanguage(code: 'ta', nativeName: 'தமிழ்', englishName: 'Tamil', enabled: true, isPublic: true),
    SiteLanguage(code: 'hi', nativeName: 'हिन्दी', englishName: 'Hindi'),
    SiteLanguage(code: 'ml', nativeName: 'മലയാളം', englishName: 'Malayalam'),
    SiteLanguage(code: 'te', nativeName: 'తెలుగు', englishName: 'Telugu'),
    SiteLanguage(code: 'kn', nativeName: 'ಕನ್ನಡ', englishName: 'Kannada'),
    SiteLanguage(code: 'fr', nativeName: 'Français', englishName: 'French'),
  ]);

  /// The registry in [data], or null when it can't be used safely (not a
  /// registry, an unknown version, the wrong shapes, or invalid — e.g. no
  /// English, or a fallback visitors can't see). Malformed entries are left
  /// out before validating.
  static SiteLanguageRegistry? tryParse(Object? data) {
    try {
      if (data is! Map) return null;
      if (data['kind'] != kind || data['schemaVersion'] != schemaVersion) return null;
      if (data['source'] != PublicLanguage.sourceCode) return null;
      final list = data['languages'];
      final fallback = data['fallback'];
      if (list is! List || fallback is! String) return null;
      final registry = SiteLanguageRegistry(languages: [for (final item in list) ?SiteLanguage.fromMap(item)], fallbackCode: fallback);
      return registry.validationErrors().isEmpty ? registry : null;
    } catch (_) {
      return null;
    }
  }

  /// In order: the order of the public switch and the editors.
  final List<SiteLanguage> languages;
  final String fallbackCode;

  SiteLanguage? byCode(String code) {
    for (final l in languages) {
      if (l.code == code) return l;
    }
    return null;
  }

  /// Languages the editors offer, in order.
  List<SiteLanguage> get enabled => [for (final l in languages) if (l.enabled) l];

  /// The visitors' languages, in order, each falling back to [fallbackCode].
  List<PublicLanguage> get publicLanguages => [for (final l in languages) if (l.isVisible) l.toPublic(fallbackCode)];

  /// The editors' languages as [PublicLanguage]s (for previews).
  List<PublicLanguage> get editorLanguages => [for (final l in enabled) l.toPublic(fallbackCode)];

  SiteLanguageRegistry copyWith({List<SiteLanguage>? languages, String? fallbackCode}) =>
      SiteLanguageRegistry(languages: languages ?? this.languages, fallbackCode: fallbackCode ?? this.fallbackCode);

  /// Visitor-facing fields only.
  Map<String, dynamic> toMap() => {
        'kind': kind,
        'schemaVersion': schemaVersion,
        'source': PublicLanguage.sourceCode,
        'fallback': fallbackCode,
        'languages': [for (final l in languages) l.toMap()],
      };

  bool sameContentAs(SiteLanguageRegistry? other) => other != null && jsonEncode(toMap()) == jsonEncode(other.toMap());

  static final _codePattern = RegExp(r'^[a-z]{2,3}(-[A-Z]{2})?$');

  /// Null when [code] can be a language code: 2–3 lowercase letters,
  /// optionally a region (`pt-BR`), and never a word the website's routes
  /// use (`app`, `otp`, …), so a future `/<code>/…` address can't collide
  /// with a page or a protected route.
  static String? validateCode(String code) {
    if (!_codePattern.hasMatch(code)) return 'Use a 2–3 letter lowercase language code, optionally with a region (for example hi or pt-BR).';
    final route = '/${code.toLowerCase()}';
    if (PublicRoutes.isReserved(route) || PublicRoutes.sections.contains(route) || code.toLowerCase() == 'pages') {
      return '“$code” is used by the website’s own addresses and can’t be a language code.';
    }
    return null;
  }

  /// Every problem that would stop this registry being saved, in order.
  List<String> validationErrors() {
    final errors = <String>[];
    if (languages.length > maxLanguages) errors.add('At most $maxLanguages languages.');
    final codes = <String>{};
    for (final l in languages) {
      final codeError = validateCode(l.code);
      if (codeError != null) errors.add(codeError);
      if (!codes.add(l.code.toLowerCase())) errors.add('The language code “${l.code}” is listed twice.');
      if (l.nativeName.trim().isEmpty) errors.add('${l.code}: enter the language’s own name.');
      if (l.nativeName.trim().length > maxNameLength || l.englishName.trim().length > maxNameLength) {
        errors.add('${l.code}: names must be $maxNameLength characters or fewer.');
      }
    }
    final english = byCode(PublicLanguage.sourceCode);
    if (english == null || !english.isVisible) errors.add('English is the source language and must stay enabled and public.');
    final fallback = byCode(fallbackCode);
    if (fallback == null || !fallback.isVisible) errors.add('The fallback language must be enabled and public.');
    return errors;
  }
}
