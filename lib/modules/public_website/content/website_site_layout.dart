import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../public_routes.dart';
import '../public_strings.dart';
import 'website_content_models.dart';
import 'website_custom_page.dart';
import 'website_design.dart';
import 'website_site_style.dart';

/// The public website's built-in pages as navigation targets, by id: the
/// managed pages' existing [WebsitePageSlot] ids, plus `contact` (which
/// has no managed content yet but is a built-in page all the same).
class SiteBuiltInPages {
  static const contactId = 'contact';

  static String idFor(String route) => WebsitePageSlot.forRoute(route)?.id ?? (route == PublicRoutes.contact ? contactId : '');

  /// Every built-in page id, in the site's own navigation order.
  static List<String> get ids => [for (final route in PublicRoutes.sections) idFor(route)];

  /// The route of built-in page [id], or null when [id] isn't one.
  static String? routeFor(String id) {
    if (id == contactId) return PublicRoutes.contact;
    return WebsitePageSlot.parse(id)?.route;
  }
}

enum SiteNavTargetKind {
  builtIn('builtin'),
  page('page'),
  external('external');

  const SiteNavTargetKind(this.id);

  final String id;

  static SiteNavTargetKind? parse(Object? value) {
    for (final kind in values) {
      if (kind.id == value) return kind;
    }
    return null;
  }
}

/// Where a navigation link leads: a built-in page (by its id), an
/// additional page (by its stable page id, so renaming its address never
/// breaks the link), or an external `https://` address. Internal pages are
/// never stored as typed paths, so a link can't point at the management
/// app's routes.
@immutable
class SiteNavTarget {
  const SiteNavTarget._(this.kind, this.value);

  const SiteNavTarget.builtIn(String id) : this._(SiteNavTargetKind.builtIn, id);
  const SiteNavTarget.page(String pageId) : this._(SiteNavTargetKind.page, pageId);
  const SiteNavTarget.external(String url) : this._(SiteNavTargetKind.external, url);

  final SiteNavTargetKind kind;

  /// The built-in page id, the additional page's id, or the URL.
  final String value;

  static const maxUrlLength = 500;

  static SiteNavTarget? fromMap(Object? map) {
    if (map is! Map) return null;
    final kind = SiteNavTargetKind.parse(map['kind']);
    return switch (kind) {
      SiteNavTargetKind.builtIn => SiteNavTarget.builtIn(map['id']?.toString() ?? ''),
      SiteNavTargetKind.page => SiteNavTarget.page(map['pageId']?.toString() ?? ''),
      SiteNavTargetKind.external => SiteNavTarget.external(map['url']?.toString() ?? ''),
      null => null,
    };
  }

  Map<String, dynamic> toMap() => switch (kind) {
        SiteNavTargetKind.builtIn => {'kind': kind.id, 'id': value},
        SiteNavTargetKind.page => {'kind': kind.id, 'pageId': value},
        SiteNavTargetKind.external => {'kind': kind.id, 'url': value.trim()},
      };

  /// Null when [url] is an allowed external link: an absolute `https://`
  /// address with a host, no spaces and no user name, on another website.
  /// Addresses on this website ([PublicSiteHosts], whatever the port, case,
  /// encoding or `www.`) are refused — with a specific message when their
  /// path or `#/` route is a reserved app route — and so are typed paths:
  /// site pages are chosen from the page list instead. [siteHosts]
  /// replaces this website's hosts (tests).
  static String? validateExternalUrl(String url, {Set<String>? siteHosts}) {
    final value = url.trim();
    if (value.isEmpty) return 'Enter the web address.';
    if (value.length > maxUrlLength) return 'The web address must be $maxUrlLength characters or fewer.';
    if (value.startsWith('/') || value.startsWith('#')) {
      return PublicRoutes.isProtectedAppRoute(value.startsWith('#') ? value.substring(1) : value)
          ? 'This is a protected part of the app and can’t be linked from the navigation.'
          : 'Choose pages of this website from the page list instead of typing their address.';
    }
    if (RegExp(r'\s').hasMatch(value)) return 'The web address can’t contain spaces.';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return 'External links must be complete https:// addresses, for example https://example.org/page.';
    }
    if (PublicSiteHosts.isSiteUrl(uri, hosts: siteHosts)) {
      return PublicRoutes.routesInUrl(uri).any(PublicRoutes.isProtectedAppRoute)
          ? 'This is a protected part of the app and can’t be linked from the navigation.'
          : 'This address is on this website. Choose the page from the page list instead.';
    }
    return null;
  }

  /// Null when this target is well formed (whether it is currently
  /// published is checked separately).
  String? validate() => switch (kind) {
        SiteNavTargetKind.builtIn => SiteBuiltInPages.routeFor(value) == null ? 'Choose a page.' : null,
        SiteNavTargetKind.page => value.trim().isEmpty ? 'Choose a page.' : null,
        SiteNavTargetKind.external => validateExternalUrl(value),
      };

  @override
  bool operator ==(Object other) => other is SiteNavTarget && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// One navigation link. Its order is its position in the list; [label]
