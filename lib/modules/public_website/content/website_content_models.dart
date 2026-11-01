import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';

import '../public_routes.dart';
import '../public_strings.dart';

/// Firestore collections behind the public website's managed content.
///
/// - [media]: the media library — one document per uploaded image (its
///   Storage files, size, alt text, caption, category, gallery order and
///   publication status). Only documents with `status == 'published'` are
///   meant to be publicly readable.
/// - [pageDrafts]: each page's editable content (admin only, never public).
/// - [livePages]: each page's published content, copied from the draft when
///   an admin publishes it; removed when the page is unpublished. Holds only
///   what visitors may see.
///
/// Image files live in Storage under `website_media/{mediaId}/...`; a page
/// refers to an image by its media id, so one upload can be reused on
/// several pages and in the gallery.
class WebsiteCollections {
  static const media = 'website_media';
  static const pageDrafts = 'website_page_drafts';
  static const livePages = 'website_pages';
}

/// Text in English (the source language) and, optionally, other
/// languages: Tamil in [ta], any other language (`hi`, `ml`, `fr`, … or a
/// code added later) in [others]. Every language read from a record is
/// written back unchanged, so saving English or Tamil never drops text in
/// another language — even one this version of the app doesn't offer yet.
@immutable
class LocalizedText {
  const LocalizedText({this.en = '', this.ta = '', this.others = const {}});

  factory LocalizedText.fromMap(Object? value) {
    if (value is Map) {
      final others = <String, String>{
        for (final entry in value.entries)
          if (entry.key is String && entry.key != 'en' && entry.key != 'ta' && entry.value is String) entry.key as String: entry.value as String,
      };
      return LocalizedText(en: value['en']?.toString() ?? '', ta: value['ta']?.toString() ?? '', others: others);
    }
    // Tolerate a plain string (English only).
    if (value is String) return LocalizedText(en: value);
    return const LocalizedText();
  }

  final String en;
  final String ta;

  /// Text in languages other than English and Tamil, by language code.
  /// Never holds `en` or `ta`.
  final Map<String, String> others;

  /// Every language's text, by code (English and Tamil always present).
  Map<String, String> get values => {'en': en, 'ta': ta, ...others};

  /// The text in language [code] ('' when none).
  String textFor(String code) => switch (code) { 'en' => en, 'ta' => ta, _ => others[code] ?? '' };

  /// This text with language [code] set to [text]; other languages kept.
  LocalizedText withText(String code, String text) => switch (code) {
        'en' => LocalizedText(en: text, ta: ta, others: others),
        'ta' => LocalizedText(en: en, ta: text, others: others),
        _ => LocalizedText(en: en, ta: ta, others: {...others, code: text}),
      };

  /// This text with English and/or Tamil replaced; other languages kept.
  LocalizedText copyWith({String? en, String? ta}) => LocalizedText(en: en ?? this.en, ta: ta ?? this.ta, others: others);

  bool get isEmpty => values.values.every((t) => t.trim().isEmpty);

  /// The text for [language]: its own text when entered, otherwise its
  /// fallback language's, otherwise English (so a page never mixes managed
  /// English text with an unrelated bundled default). Empty when none was
  /// entered.
  String resolve(PublicLanguage language) {
    final own = textFor(language.code).trim();
    if (own.isNotEmpty) return own;
    if (language.fallbackCode != PublicLanguage.sourceCode) {
      final fallback = textFor(language.fallbackCode).trim();
      if (fallback.isNotEmpty) return fallback;
    }
    return en.trim();
  }

  /// English and Tamil always, then any other language (sorted by code).
  Map<String, String> toMap() => {
        'en': en.trim(),
        'ta': ta.trim(),
        for (final code in others.keys.toList()..sort()) code: others[code]!.trim(),
      };

  /// Same text in every language, ignoring surrounding whitespace (a
  /// language that is missing counts as empty).
  bool sameTextAs(LocalizedText other) {
    final a = values;
    final b = other.values;
    return {...a.keys, ...b.keys}.every((code) => (a[code] ?? '').trim() == (b[code] ?? '').trim());
  }

  LocalizedText trimmed() => LocalizedText(en: en.trim(), ta: ta.trim(), others: {for (final e in others.entries) e.key: e.value.trim()});

