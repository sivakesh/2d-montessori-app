import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../public_routes.dart';
import 'blocks/block_registry.dart';
import 'blocks/legacy_sections.dart';
import 'blocks/website_block.dart';
import 'website_content_models.dart';

/// The kinds of content block an additional page can contain.
enum CustomSectionType {
  text('text', 'Text'),
  imageText('image_text', 'Image with text'),
  imageGrid('image_grid', 'Image grid'),
  callToAction('cta', 'Call to action');

  const CustomSectionType(this.id, this.adminLabel);

  final String id;
  final String adminLabel;

  static CustomSectionType parse(Object? value) =>
      CustomSectionType.values.firstWhere((t) => t.id == value, orElse: () => CustomSectionType.text);
}

/// One content block of an additional page. Which fields apply depends on
/// [type]: text uses heading/body; image-with-text adds [mediaId] and
/// [imageOnRight]; an image grid uses heading and [mediaIds]; a call to
/// action uses heading/body plus [buttonLabel] and [target].
@immutable
class CustomPageSection {
  const CustomPageSection({
    required this.id,
    required this.type,
    this.heading = const LocalizedText(),
    this.body = const LocalizedText(),
    this.mediaId,
    this.mediaIds = const [],
    this.imageOnRight = false,
    this.buttonLabel = const LocalizedText(),
    this.target = '',
  });

  factory CustomPageSection.fromMap(Map<String, dynamic> map) {
    final mediaId = map['mediaId']?.toString() ?? '';
    final ids = map['mediaIds'];
    return CustomPageSection(
      id: map['id']?.toString() ?? '',
      type: CustomSectionType.parse(map['type']),
      heading: LocalizedText.fromMap(map['heading']),
      body: LocalizedText.fromMap(map['body']),
      mediaId: mediaId.isEmpty ? null : mediaId,
      mediaIds: ids is List ? [for (final id in ids) id.toString()] : const [],
      imageOnRight: map['imageOnRight'] == true,
      buttonLabel: LocalizedText.fromMap(map['buttonLabel']),
      target: map['target']?.toString() ?? '',
    );
  }

  /// A new, empty block of [type].
  factory CustomPageSection.create(CustomSectionType type) =>
      CustomPageSection(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), type: type);

  final String id;
  final CustomSectionType type;
  final LocalizedText heading;
  final LocalizedText body;
  final String? mediaId;
  final List<String> mediaIds;
  final bool imageOnRight;
  final LocalizedText buttonLabel;
  final String target;

  /// Every image this block shows.
  List<String> get referencedMedia => switch (type) {
        CustomSectionType.imageText => [?mediaId],
        CustomSectionType.imageGrid => mediaIds,
        _ => const [],
      };

  CustomPageSection copyWith({
    LocalizedText? heading,
    LocalizedText? body,
    String? Function()? mediaId,
    List<String>? mediaIds,
    bool? imageOnRight,
    LocalizedText? buttonLabel,
    String? target,
  }) =>
      CustomPageSection(
        id: id,
        type: type,
        heading: heading ?? this.heading,
        body: body ?? this.body,
        mediaId: mediaId == null ? this.mediaId : mediaId(),
        mediaIds: mediaIds ?? this.mediaIds,
        imageOnRight: imageOnRight ?? this.imageOnRight,
        buttonLabel: buttonLabel ?? this.buttonLabel,
        target: target ?? this.target,
      );

  /// Only the fields that apply to [type] are stored.
  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.id,
        'heading': heading.toMap(),
        if (type != CustomSectionType.imageGrid) 'body': body.toMap(),
        if (type == CustomSectionType.imageText) ...{'mediaId': mediaId ?? '', 'imageOnRight': imageOnRight},
        if (type == CustomSectionType.imageGrid) 'mediaIds': mediaIds,
        if (type == CustomSectionType.callToAction) ...{'buttonLabel': buttonLabel.toMap(), 'target': target.trim()},
      };
}

/// Where a call-to-action button may lead, checked when saving and again
/// before following it on the public site. Allowed: a public page of this
/// site (`/`, a built-in section, or `/pages/<slug>`), an `https://` link
/// to another website, or a `mailto:`/`tel:` link. Anything else (e.g.
/// `javascript:`, `http:`, `/app` or other management routes, or an
/// `https://` address on this website such as `https://<site>/#/app`) is
/// refused.
class SafeLinkTarget {
  static bool isInternal(String target) => target.startsWith('/');

