import 'package:flutter/foundation.dart';

import '../website_content_models.dart';
import 'block_registry.dart';
import 'field_spec.dart';

/// One block of a page built with the page builder. Every block has a
/// stable [id] (fixed for its life: reordering never changes it), a [type]
/// and a schema version. A block this app knows is a [StructuredBlock]; any
/// other (an unknown type, or a newer version of a known one) is an
/// [UnsupportedBlock], kept exactly as stored and never shown publicly.
@immutable
sealed class WebsiteBlock {
  const WebsiteBlock();

  String get id;
  String get type;

  /// The stored form.
  Map<String, dynamic> toMap();
}

/// A block of a type (and version) this app knows: [values] hold its
/// fields as declared by its [definition].
final class StructuredBlock extends WebsiteBlock {
  const StructuredBlock({
    required this.definition,
    required this.id,
    this.hidden = false,
    this.style = const {},
    this.values = const {},
    this.preserved = const {},
  });

  final BlockDefinition definition;

  @override
  final String id;

  /// Hidden blocks stay in the page but aren't shown publicly.
  final bool hidden;

  /// Display options (`background`, `spacing`), kept as stored.
  final Map<String, dynamic> style;
  final Map<String, Object?> values;

  /// Raw stored values kept as they were: unknown keys, and known keys
  /// whose stored value had the wrong shape (they win over [values]).
  final Map<String, Object?> preserved;

  @override
  String get type => definition.type;

  LocalizedText text(String key) => values[key] as LocalizedText? ?? const LocalizedText();
  String string(String key) => values[key] as String? ?? '';
  bool flag(String key) => values[key] as bool? ?? false;
  List<BlockItem> items(String key) => values[key] as List<BlockItem>? ?? const [];
  List<BlockColumn> columns(String key) => values[key] as List<BlockColumn>? ?? const [];

  /// `background` and `spacing`, or their defaults.
  String get background => style['background'] is String ? style['background'] as String : 'white';
  String get spacing => style['spacing'] is String ? style['spacing'] as String : 'normal';

  StructuredBlock copyWith({String? id, bool? hidden, Map<String, dynamic>? style, Map<String, Object?>? values}) => StructuredBlock(
        definition: definition,
        id: id ?? this.id,
        hidden: hidden ?? this.hidden,
        style: style ?? this.style,
        values: values ?? this.values,
        preserved: preserved,
      );

  /// This block with field [key] set (its preserved raw value dropped).
  StructuredBlock withValue(String key, Object? value) => StructuredBlock(
        definition: definition,
        id: id,
        hidden: hidden,
        style: style,
        values: {...values, key: value},
        preserved: Map.of(preserved)..remove(key),
      );

  @override
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'type': definition.type,
      'v': definition.version,
      if (hidden) 'hidden': true,
      if (style.isNotEmpty) 'style': style,
      ...serializeFieldValues(values, preserved, definition.fields),
    };
    // Columns hold blocks: written through their own toMap.
    for (final field in definition.fields.whereType<ColumnsFieldSpec>()) {
      if (!preserved.containsKey(field.key)) map[field.key] = [for (final c in columns(field.key)) c.toMap()];
    }
    return map;
  }
}

/// A block this app can't show — an unknown type, a newer version, or a
/// block without a usable type — kept exactly as stored so saving never
/// loses it. Never rendered publicly.
final class UnsupportedBlock extends WebsiteBlock {
  UnsupportedBlock(Object? stored)
      : stored = _deepCopy(stored),
        raw = stored is Map ? Map<String, dynamic>.unmodifiable(_deepCopy(stored) as Map<String, dynamic>) : const {};

  /// Exactly what was stored (a map, or any other value found in a block
  /// list), written back unchanged.
  final Object? stored;

  /// A copy of nested maps and lists; other values (strings, numbers,
  /// timestamps …) are kept as they are.
  static Object? _deepCopy(Object? value) => switch (value) {
        Map() => <String, dynamic>{for (final e in value.entries) e.key.toString(): _deepCopy(e.value)},
        List() => [for (final e in value) _deepCopy(e)],
        _ => value,
      };

  /// [stored] when it is a map; otherwise empty.
  final Map<String, dynamic> raw;

  @override
  String get id => raw['id'] is String ? raw['id'] as String : '';

  @override
  String get type => raw['type'] is String ? raw['type'] as String : '';

  @override
  Map<String, dynamic> toMap() => Map<String, dynamic>.of(raw);
}

/// The stored form of [blocks] (an unsupported entry exactly as stored).
List<Object?> storedBlockList(List<WebsiteBlock> blocks) => [for (final b in blocks) b is UnsupportedBlock ? b.stored : b.toMap()];

/// One column of a columns block: a stable [id] and the blocks in it.
@immutable
class BlockColumn {
  const BlockColumn({required this.id, this.blocks = const [], this.preserved = const {}});

  final String id;
  final List<WebsiteBlock> blocks;

  /// Stored keys this app doesn't know, kept unchanged.
  final Map<String, Object?> preserved;

  BlockColumn copyWith({String? id, List<WebsiteBlock>? blocks}) => BlockColumn(id: id ?? this.id, blocks: blocks ?? this.blocks, preserved: preserved);

  Map<String, dynamic> toMap() => {'id': id, 'blocks': storedBlockList(blocks), ...preserved};
}