  /// The English name of a language that has text while English (the
  /// source) has none, or null.
  String? get languageMissingSource {
    if (en.trim().isNotEmpty) return null;
    for (final e in values.entries) {
      if (e.key != PublicLanguage.sourceCode && e.value.trim().isNotEmpty) return languageNameFor(e.key);
    }
    return null;
  }

  /// Problems with this text as a field of at most [max] characters per
  /// language, named [what]: too long in any language, or text in another
  /// language without the English (source) text.
  List<String> problems(int max, String what) => [
        if (values.values.any((t) => t.trim().length > max)) '$what must be $max characters or fewer.',
        if (languageMissingSource case final name?) '$what: enter the English text as well as the $name text.',
      ];

  @override
  bool operator ==(Object other) => other is LocalizedText && mapEquals(other.values, values);

  @override
  int get hashCode => Object.hashAllUnordered([for (final e in values.entries) Object.hash(e.key, e.value)]);
}

/// The English name of language [code] for admin messages ("Tamil",
/// "Hindi", …), or the code itself when it isn't a known language.
String languageNameFor(String code) => const {
      'en': 'English',
      'ta': 'Tamil',
      'hi': 'Hindi',
      'ml': 'Malayalam',
      'te': 'Telugu',
      'kn': 'Kannada',
      'fr': 'French',
    }[code] ??
    code;

enum WebsiteMediaStatus {
  /// Uploaded, not visible on the website.
  draft,

  /// Visible wherever it is used (gallery and/or pages).
  published,

  /// Taken off the website (was published); kept in the library.
  hidden;

  static WebsiteMediaStatus parse(Object? value) =>
      WebsiteMediaStatus.values.firstWhere((s) => s.name == value, orElse: () => WebsiteMediaStatus.draft);
}

/// Gallery filter categories. Only categories that have published gallery
/// photographs are offered to visitors, so an unused category never implies
/// anything about the school. Tamil labels should be reviewed by a native
/// speaker.
enum GalleryCategory {
  general('general', 'General', 'பொது'),
  classroom('classroom', 'Classroom', 'வகுப்பறை'),
  materials('materials', 'Montessori materials', 'மாண்டிசோரி உபகரணங்கள்'),
  outdoors('outdoors', 'Outdoors', 'வெளிப்புறம்'),
  events('events', 'Events', 'நிகழ்வுகள்'),
  teacherTraining('teacher_training', 'Teacher training', 'ஆசிரியர் பயிற்சி'),
  campus('campus', 'Campus', 'வளாகம்');

  const GalleryCategory(this.id, this.en, this.ta);

  final String id;
  final String en;
  final String ta;

  String label(PublicLanguage language) => language == PublicLanguage.tamil ? ta : en;

  static GalleryCategory parse(Object? value) =>
      GalleryCategory.values.firstWhere((c) => c.id == value, orElse: () => GalleryCategory.general);
}

/// One image in the media library. A published record is publicly
/// readable, so it holds only what the website needs: no uploader or
/// editor identity and no original file name (which could name a child).
/// Who changed what is kept in the admin-only `audit` subcollection.
@immutable
class WebsiteMedia {
  const WebsiteMedia({
    required this.id,
    required this.url,
    required this.storagePath,
    this.thumbUrl = '',
    this.thumbStoragePath = '',
    this.contentType = 'image/jpeg',
    this.sizeBytes = 0,
    this.width = 0,
    this.height = 0,
    this.focalX = 0.5,
    this.focalY = 0.5,
    this.alt = const LocalizedText(),
    this.caption = const LocalizedText(),
    this.category = GalleryCategory.general,
    this.status = WebsiteMediaStatus.draft,
    this.inGallery = true,
    this.galleryOrder = 0,
    this.consentConfirmed = false,
    this.updatedAt,
  });

