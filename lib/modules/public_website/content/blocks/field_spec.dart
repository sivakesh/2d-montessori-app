import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../website_content_models.dart';

/// One field of a block type (or of an item inside a block). A block type
/// declares its fields once; parsing, saving, validation, the images a page
/// uses and its translatable text are all derived from these declarations,
/// so a new block type needs no bespoke code for any of them.
@immutable
sealed class FieldSpec {
  const FieldSpec(this.key, this.label, {this.required = false, this.omitDefault = false});

  /// The key in the stored block map.
  final String key;

  /// For admin messages ("Heading", "Button label").
  final String label;
  final bool required;

  /// Not stored while it holds its default (fields added after their
  /// block type's first version): a block saved before the field existed
  /// is written back exactly as it was stored.
  final bool omitDefault;

  /// The value when the field is absent.
  Object? get defaultValue;

  /// Whether [raw] (present in the stored map) has this field's shape.
  bool accepts(Object? raw);

  /// [raw] (already [accepts]ed) as this field's value.
  Object? parse(Object? raw);

  /// The stored form of [value].
  Object? serialize(Object? value);
}

/// Text in every language ([LocalizedText]; all language keys are kept).
final class TextFieldSpec extends FieldSpec {
  const TextFieldSpec(
    super.key,
    super.label, {
    required this.maxLength,
    super.required,
    super.omitDefault,
    this.multiline = false,
    this.translatable = true,
    this.translationRequired = false,
  });

  final int maxLength;
  final bool multiline;

  /// Offered for translation (L2).
  final bool translatable;

  /// A translation must exist before the page can be published in a
  /// language (titles, headings, labels); otherwise the text falls back.
  final bool translationRequired;

  @override
  Object? get defaultValue => const LocalizedText();

  @override
  bool accepts(Object? raw) => raw is Map || raw is String;

  @override
  Object? parse(Object? raw) => LocalizedText.fromMap(raw);

  @override
  Object? serialize(Object? value) => (value as LocalizedText? ?? const LocalizedText()).toMap();
}

/// A media-library image, by id ('' = none).
final class MediaFieldSpec extends FieldSpec {
  const MediaFieldSpec(super.key, super.label, {super.required});

  @override
  Object? get defaultValue => '';

  @override
  bool accepts(Object? raw) => raw is String;

  @override
  Object? parse(Object? raw) => raw as String;

  @override
  Object? serialize(Object? value) => (value as String? ?? '').trim();
}

/// Where a button leads (checked with `SafeLinkTarget`).
final class LinkFieldSpec extends FieldSpec {
  const LinkFieldSpec(super.key, super.label, {super.required, super.omitDefault});

  @override
  Object? get defaultValue => '';

  @override
  bool accepts(Object? raw) => raw is String;

  @override
  Object? parse(Object? raw) => raw as String;

  @override
  Object? serialize(Object? value) => (value as String? ?? '').trim();
}

/// A website form (Settings → Website forms), by id ('' = none). The page
/// stores only the id: the form itself is read from its active version
/// when the page is shown, so one form can be on many pages.
final class FormRefFieldSpec extends FieldSpec {
  const FormRefFieldSpec(super.key, super.label, {super.required});

  static final idPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  @override
  Object? get defaultValue => '';

  @override
  bool accepts(Object? raw) => raw is String;

  @override
  Object? parse(Object? raw) => raw as String;

  @override
  Object? serialize(Object? value) => (value as String? ?? '').trim();
}

/// One of a fixed set of options. An unknown option is kept as stored (so a
/// newer app's option survives) and reported by validation.
final class ChoiceFieldSpec extends FieldSpec {
  const ChoiceFieldSpec(super.key, super.label, {required this.options, required this.initial, this.optionLabels = const {}, super.omitDefault});

  final List<String> options;
  final String initial;

  /// How the editor names an option (the stored value when not listed).
  final Map<String, String> optionLabels;

  @override
  Object? get defaultValue => initial;

  @override
  bool accepts(Object? raw) => raw is String;

  @override
  Object? parse(Object? raw) => raw as String;

  @override
  Object? serialize(Object? value) => value as String? ?? initial;
}

/// On or off.
final class ToggleFieldSpec extends FieldSpec {
  const ToggleFieldSpec(super.key, super.label, {this.initial = false, super.omitDefault});

  final bool initial;

  @override
  Object? get defaultValue => initial;

  @override
  bool accepts(Object? raw) => raw is bool;

  @override
  Object? parse(Object? raw) => raw as bool;

  @override
  Object? serialize(Object? value) => value as bool? ?? initial;
}