/// left blank (English) means "use the page's own name".
@immutable
class SiteNavEntry {
  const SiteNavEntry({required this.id, required this.target, this.label = const LocalizedText(), this.visible = true});

  /// A new link with a fresh id.
  factory SiteNavEntry.create(SiteNavTarget target, {LocalizedText label = const LocalizedText()}) =>
      SiteNavEntry(id: 'n${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}', target: target, label: label);

  /// Null when [map] isn't a usable entry (it is then left out).
  static SiteNavEntry? fromMap(Object? map) {
    if (map is! Map) return null;
    final id = map['id']?.toString() ?? '';
    final target = SiteNavTarget.fromMap(map['target']);
    if (id.isEmpty || target == null) return null;
    return SiteNavEntry(id: id, target: target, label: LocalizedText.fromMap(map['label']), visible: map['visible'] != false);
  }

  final String id;
  final SiteNavTarget target;
  final LocalizedText label;

  /// Hidden links stay in the layout (and their pages stay published) but
  /// aren't shown.
  final bool visible;

  SiteNavEntry copyWith({SiteNavTarget? target, LocalizedText? label, bool? visible}) =>
      SiteNavEntry(id: id, target: target ?? this.target, label: label ?? this.label, visible: visible ?? this.visible);

  Map<String, dynamic> toMap() => {'id': id, 'label': label.toMap(), 'target': target.toMap(), 'visible': visible};
}

/// The public website's header and footer: site name and tagline, the main
/// (header and mobile menu) and footer navigation, footer text and
/// copyright — and the site's design ([design]: palette and typography)
/// and the header's and footer's look ([header], [footer]), which every
/// page shares. Stored as one document, `site_layout`, in the page drafts
/// and live pages collections, so visitors get it with the live pages they
/// already load (no extra read). Blank text means "use the built-in
/// wording". When nothing is published the site uses its built-in layout.
///
/// The design, header and footer are stored only once they differ from the
/// site's own look, so an unchanged layout is stored exactly as before;
/// older versions of the app ignore them. Top-level keys this version
/// doesn't know are kept in the draft.
@immutable
class SiteLayout {
  const SiteLayout({
    this.siteName = const LocalizedText(),
    this.tagline = const LocalizedText(),
    this.mainNav = const [],
    this.footerNav = const [],
    this.footerText = const LocalizedText(),
    this.copyright = const LocalizedText(),
    this.design = SiteDesign.defaults,
    this.header = const SiteHeaderStyle(),
    this.footer = const SiteFooterStyle(),
    this.preserved = const {},
  });

  /// Keys of the stored document that aren't layout content.
  static const _bookkeeping = {'updatedAt', 'updatedById', 'updatedByName', 'lastPublishedAt', 'lastPublishedById', 'lastPublishedByName', 'publishedAt'};
  static const _known = {'kind', 'schemaVersion', 'siteName', 'tagline', 'mainNav', 'footerNav', 'footerText', 'copyright', 'design', 'header', 'footer'};

  /// Document id in [WebsiteCollections.pageDrafts]/[WebsiteCollections.livePages].
  static const docId = 'site_layout';
  static const kind = 'layout';
  static const schemaVersion = 1;

  static const maxMainEntries = 10;
  static const maxFooterEntries = 16;
  static const maxLabelLength = 40;
  static const maxSiteNameLength = 60;
  static const maxTaglineLength = 160;
  static const maxFooterTextLength = 600;
  static const maxCopyrightLength = 120;

