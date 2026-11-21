import 'website_block.dart';

/// Section anchor ids: the public navigation identifier of a page's
/// sections (`#enquire`, `/teacher-training#enquire`), kept apart from the
/// section's editor-only name.
///
/// A section's anchor is stored in its `anchor` field. It is given one
/// automatically — from its name (or heading) when it is created or first
/// edited — unique on its page, and then kept: renaming, reordering or
/// editing the section never changes it. Only an administrator changes it
/// (Section anchor ID), or a duplicate, which gets a new one.
///
/// Sections saved before anchors existed have none stored: their anchor is
/// derived the same way, in page order ([effective]), so it is the same
/// every time the page is read. Such a page is saved back exactly as it was
/// stored; an anchor is stored only when an edit would otherwise change it
/// ([ensure]), or publishing would ([pinForVisitors]).
class SectionAnchors {
  SectionAnchors._();

  /// The stored field.
  static const field = 'anchor';

  /// The longest anchor id.
  static const maxLength = 64;

  /// Lowercase letters and digits in words joined by single hyphens.
  static final pattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  /// What a section with neither name nor heading (in letters a–z or
  /// digits) is called.
  static const fallback = 'section';

  /// Whether [anchor] is a well-formed anchor id.
  static bool isValid(String anchor) => anchor.length <= maxLength && pattern.hasMatch(anchor);

  /// Why [anchor] can't be an anchor id, or null when it can.
  static String? formatProblem(String anchor) {
    if (anchor.isEmpty) return 'Enter an anchor ID.';
    if (anchor.length > maxLength) return 'An anchor ID can be at most $maxLength characters.';
    if (!pattern.hasMatch(anchor)) return 'Use lowercase letters, numbers and single hyphens only (for example enquire or our-programs).';
    return null;
  }

  /// [text] as an anchor id: lower case, every run of other characters a
  /// single hyphen, no hyphen at either end, at most 56 characters (room
  /// for a `-NN` suffix). Empty when [text] has no letter a–z or digit.
  static String slugify(String text) {
    final slug = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.length > 56 ? slug.substring(0, 56).replaceAll(RegExp(r'-+$'), '') : slug;
  }

  /// Whether [block] is a section (the blocks anchors belong to).
  static bool isSection(WebsiteBlock block) => block is StructuredBlock && block.type == 'section';

  /// The anchor stored on [section] (trimmed; '' for none).
  static String stored(StructuredBlock section) => section.string(field).trim();

  /// The anchor a section without one is given: from its editor name,
  /// else its English heading, else [fallback].
  static String baseFor(StructuredBlock section) {
    for (final key in const ['name', 'heading']) {
      final slug = slugify(section.text(key).en);
      if (slug.isNotEmpty) return slug;
    }
    return fallback;
  }