  factory WebsiteMedia.fromMap(String id, Map<String, dynamic> map) {
    double fraction(Object? v) => v is num ? v.toDouble().clamp(0.0, 1.0) : 0.5;
    int number(Object? v) => v is num ? v.toInt() : 0;
    final updatedAt = map['updatedAt'];
    return WebsiteMedia(
      id: id,
      url: map['url']?.toString() ?? '',
      storagePath: map['storagePath']?.toString() ?? '',
      thumbUrl: map['thumbUrl']?.toString() ?? '',
      thumbStoragePath: map['thumbStoragePath']?.toString() ?? '',
      contentType: map['contentType']?.toString() ?? 'image/jpeg',
      sizeBytes: number(map['sizeBytes']),
      width: number(map['width']),
      height: number(map['height']),
      focalX: fraction(map['focalX']),
      focalY: fraction(map['focalY']),
      alt: LocalizedText.fromMap(map['alt']),
      caption: LocalizedText.fromMap(map['caption']),
      category: GalleryCategory.parse(map['category']),
      status: WebsiteMediaStatus.parse(map['status']),
      inGallery: map['inGallery'] != false,
      galleryOrder: number(map['galleryOrder']),
      consentConfirmed: map['consentConfirmed'] == true,
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }

  final String id;

  /// Download URL of the display-size image (long edge at most
  /// [WebsiteImageSizes.display] px when resized on upload).
  final String url;
  final String storagePath;

  /// Download URL of the small grid/thumbnail image; empty means use [url].
  final String thumbUrl;
  final String thumbStoragePath;
  final String contentType;
  final int sizeBytes;

  /// Pixel size of the display image (0 when unknown).
  final int width;
  final int height;

  /// Point of interest, as fractions of width/height (0.5, 0.5 = centre),
  /// kept in view when the image is cropped to a different aspect ratio.
  final double focalX;
  final double focalY;
  final LocalizedText alt;
  final LocalizedText caption;
  final GalleryCategory category;
  final WebsiteMediaStatus status;

  /// Listed in the public gallery (when published). An image can be used on
  /// a page without appearing in the gallery.
  final bool inGallery;
  final int galleryOrder;

  /// The admin confirmed the photograph is school-approved and that consent
  /// was obtained for any identifiable children. Required to publish.
  final bool consentConfirmed;
  final DateTime? updatedAt;

  bool get isPublished => status == WebsiteMediaStatus.published;

  /// This image with a different focal point (for previews while editing).
  WebsiteMedia withFocal(double x, double y) => WebsiteMedia(
        id: id,
        url: url,
        storagePath: storagePath,
        thumbUrl: thumbUrl,
        thumbStoragePath: thumbStoragePath,
        contentType: contentType,
        sizeBytes: sizeBytes,
        width: width,
        height: height,
        focalX: x.clamp(0.0, 1.0),
        focalY: y.clamp(0.0, 1.0),
        alt: alt,
        caption: caption,
        category: category,
        status: status,
        inGallery: inGallery,
        galleryOrder: galleryOrder,
        consentConfirmed: consentConfirmed,
        updatedAt: updatedAt,
      );

  /// Width / height, or 4:3 when unknown.
  double get aspectRatio => width > 0 && height > 0 ? width / height : 4 / 3;

  /// [focalX]/[focalY] as an [Alignment] for `BoxFit.cover` cropping.
  Alignment get alignment => Alignment(focalX * 2 - 1, focalY * 2 - 1);

  /// The smallest stored image that still covers [physicalWidth] pixels.
  String urlForWidth(double physicalWidth) {
    if (thumbUrl.isNotEmpty && physicalWidth <= WebsiteImageSizes.thumb) return thumbUrl;
    return url;
  }

  /// Why this image can't be published yet, or null when it can.
  String? get publishBlocker {
    if (url.isEmpty) return 'The image file is missing.';
    if (alt.en.trim().isEmpty) return 'Add English alt text describing the image.';
    if (!consentConfirmed) return 'Confirm the photograph is approved and consent has been obtained.';
    return null;
  }
}

/// Pixel limits for the images stored on upload (long edge).
class WebsiteImageSizes {
  static const display = 2000;
  static const thumb = 640;
}

/// The website places whose image and text can be managed.
enum WebsitePageSlot {
  home('home', PublicRoutes.home, 'Homepage hero'),
  admissions('admissions', PublicRoutes.admissions, 'Admissions'),
  teacherTraining('teacher_training', PublicRoutes.teacherTraining, 'Teacher Training'),
  programs('programs', PublicRoutes.programs, 'Programs'),
  gallery('gallery', PublicRoutes.gallery, 'Gallery');