  /// The layout in [data], or null when it can't be used safely (not a
  /// layout, an unknown schema version or the wrong shapes) — the site then
  /// keeps its built-in layout. Individual malformed links are left out.
  static SiteLayout? tryParse(Object? data) {
    try {
      if (data is! Map) return null;
      if (data['kind'] != kind || data['schemaVersion'] != schemaVersion) return null;
      final main = data['mainNav'];
      final footer = data['footerNav'];
      if (main is! List || footer is! List) return null;
      for (final key in ['siteName', 'tagline', 'footerText', 'copyright']) {
        final value = data[key];
        if (value != null && value is! Map) return null;
      }
      List<SiteNavEntry> entries(List list) => [for (final item in list) ?SiteNavEntry.fromMap(item)];
      return SiteLayout(
        siteName: LocalizedText.fromMap(data['siteName']),
        tagline: LocalizedText.fromMap(data['tagline']),
        mainNav: entries(main),
        footerNav: entries(footer),
        footerText: LocalizedText.fromMap(data['footerText']),
        copyright: LocalizedText.fromMap(data['copyright']),
        design: SiteDesign.fromMap(data['design']),
        header: SiteHeaderStyle.fromMap(data['header']),
        footer: SiteFooterStyle.fromMap(data['footer']),
        preserved: {for (final e in data.entries) if (!_known.contains(e.key) && !_bookkeeping.contains(e.key)) e.key.toString(): e.value},
      );
    } catch (_) {
      return null;
    }
  }

  /// A first layout that reproduces today's navigation exactly: the
  /// built-in pages, then the published additional pages listed in the
  /// navigation (in their order), then Contact — in the header and, as
  /// today, in the footer. Labels are blank, so they follow each page's
  /// own name.
  factory SiteLayout.fromCurrentNavigation(List<CustomPage> publishedPages) {
    List<SiteNavEntry> entries(String prefix) {
      final builtIn = [for (final id in SiteBuiltInPages.ids) SiteNavEntry(id: '$prefix-$id', target: SiteNavTarget.builtIn(id))];
      final listed = [
        for (final page in publishedPages)
          if (page.showInNavigation) SiteNavEntry(id: '$prefix-page-${page.id}', target: SiteNavTarget.page(page.id)),
      ];
      final contactAt = builtIn.indexWhere((e) => e.target.value == SiteBuiltInPages.contactId);
      return [...builtIn.sublist(0, contactAt), ...listed, ...builtIn.sublist(contactAt)];
    }

    return SiteLayout(mainNav: entries('main'), footerNav: entries('footer'));
  }

  final LocalizedText siteName;
  final LocalizedText tagline;

  /// Header (desktop) and mobile menu links, in order.
  final List<SiteNavEntry> mainNav;

  /// Footer links, in order (independent of [mainNav]).
  final List<SiteNavEntry> footerNav;
  final LocalizedText footerText;
  final LocalizedText copyright;

  /// The site's palette and typography (what pages, header and footer
  /// draw with).
  final SiteDesign design;
  final SiteHeaderStyle header;
  final SiteFooterStyle footer;

  /// Stored top-level keys this version doesn't know, kept in the draft.
  final Map<String, Object?> preserved;

  SiteLayout copyWith({
    LocalizedText? siteName,
    LocalizedText? tagline,
    List<SiteNavEntry>? mainNav,
    List<SiteNavEntry>? footerNav,
    LocalizedText? footerText,
    LocalizedText? copyright,
    SiteDesign? design,
    SiteHeaderStyle? header,
    SiteFooterStyle? footer,
  }) =>
      SiteLayout(
        siteName: siteName ?? this.siteName,
        tagline: tagline ?? this.tagline,
        mainNav: mainNav ?? this.mainNav,
        footerNav: footerNav ?? this.footerNav,
        footerText: footerText ?? this.footerText,
        copyright: copyright ?? this.copyright,
        design: design ?? this.design,
        header: header ?? this.header,
        footer: footer ?? this.footer,
        preserved: preserved,
      );

  /// The stored fields (visitor-facing only; no editor bookkeeping). The
  /// design, header and footer only when they differ from the site's own.
  Map<String, dynamic> toMap() => {
        'kind': kind,
        'schemaVersion': schemaVersion,
        'siteName': siteName.toMap(),
        'tagline': tagline.toMap(),
        'mainNav': [for (final e in mainNav) e.toMap()],
        'footerNav': [for (final e in footerNav) e.toMap()],
        'footerText': footerText.toMap(),
        'copyright': copyright.toMap(),
        if (!design.isDefault) 'design': design.toMap(),
        if (!header.isDefault) 'header': header.toMap(),
        if (!footer.isDefault) 'footer': footer.toMap(),
      };

