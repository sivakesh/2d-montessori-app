import 'package:flutter/foundation.dart';

import '../blocks/block_ids.dart';

/// Where a translatable text lives, by stable ids and explicit field names —
/// never by list position — so reordering, inserting or moving content
/// never changes it. Segments are joined with `/` (not `.`, which
/// Firestore's `update()` would read as nesting):
///
/// | Path | Text |
/// |---|---|
/// | `page/title`, `page/seo/description` | a page field |
/// | `b/<blockId>/heading` | a block field (blocks inside columns too: block ids are unique on a page) |
/// | `b/<blockId>/i/<itemId>/label` | a field of an item inside a block |
/// | `b/<blockId>/col/<colId>/header` | a table column header |
/// | `b/<blockId>/row/<rowId>/<colId>` | a table cell |
/// | `layout/siteName` | a site-layout field |
/// | `nav/<entryId>/label` | a navigation link label |
/// | `media/<mediaId>/alt` | an image's text |
@immutable
class TranslationPath {
  const TranslationPath._(this.segments);

  static const separator = '/';
  static final _fieldName = RegExp(r'^[a-z][A-Za-z0-9]{0,39}$');

  final List<String> segments;

  String get value => segments.join(separator);

  static TranslationPath _of(List<String> segments) {
    final path = TranslationPath._(List.unmodifiable(segments));
    if (!path.isValid) throw ArgumentError.value(path.value, 'path', 'Not a valid translation path');
    return path;
  }

  /// A page field; [field] may be nested with `/` (`seo/description`).
  static TranslationPath page(String field) => _of(['page', ...field.split(separator)]);
  static TranslationPath block(String blockId, String field) => _of(['b', blockId, field]);
  static TranslationPath item(String blockId, String itemId, String field) => _of(['b', blockId, 'i', itemId, field]);
  static TranslationPath tableHeader(String blockId, String columnId) => _of(['b', blockId, 'col', columnId, 'header']);
  static TranslationPath tableCell(String blockId, String rowId, String columnId) => _of(['b', blockId, 'row', rowId, columnId]);
  static TranslationPath layout(String field) => _of(['layout', field]);
  static TranslationPath navLabel(String entryId) => _of(['nav', entryId, 'label']);
  static TranslationPath media(String mediaId, String field) => _of(['media', mediaId, field]);

  /// [value] as a path, or null when it isn't one of the shapes above.
  static TranslationPath? tryParse(String value) {
    final path = TranslationPath._(List.unmodifiable(value.split(separator)));
    return path.isValid ? path : null;
  }

  bool get isValid {
    final s = segments;
    bool id(String v) => BlockIds.isValid(v);
    bool name(String v) => _fieldName.hasMatch(v);
    if (s.isEmpty) return false;
    switch (s.first) {
      case 'page':
        return s.length >= 2 && s.length <= 3 && s.skip(1).every(name);
      case 'b':
        return switch (s.length) {
          3 => id(s[1]) && name(s[2]),
          5 => id(s[1]) && ((s[2] == 'i' && id(s[3]) && name(s[4])) || (s[2] == 'col' && id(s[3]) && s[4] == 'header') || (s[2] == 'row' && id(s[3]) && id(s[4]))),
          _ => false,
        };
      case 'layout':
        return s.length == 2 && name(s[1]);
      case 'nav':
        return s.length == 3 && id(s[1]) && s[2] == 'label';
      case 'media':
        return s.length == 3 && id(s[1]) && name(s[2]);
      default:
        return false;
    }
  }

  /// The block this path belongs to, or null.
  String? get blockId => segments.first == 'b' ? segments[1] : null;

  @override
  bool operator ==(Object other) => other is TranslationPath && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