  const WebsitePageSlot(this.id, this.route, this.adminLabel);

  /// Document id in [WebsiteCollections.pageDrafts]/[WebsiteCollections.livePages].
  final String id;
  final String route;
  final String adminLabel;

  /// The site's own heading for this place, in English and Tamil (the
  /// exact built-in copy from [PublicStrings]).
  LocalizedText get builtInHeadline {
    final en = PublicStrings.of(PublicLanguage.english);
    final ta = PublicStrings.of(PublicLanguage.tamil);
    return this == home
        ? LocalizedText(en: en.heroTitle, ta: ta.heroTitle)
        : LocalizedText(en: en.labelFor(route), ta: ta.labelFor(route));
  }

  /// The site's own introduction for this place, in English and Tamil.
  LocalizedText get builtInIntro {
    final en = PublicStrings.of(PublicLanguage.english);
    final ta = PublicStrings.of(PublicLanguage.tamil);
    return this == home
        ? LocalizedText(en: en.heroBody, ta: ta.heroBody)
        : LocalizedText(en: en.introFor(route), ta: ta.introFor(route));
  }

  static WebsitePageSlot? forRoute(String route) {
    for (final slot in values) {
      if (slot.route == route) return slot;
    }
    return null;
  }

  static WebsitePageSlot? parse(String id) {
    for (final slot in values) {
      if (slot.id == id) return slot;
    }
    return null;
  }
}

/// A page's managed image and text. Blank text means "use the site's
/// built-in wording"; no image means "use the built-in placeholder".
@immutable
class WebsitePageContent {
  const WebsitePageContent({
    required this.slot,
    this.imageMediaId,
    this.headline = const LocalizedText(),
    this.intro = const LocalizedText(),
    this.updatedAt,
    this.publishedAt,
    this.updatedByName = '',
  });

  factory WebsitePageContent.fromMap(WebsitePageSlot slot, Map<String, dynamic> map) {
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    final imageId = map['imageMediaId']?.toString() ?? '';
    return WebsitePageContent(
      slot: slot,
      imageMediaId: imageId.isEmpty ? null : imageId,
      headline: LocalizedText.fromMap(map['headline']),
      intro: LocalizedText.fromMap(map['intro']),
      updatedAt: date(map['updatedAt']),
      publishedAt: date(map['publishedAt']),
      updatedByName: map['updatedByName']?.toString() ?? '',
    );
  }

  final WebsitePageSlot slot;
  final String? imageMediaId;
  final LocalizedText headline;
  final LocalizedText intro;
  final DateTime? updatedAt;
  final DateTime? publishedAt;
  final String updatedByName;

  WebsitePageContent copyWith({
    String? Function()? imageMediaId,
    LocalizedText? headline,
    LocalizedText? intro,
  }) =>
      WebsitePageContent(
        slot: slot,
        imageMediaId: imageMediaId == null ? this.imageMediaId : imageMediaId(),
        headline: headline ?? this.headline,
        intro: intro ?? this.intro,
        updatedAt: updatedAt,
        publishedAt: publishedAt,
        updatedByName: updatedByName,
      );

  /// The visitor-facing fields only (no editor bookkeeping). `mediaIds`
  /// lists every image the page uses, for the library's usage checks.
  Map<String, dynamic> toContentMap() => {
        'slot': slot.id,
        'imageMediaId': imageMediaId ?? '',
        'mediaIds': [?imageMediaId],
        'headline': headline.toMap(),
        'intro': intro.toMap(),
      };

  /// Text that is exactly the built-in copy (both languages) is stored
  /// blank, meaning "use the built-in wording", so the page keeps following
  /// the site's own copy if that is ever revised.
  WebsitePageContent normalized() => copyWith(
        headline: headline.sameTextAs(slot.builtInHeadline) ? const LocalizedText() : headline,
        intro: intro.sameTextAs(slot.builtInIntro) ? const LocalizedText() : intro,
      );

  /// Same visible content as [other] (ignores timestamps).
  bool sameContentAs(WebsitePageContent? other) =>
      other != null &&
      other.imageMediaId == imageMediaId &&
      other.headline.sameTextAs(headline) &&
      other.intro.sameTextAs(intro);
}