  /// [toMap] plus the keys this version doesn't know (for the draft).
  Map<String, dynamic> toDraftMap() => {...preserved, ...toMap()};

  bool sameContentAs(SiteLayout? other) => other != null && jsonEncode(toMap()) == jsonEncode(other.toMap());

  /// Every problem that would stop this layout being saved, in order.
  List<String> validationErrors() {
    final errors = <String>[];
    void text(LocalizedText value, int max, String what) => errors.addAll(value.problems(max, what));

    text(siteName, maxSiteNameLength, 'The site name');
    text(tagline, maxTaglineLength, 'The tagline');
    text(footerText, maxFooterTextLength, 'The footer text');
    text(copyright, maxCopyrightLength, 'The copyright text');

    void list(List<SiteNavEntry> entries, int max, String where) {
      if (entries.length > max) errors.add('$where can have at most $max links.');
      final ids = <String>{};
      final targets = <SiteNavTarget>{};
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        final name = '$where, link ${i + 1}';
        if (e.id.isEmpty || !ids.add(e.id)) errors.add('$name: this link is duplicated. Remove it and add it again.');
        final targetError = e.target.validate();
        if (targetError != null) errors.add('$name: $targetError');
        if (!targets.add(_normalized(e.target))) errors.add('$name: this destination is already in $where.');
        text(e.label, maxLabelLength, '$name label');
        if (e.target.kind == SiteNavTargetKind.external && e.label.en.trim().isEmpty) errors.add('$name: enter an English label for the external link.');
      }
    }

    list(mainNav, maxMainEntries, 'Main navigation');
    list(footerNav, maxFooterEntries, 'Footer navigation');
    errors.addAll(design.validationErrors());
    errors.addAll(header.validationErrors(validateHeaderLink));
    errors.addAll(footer.validationErrors());
    return errors;
  }

  /// Null when the header button may lead to [target]: a public page of
  /// this website, an allowed external link, mailto: or tel: (the same
  /// rule as page buttons).
  static String? validateHeaderLink(String target) => SafeLinkTarget.validate(target);

  /// Problems with visible links whose additional page isn't published
  /// (missing, unpublished, archived or invalid), given the ids of the
  /// published pages. Such links are hidden from visitors; publishing the
  /// layout is refused while any visible link has one.
  List<String> unpublishedLinkErrors(Set<String> publishedPageIds) {
    final errors = <String>[];
    void list(List<SiteNavEntry> entries, String where) {
      for (var i = 0; i < entries.length; i++) {
        final e = entries[i];
        if (e.visible && e.target.kind == SiteNavTargetKind.page && !publishedPageIds.contains(e.target.value)) {
          errors.add('$where, link ${i + 1}: its page isn’t published. Publish the page, or hide or remove the link.');
        }
      }
    }

    list(mainNav, 'Main navigation');
    list(footerNav, 'Footer navigation');
    return errors;
  }

  static SiteNavTarget _normalized(SiteNavTarget t) => t.kind == SiteNavTargetKind.external ? SiteNavTarget.external(t.value.trim()) : t;
}

/// One link of the public header, mobile menu or footer, ready to show.
@immutable
class PublicNavEntry {
  const PublicNavEntry.builtIn(this.route)
      : title = const LocalizedText(),
        isExternal = false;
  const PublicNavEntry.custom(this.route, this.title) : isExternal = false;
  const PublicNavEntry.external(String url, this.title)
      : route = url,
        isExternal = true;

  /// The public route — or, for an external link, its https URL.
  final String route;

  /// The label; blank (English) means the built-in name of [route].
  final LocalizedText title;
  final bool isExternal;

  String label(PublicStrings strings, PublicLanguage language) {
    final text = title.resolve(language);
    return text.isNotEmpty ? text : strings.labelFor(route);
  }
}

/// The header and footer as visitors see them: the published [SiteLayout]
/// resolved against published content, or — with no usable layout — the
/// site's built-in header and footer exactly as before layouts existed.
@immutable
class PublicSiteChrome {
  const PublicSiteChrome({
    required this.mainNav,
    required this.footerNav,
    this.siteName = const LocalizedText(),
    this.tagline = const LocalizedText(),
    this.footerText = const LocalizedText(),
    this.copyright = const LocalizedText(),
    this.fromLayout = false,
    this.design = SiteDesign.defaults,
    this.header = const SiteHeaderStyle(),
    this.footer = const SiteFooterStyle(),
  });