  /// [base] when [taken] doesn't have it, else `base-2`, `base-3` …
  static String unique(String base, Set<String> taken) {
    if (!taken.contains(base)) return base;
    for (var n = 2;; n++) {
      final suffix = '-$n';
      var stem = base.length + suffix.length > maxLength ? base.substring(0, maxLength - suffix.length) : base;
      stem = stem.replaceAll(RegExp(r'-+$'), '');
      final candidate = '$stem$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// The page's top-level sections, in page order.
  static List<StructuredBlock> sectionsOf(List<WebsiteBlock> blocks) => [
        for (final b in blocks)
          if (isSection(b)) b as StructuredBlock,
      ];

  /// The anchor of each section of [blocks] (by block id), as visitors get
  /// it: a stored, well-formed anchor (the first section to use one keeps
  /// it); for a section without one, the anchor [ensure] would give it. A
  /// section whose stored anchor is malformed or already used gets none
  /// (the editor reports it).
  static Map<String, String> effective(List<WebsiteBlock> blocks) {
    final sections = sectionsOf(blocks);
    final out = <String, String>{};
    final taken = <String>{};
    for (final s in sections) {
      final anchor = stored(s);
      if (anchor.isNotEmpty && isValid(anchor) && taken.add(anchor)) out[s.id] = anchor;
    }
    // Stored anchors are claimed first, so a derived one never takes the
    // anchor of a section further down the page.
    for (final s in sections) {
      if (stored(s).isNotEmpty) continue;
      final anchor = unique(baseFor(s), taken);
      taken.add(anchor);
      out[s.id] = anchor;
    }
    return out;
  }

  /// [next] (the page after an edit of [previous]) with the anchors that
  /// edit would otherwise change stored, or [next] itself when there are
  /// none:
  ///
  /// * a section that wasn't on the page (added, duplicated, or inserted
  ///   from a template) stores an anchor unique on the page: from its
  ///   name or heading, or the one it brought when no other section uses
  ///   it;
  /// * a section already on the page without a stored anchor (saved before
  ///   anchors existed) keeps the anchor it had: it is stored only if the
  ///   edit would change it (renaming it, or deleting, adding or
  ///   reordering a section it shared its name with). Untouched sections
  ///   are left exactly as stored.
  ///
  /// Stored anchors are never changed (a malformed or repeated one is
  /// reported by the editor, never fixed silently).
  static List<WebsiteBlock> ensure(List<WebsiteBlock> next, {required List<WebsiteBlock> previous}) {
    final before = effective(previous);
    final existed = {for (final b in previous) b.id};
    final sections = sectionsOf(next);

    // What the sections already on the page hold or held: never given to
    // a new one.
    final taken = <String>{};
    for (final s in sections) {
      if (!existed.contains(s.id)) continue;
      final own = stored(s);
      if (own.isNotEmpty) {
        taken.add(own);
      } else if (before[s.id] case final anchor?) {
        taken.add(anchor);
      }
    }
    final assigned = <String, String>{};
    for (final s in sections) {
      if (existed.contains(s.id)) continue;
      final own = stored(s);
      final anchor = own.isNotEmpty && isValid(own) && !taken.contains(own) ? own : unique(baseFor(s), taken);
      taken.add(anchor);
      if (anchor != own) assigned[s.id] = anchor;
    }
    var out = _withAnchors(next, assigned);

    // Sections from before keep their anchors: stored where the edit would
    // move them (each one stored can move another, so until none moves).
    for (var round = 0; round <= sections.length; round++) {
      final now = effective(out);
      final pins = <String, String>{
        for (final s in sectionsOf(out))
          if (existed.contains(s.id) && stored(s).isEmpty && before[s.id] != null && now[s.id] != before[s.id]) s.id: before[s.id]!,
      };
      if (pins.isEmpty) break;
      out = _withAnchors(out, pins);
    }
    return identical(out, next) || _sameAnchors(out, next) ? next : out;
  }

  /// [blocks] with the anchors of the sections that [visible] (the page as
  /// visitors get it, without its hidden blocks) would give a different
  /// anchor stored, so visitors get the anchors the editor shows: only for
  /// sections without a stored anchor that share a name with a hidden one
  /// above them. [blocks] itself when there are none.
  static List<WebsiteBlock> pinForVisitors(List<WebsiteBlock> blocks, List<WebsiteBlock> Function(List<WebsiteBlock>) visible) {
    var out = blocks;
    for (var round = 0; round <= blocks.length; round++) {
      final draft = effective(out);
      final live = effective(visible(out));
      final pins = <String, String>{};
      for (final e in live.entries) {
        final anchor = draft[e.key];
        if (anchor != null && anchor != e.value) pins[e.key] = anchor;
      }
      if (pins.isEmpty) break;
      out = _withAnchors(out, pins);
    }
    return out;
  }

  static List<WebsiteBlock> _withAnchors(List<WebsiteBlock> blocks, Map<String, String> anchors) {
    if (anchors.isEmpty) return blocks;
    return [
      for (final b in blocks)
        if (anchors[b.id] case final anchor? when isSection(b)) (b as StructuredBlock).withValue(field, anchor) else b,
    ];
  }

  static bool _sameAnchors(List<WebsiteBlock> a, List<WebsiteBlock> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// A new anchor for [section] from its name (or heading), unique among
  /// the other sections of [blocks]: the section settings' Regenerate.
  static String regenerate(StructuredBlock section, List<WebsiteBlock> blocks) {
    final others = {
      for (final e in effective(blocks).entries)
        if (e.key != section.id) e.value,
    };
    return unique(baseFor(section), others);
  }

  /// Problems with the anchors of [blocks] as a whole (each section's own
  /// format is checked with its fields): an anchor used by more than one
  /// section. Located as `BlockRegistry.validate` locates problems.
  static List<String> pageProblems(List<WebsiteBlock> blocks) {
    final firstUse = <String, int>{};
    final problems = <String>[];
    for (final (i, b) in blocks.indexed) {
      if (!isSection(b)) continue;
      final anchor = stored(b as StructuredBlock);
      if (anchor.isEmpty || !isValid(anchor)) continue;
      final first = firstUse[anchor];
      if (first == null) {
        firstUse[anchor] = i;
      } else {
        problems.add('Block ${i + 1} (Section): the anchor ID “$anchor” is already used by block ${first + 1} on this page. Each section needs its own.');
      }
    }
    return problems;
  }

  /// A label for [section] in lists: its editor name, else its heading,
  /// else "Section N" ([position] from 1).
  static String labelOf(StructuredBlock section, int position) {
    for (final key in const ['name', 'heading']) {
      final text = section.text(key).en.trim();
      if (text.isNotEmpty) return text;
    }
    return 'Section $position';
  }
}