  /// Null when [target] is allowed, otherwise why not. [siteHosts]
  /// replaces this website's hosts (tests).
  static String? validate(String target, {Set<String>? siteHosts}) {
    final value = target.trim();
    if (value.isEmpty) return 'Enter where the button should lead.';
    if (value.startsWith('/')) {
      if (PublicRoutes.sections.contains(value)) return null;
      final slug = PublicRoutes.slugFromRoute(value);
      if (slug != null && CustomPage.validateSlugFormat(slug) == null) return null;
      return 'Use a page of this website, for example /admissions or /pages/open-day.';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return 'This link is not valid.';
    switch (uri.scheme) {
      case 'https':
        if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return 'This link is not valid.';
        if (PublicSiteHosts.isSiteUrl(uri, hosts: siteHosts)) {
          return PublicRoutes.routesInUrl(uri).any(PublicRoutes.isProtectedAppRoute)
              ? 'This is a protected part of the app and can’t be linked.'
              : 'This address is on this website. Use the page’s address instead, for example /admissions or /pages/open-day.';
        }
        return null;
      case 'mailto':
      case 'tel':
        return uri.path.isEmpty ? 'This link is not valid.' : null;
      default:
        return 'Links must start with https://, mailto: or tel:, or be a page of this website.';
    }
  }
}

/// An additional public page created in Settings -> Website, shown at
/// `/pages/<slug>` once published. Stored in the same draft/live
/// collections as the built-in pages' content (`kind: 'custom'`, with an
/// automatic document id), so drafts stay admin-only and visitors read only
/// the live copy.
@immutable
class CustomPage {
  const CustomPage({
    required this.id,
    required this.slug,
    this.title = const LocalizedText(),
    this.intro = const LocalizedText(),
    this.heroMediaId,
    this.sections = const [],
    this.blocks,
    this.showInNavigation = false,
    this.navOrder = 0,
    this.archived = false,
    this.updatedAt,
    this.publishedAt,
  });

  static const kind = 'custom';
  static const maxSections = 20;
  static const maxTitleLength = 80;
  static const maxIntroLength = 600;
  static const maxHeadingLength = 120;
  static const maxBodyLength = 3000;
  static const maxButtonLength = 40;
  static const maxGridImages = 24;

  static bool isCustomDoc(Map<String, dynamic> data) => data['kind'] == kind;

  factory CustomPage.fromMap(String id, Map<String, dynamic> map) {
    DateTime? date(Object? v) => v is Timestamp ? v.toDate() : null;
    final heroId = map['heroMediaId']?.toString() ?? '';
    final sections = map['sections'];
    return CustomPage(
      id: id,
      slug: map['slug']?.toString() ?? '',
      title: LocalizedText.fromMap(map['title']),
      intro: LocalizedText.fromMap(map['intro']),
      heroMediaId: heroId.isEmpty ? null : heroId,
      sections: sections is List
          ? [
              for (final s in sections)
                if (s is Map) CustomPageSection.fromMap(Map<String, dynamic>.from(s)),
            ]
          : const [],
      blocks: map['blocks'] is List ? BlockRegistry.parseList(map['blocks']) : null,
      showInNavigation: map['showInNavigation'] == true,
      navOrder: map['navOrder'] is num ? (map['navOrder'] as num).toInt() : 0,
      archived: map['archived'] == true,
      updatedAt: date(map['updatedAt']),
      publishedAt: date(map['publishedAt']),
    );
  }

  final String id;
  final String slug;
  final LocalizedText title;
  final LocalizedText intro;
  final String? heroMediaId;
  final List<CustomPageSection> sections;

  /// The page-builder blocks of a page saved in that format (schema
  /// version 2), or null for a page made of [sections] (every page so
  /// far). When set, they are what the page shows; [sections] are kept as
  /// stored. Unsupported blocks are kept and saved back unchanged.
  final List<WebsiteBlock>? blocks;

  /// Whether this page is made of page-builder [blocks].
  bool get usesBlocks => blocks != null;

  /// The page's content as blocks: its [blocks], or its [sections]
  /// converted in memory (nothing is saved).
  List<WebsiteBlock> get effectiveBlocks => blocks ?? LegacySections.toBlocks(sections);

  /// This page with its sections converted to blocks (ids kept or
  /// derived). Nothing is saved; the converted page's sections copy is
  /// exactly its current sections.
  CustomPage convertedToBlocks() => copyWith(blocks: () => LegacySections.toBlocks(sections));

  /// Listed in the site navigation (when published).
  final bool showInNavigation;
  final int navOrder;

  /// Archived pages are off the website and out of the active list (draft
  /// only); the slug stays reserved so an old link never reaches a
  /// different page.
  final bool archived;
  final DateTime? updatedAt;
  final DateTime? publishedAt;

  String get route => PublicRoutes.customPage(slug);

  /// Every image the page shows.
  List<String> get referencedMedia => {
        ?heroMediaId,
        for (final s in sections) ...s.referencedMedia,
        ...BlockRegistry.referencedMedia(blocks ?? const []),
      }.toList();

  CustomPage copyWith({
    String? slug,
    LocalizedText? title,
    LocalizedText? intro,
    String? Function()? heroMediaId,
    List<CustomPageSection>? sections,
    List<WebsiteBlock>? Function()? blocks,
    bool? showInNavigation,
    int? navOrder,
    bool? archived,
  }) =>
      CustomPage(
        id: id,
        slug: slug ?? this.slug,
        title: title ?? this.title,
        intro: intro ?? this.intro,
        heroMediaId: heroMediaId == null ? this.heroMediaId : heroMediaId(),
        sections: sections ?? this.sections,
        blocks: blocks == null ? this.blocks : blocks(),
        showInNavigation: showInNavigation ?? this.showInNavigation,
        navOrder: navOrder ?? this.navOrder,
        archived: archived ?? this.archived,
        updatedAt: updatedAt,
        publishedAt: publishedAt,
      );