  /// The built-in navigation: the built-in pages, then the published
  /// additional pages listed in the navigation (in order), Contact last —
  /// the same list in the header and the footer.
  factory PublicSiteChrome.builtIn(List<CustomPage> publishedPages) {
    final builtIn = [for (final route in PublicRoutes.sections) PublicNavEntry.builtIn(route)];
    final listed = [
      for (final page in publishedPages)
        if (page.showInNavigation && _isUsable(page)) PublicNavEntry.custom(page.route, page.title),
    ];
    final contactAt = builtIn.indexWhere((e) => e.route == PublicRoutes.contact);
    final nav = [...builtIn.sublist(0, contactAt), ...listed, ...builtIn.sublist(contactAt)];
    return PublicSiteChrome(mainNav: nav, footerNav: nav);
  }

  /// [layout] (published, or a draft being previewed) resolved against
  /// [publishedPages]; the built-in chrome when [layout] is null. Links
  /// that are hidden, malformed, or whose page isn't published (missing,
  /// unpublished, archived or invalid) are left out, so no draft title or
  /// address ever appears.
  factory PublicSiteChrome.resolve(SiteLayout? layout, List<CustomPage> publishedPages) {
    if (layout == null) return PublicSiteChrome.builtIn(publishedPages);
    final pages = {for (final p in publishedPages) if (_isUsable(p)) p.id: p};
    List<PublicNavEntry> resolve(List<SiteNavEntry> entries) {
      final result = <PublicNavEntry>[];
      final seen = <String>{};
      for (final e in entries) {
        if (!e.visible || e.target.validate() != null) continue;
        final label = e.label.en.trim().isEmpty ? null : e.label.trimmed();
        final PublicNavEntry? entry = switch (e.target.kind) {
          SiteNavTargetKind.builtIn => PublicNavEntry.custom(SiteBuiltInPages.routeFor(e.target.value)!, label ?? const LocalizedText()),
          SiteNavTargetKind.page => pages[e.target.value] == null ? null : PublicNavEntry.custom(pages[e.target.value]!.route, label ?? pages[e.target.value]!.title),
          SiteNavTargetKind.external => PublicNavEntry.external(e.target.value.trim(), e.label.trimmed()),
        };
        // One link per destination in a list (they're keyed by route).
        if (entry != null && seen.add(entry.route)) result.add(entry);
      }
      return result;
    }

    return PublicSiteChrome(
      mainNav: resolve(layout.mainNav),
      footerNav: resolve(layout.footerNav),
      siteName: layout.siteName.trimmed(),
      tagline: layout.tagline.trimmed(),
      footerText: layout.footerText.trimmed(),
      copyright: layout.copyright.trimmed(),
      fromLayout: true,
      design: layout.design,
      header: layout.header,
      footer: layout.footer,
    );
  }

  /// A published additional page the site can link to.
  static bool _isUsable(CustomPage page) =>
      !page.archived && CustomPage.validateSlugFormat(page.slug) == null && page.title.en.trim().isNotEmpty;

  final List<PublicNavEntry> mainNav;
  final List<PublicNavEntry> footerNav;
  final LocalizedText siteName;
  final LocalizedText tagline;
  final LocalizedText footerText;
  final LocalizedText copyright;

  /// Whether a published layout is in use (otherwise the built-in one).
  final bool fromLayout;

  /// The site's design, and the header's and footer's look (the site's
  /// own without a layout).
  final SiteDesign design;
  final SiteHeaderStyle header;
  final SiteFooterStyle footer;

  /// The header button, when there is one and its link is allowed.
  PublicNavEntry? get headerButton {
    if (!header.hasCta || SiteLayout.validateHeaderLink(header.ctaTarget.trim()) != null) return null;
    final target = header.ctaTarget.trim();
    return SafeLinkTarget.isInternal(target) ? PublicNavEntry.custom(target, header.ctaLabel.trimmed()) : PublicNavEntry.external(target, header.ctaLabel.trimmed());
  }

  String siteNameFor(PublicStrings strings, PublicLanguage language) => _or(siteName.resolve(language), strings.schoolName);
  String taglineFor(PublicStrings strings, PublicLanguage language) => _or(tagline.resolve(language), strings.footerTagline);

  static String _or(String value, String fallback) => value.isNotEmpty ? value : fallback;
}
