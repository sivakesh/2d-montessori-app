import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../website_content_models.dart';
import '../website_design.dart';

/// One field of a block type (or of an item inside a block). A block type
/// declares its fields once; parsing, saving, validation, the images a page
/// uses and its translatable text are all derived from these declarations,
/// so a new block type needs no bespoke code for any of them.
@immutable
sealed class FieldSpec {
  const FieldSpec(this.key, this.label, {this.required = false, this.omitDefault = false, this.group, this.shownWhen});

  /// The key in the stored block map.
  final String key;

  /// For admin messages ("Heading", "Button label").
  final String label;
  final bool required;

  /// Not stored while it holds its default (fields added after their
  /// block type's first version): a block saved before the field existed
  /// is written back exactly as it was stored.
  final bool omitDefault;

  /// The editor's collapsible group (its title) this field is shown in,
  /// with the fields around it in the same group; null: shown on its own.
  final String? group;

  /// Whether the editor shows this field, from the values of its item (or
  /// block) and of the block ([values] is [block] for a block's own
  /// fields): a setting of a feature that is turned off is left out. Null:
  /// always shown. Its value is kept either way.
  final bool Function(Map<String, Object?> values, Map<String, Object?> block)? shownWhen;

  /// The value when the field is absent.
  Object? get defaultValue;

  /// The value a newly added block or item starts with (usually the
  /// [defaultValue]).
  Object? get newValue => defaultValue;

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
    super.group, super.shownWhen,
    this.multiline = false,
    this.translatable = true,
    this.translationRequired = false,
    this.code = false,
  });

  final int maxLength;
  final bool multiline;

  /// Source code (a Custom HTML block's markup): edited in a monospaced
  /// box, in one language only (it should be [translatable] false).
  final bool code;

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
  const MediaFieldSpec(super.key, super.label, {super.required, super.omitDefault, super.group, super.shownWhen, this.removable = false});

  /// The editor shows the field's label and a Remove button (an optional
  /// image that can be taken off again).
  final bool removable;

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
  const LinkFieldSpec(super.key, super.label, {super.required, super.omitDefault, super.group, super.shownWhen});

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
  const ChoiceFieldSpec(super.key, super.label, {required this.options, required this.initial, this.initialForNew, this.optionLabels = const {}, super.omitDefault, super.group, super.shownWhen});

  final List<String> options;

  /// The value when absent.
  final String initial;

  /// What a newly added block or item starts with, when it differs from
  /// [initial] (which stays the value of those saved without the field).
  final String? initialForNew;

  /// How the editor names an option (the stored value when not listed).
  final Map<String, String> optionLabels;

  @override
  Object? get defaultValue => initial;

  @override
  Object? get newValue => initialForNew ?? initial;

  @override
  bool accepts(Object? raw) => raw is String;

  @override
  Object? parse(Object? raw) => raw as String;

  @override
  Object? serialize(Object? value) => value as String? ?? initial;
}

/// A whole number from [min] to [max] (in [unit]), or Automatic: not set
/// (null, never stored), so the block's own default applies, which the
/// editor names with [automaticLabel].
final class NumberFieldSpec extends FieldSpec {
  const NumberFieldSpec(super.key, super.label, {required this.min, required this.max, this.unit = '', this.automaticLabel = 'Automatic', super.group, super.shownWhen}) : super(omitDefault: true);

  final int min;
  final int max;
  final String unit;
  final String automaticLabel;

  /// [n] within range.
  bool allows(int n) => n >= min && n <= max;

  @override
  Object? get defaultValue => null;

  /// Whole numbers only (a stored 200.0 is 200).
  @override
  bool accepts(Object? raw) => raw is int || (raw is double && raw.isFinite && raw == raw.roundToDouble());

  @override
  Object? parse(Object? raw) => (raw as num).toInt();

  @override
  Object? serialize(Object? value) => value as int?;
}

/// On or off.
final class ToggleFieldSpec extends FieldSpec {
  const ToggleFieldSpec(super.key, super.label, {this.initial = false, this.exclusive = false, super.omitDefault, super.group, super.shownWhen});

  final bool initial;

  /// In a list's items: turning it on in one item turns it off in the
  /// others (one feature image).
  final bool exclusive;

  @override
  Object? get defaultValue => initial;

  @override
  bool accepts(Object? raw) => raw is bool;

  @override
  Object? parse(Object? raw) => raw as bool;

  @override
  Object? serialize(Object? value) => value as bool? ?? initial;
}

/// A colour chosen for one thing (an accreditation's card): [automatic]
/// (the block's own look; not stored when [omitDefault]), [transparent]
/// (whatever is behind it shows), a palette colour (`token:<id>`, which
/// follows the site design) or a custom `#RRGGBB`. [presets] are offered
/// first in the editor, by value, with their names.
final class ColorFieldSpec extends FieldSpec {
  const ColorFieldSpec(super.key, super.label, {this.presets = const {}, this.automaticLabel = 'the block: Automatic (white card)', super.omitDefault, super.group, super.shownWhen});

  /// What Automatic means here, for the editor.
  final String automaticLabel;

  static const automatic = 'auto';
  static const transparent = 'transparent';

  /// Suggested values (palette references or `#RRGGBB`) and their names.
  final Map<String, String> presets;

  /// Whether [value] is one this field can hold.
  static bool isValid(Object? value) => value == automatic || value == transparent || SiteDesign.isColorValue(value);

  @override
  Object? get defaultValue => automatic;

  @override
  bool accepts(Object? raw) => raw is String;

  @override
  Object? parse(Object? raw) => raw as String;

  @override
  Object? serialize(Object? value) => value as String? ?? automatic;
}

/// A list of items (buttons, gallery images, cards …), each with a stable
/// id and its own [itemFields].
final class ItemsFieldSpec extends FieldSpec {
  const ItemsFieldSpec(super.key, super.label, {required this.itemLabel, required this.itemFields, this.minItems = 0, required this.maxItems, this.badge});

  /// A short mark the editor shows beside item [index] of [items] (its
  /// role, e.g. "Feature image"), if any.
  final String? Function(List<BlockItem> items, int index)? badge;

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