  /// The visitor-facing fields only: what the live page holds.
  Map<String, dynamic> toContentMap() => {
        'kind': kind,
        'slug': slug.trim(),
        'title': title.toMap(),
        'intro': intro.toMap(),
        'heroMediaId': heroMediaId ?? '',
        // A page built with blocks stores a sections copy derived from its
        // blocks on every save, for older versions of the app; it is never
        // read back, so blocks are the only editable copy.
        'sections': [for (final s in blocks == null ? sections : LegacySections.mirror(blocks!)) s.toMap()],
        // Only pages saved with blocks have these (existing pages unchanged).
        if (blocks != null) ...{'schemaVersion': 2, 'blocks': BlockRegistry.toMapList(blocks!)},
        'showInNavigation': showInNavigation,
        'navOrder': navOrder,
        'mediaIds': referencedMedia,
      };

  /// Same visible content as [other] (ignores timestamps and archiving).
  bool sameContentAs(CustomPage? other) => other != null && jsonEncode(toContentMap()) == jsonEncode(other.toContentMap());

  /// What publishing this page stores: its hidden blocks left out
  /// ([BlockRegistry.withoutHidden]); the draft keeps them.
  CustomPage get forVisitors => blocks == null ? this : copyWith(blocks: () => BlockRegistry.withoutHidden(blocks!));

  /// Whether publishing this draft would leave [live] as it is.
  bool samePublishedContentAs(CustomPage? live) => forVisitors.sameContentAs(live?.forVisitors);

  static final _slugPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  /// Null when [slug] is a well-formed URL slug: 2–60 lowercase letters,
  /// digits and single hyphens (no leading/trailing hyphen).
  static String? validateSlugFormat(String slug) {
    if (slug.length < 2 || slug.length > 60) return 'The web address must be 2–60 characters.';
    if (!_slugPattern.hasMatch(slug)) {
      return 'Use lowercase letters, numbers and single hyphens only (for example open-day-2026).';
    }
    return null;
  }

  /// A suggested slug from an English title ("Open Day 2026!" ->
  /// "open-day-2026"); empty when the title has no usable characters.
  static String slugify(String title) {
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.length > 60 ? slug.substring(0, 60).replaceAll(RegExp(r'-+$'), '') : slug;
  }

  /// Every problem that would stop this page being saved, in order.
  List<String> validationErrors() {
    final errors = <String>[];
    final slugError = validateSlugFormat(slug.trim());
    if (slugError != null) errors.add(slugError);
    if (title.en.trim().isEmpty) errors.add('Enter an English title.');
    // Every language is checked: English, Tamil and any other.
    void limit(LocalizedText text, int max, String what) {
      if (text.values.values.any((t) => t.trim().length > max)) errors.add('$what must be $max characters or fewer.');
    }

    void tamilNeedsEnglish(LocalizedText text, String what) {
      if (text.languageMissingSource case final name?) errors.add('$what: enter the English text as well as the $name text.');
    }

    limit(title, maxTitleLength, 'The title');
    limit(intro, maxIntroLength, 'The introduction');
    tamilNeedsEnglish(intro, 'Introduction');
    // A page built with blocks is checked by its blocks; its sections are a
    // derived copy, not checked as content.
    if (blocks != null) {
      errors.addAll(BlockRegistry.validate(blocks!));
      return errors;
    }
    if (sections.length > maxSections) errors.add('A page can have at most $maxSections sections.');
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      final where = 'Section ${i + 1} (${s.type.adminLabel})';
      limit(s.heading, maxHeadingLength, '$where heading');
      limit(s.body, maxBodyLength, '$where text');
      tamilNeedsEnglish(s.heading, '$where heading');
      tamilNeedsEnglish(s.body, '$where text');
      switch (s.type) {
        case CustomSectionType.text:
          if (s.heading.en.trim().isEmpty && s.body.en.trim().isEmpty) errors.add('$where: add a heading or some text.');
        case CustomSectionType.imageText:
          if (s.mediaId == null) errors.add('$where: choose an image.');
        case CustomSectionType.imageGrid:
          if (s.mediaIds.isEmpty) errors.add('$where: choose at least one image.');
          if (s.mediaIds.length > maxGridImages) errors.add('$where: at most $maxGridImages images.');
        case CustomSectionType.callToAction:
          limit(s.buttonLabel, maxButtonLength, '$where button label');
          if (s.buttonLabel.en.trim().isEmpty) errors.add('$where: enter an English button label.');
          final targetError = SafeLinkTarget.validate(s.target);
          if (targetError != null) errors.add('$where: $targetError');
      }
    }
    return errors;
  }
}