/// A list of items (buttons, gallery images, cards …), each with a stable
/// id and its own [itemFields].
final class ItemsFieldSpec extends FieldSpec {
  const ItemsFieldSpec(super.key, super.label, {required this.itemLabel, required this.itemFields, this.minItems = 0, required this.maxItems});

  final String itemLabel;
  final List<FieldSpec> itemFields;
  final int minItems;
  final int maxItems;

  @override
  Object? get defaultValue => const <BlockItem>[];

  /// A list of maps only: anything else is kept as stored, untouched.
  @override
  bool accepts(Object? raw) => raw is List && raw.every((e) => e is Map);

  @override
  Object? parse(Object? raw) => [for (final entry in raw as List) BlockItem.fromMap(entry as Map, itemFields)];

  @override
  Object? serialize(Object? value) => [for (final item in value as List<BlockItem>? ?? const []) item.toMap(itemFields)];
}

/// The columns of a columns block, each holding blocks. Parsed and saved
/// by the block registry (columns contain blocks of any type).
final class ColumnsFieldSpec extends FieldSpec {
  const ColumnsFieldSpec(super.key, super.label);

  @override
  Object? get defaultValue => const [];

  /// A list of maps only: anything else is kept as stored, untouched.
  @override
  bool accepts(Object? raw) => raw is List && raw.every((e) => e is Map);

  // The registry replaces these for columns (see BlockRegistry).
  @override
  Object? parse(Object? raw) => raw;

  @override
  Object? serialize(Object? value) => value;
}

/// One item of an [ItemsFieldSpec]: a stable [id] and its field values.
/// Stored keys this app doesn't know, and values of the wrong shape, are
/// kept and written back unchanged.
@immutable
class BlockItem {
  const BlockItem({required this.id, this.values = const {}, this.preserved = const {}});

  factory BlockItem.fromMap(Map raw, List<FieldSpec> fields) {
    final parsed = parseFieldValues(raw, fields);
    return BlockItem(id: raw['id'] is String ? raw['id'] as String : '', values: parsed.values, preserved: parsed.preserved);
  }

  final String id;
  final Map<String, Object?> values;

  /// Raw stored values kept as they were: unknown keys, and known keys
  /// whose stored value had the wrong shape (they win over [values]).
  final Map<String, Object?> preserved;

  T? value<T>(String key) => values[key] as T?;
  LocalizedText text(String key) => values[key] as LocalizedText? ?? const LocalizedText();
  String string(String key) => values[key] as String? ?? '';

  BlockItem withId(String newId) => BlockItem(id: newId, values: values, preserved: preserved);
  BlockItem withValue(String key, Object? value) =>
      BlockItem(id: id, values: {...values, key: value}, preserved: Map.of(preserved)..remove(key));

  Map<String, dynamic> toMap(List<FieldSpec> fields) => {'id': id, ...serializeFieldValues(values, preserved, fields)};
}

/// [raw]'s values for [fields] (defaults where absent) and everything to
/// keep as stored: keys no field declares (except `id`, `type`, `v`,
/// `hidden`, `style`, which blocks handle) and wrongly shaped values.
({Map<String, Object?> values, Map<String, Object?> preserved}) parseFieldValues(Map raw, List<FieldSpec> fields) {
  const structural = {'id', 'type', 'v', 'hidden', 'style'};
  final values = <String, Object?>{};
  final preserved = <String, Object?>{};
  final declared = {for (final f in fields) f.key};
  for (final field in fields) {
    if (!raw.containsKey(field.key) || raw[field.key] == null) {
      values[field.key] = field.defaultValue;
    } else if (field.accepts(raw[field.key])) {
      values[field.key] = field.parse(raw[field.key]);
    } else {
      values[field.key] = field.defaultValue;
      preserved[field.key] = raw[field.key];
    }
  }
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is String && !declared.contains(key) && !structural.contains(key)) preserved[key] = entry.value;
  }
  return (values: values, preserved: preserved);
}

/// The stored form of [values] for [fields], with [preserved] raw values
/// written back unchanged. A field that is [FieldSpec.omitDefault] and
/// holds its default isn't written.
Map<String, dynamic> serializeFieldValues(Map<String, Object?> values, Map<String, Object?> preserved, List<FieldSpec> fields) => {
      for (final field in fields)
        if (field.serialize(values[field.key] ?? field.defaultValue) case final stored
            when !field.omitDefault || jsonEncode(stored) != jsonEncode(field.serialize(field.defaultValue)))
          field.key: stored,
      ...preserved,
    };
