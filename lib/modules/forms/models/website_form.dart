import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../public_website/content/website_content_models.dart';

/// Where forms and their submissions are stored. Definitions and
/// submissions are kept apart:
/// - [forms]: each form as administrators edit it (private: its internal
///   description, status, versions and who changed it).
/// - [publicForms]: the active version of each form, visitor-facing fields
///   only ([PublicWebsiteForm]), written only when an administrator
///   activates it and removed when it is deactivated. The public website
///   reads nothing else.
/// - [submissions]: what visitors sent (private), each with a snapshot of
///   the form it answered; administrators' notes are in its [notes]
///   subcollection.
/// - [versions]: each activated version (private, never changed).
/// - [deletedForms]: what remains of a deleted form (private, never
///   changed), so its submissions stay understandable.
class FormCollections {
  static const forms = 'website_forms';
  static const publicForms = 'website_public_forms';
  static const submissions = 'website_form_submissions';
  static const notes = 'notes';
  static const versions = 'website_form_versions';
  static const deletedForms = 'website_deleted_forms';
}

/// Limits on a form's schema, so a definition stays small enough to load
/// and render on any phone.
class FormLimits {
  static const maxFields = 30;
  static const maxOptions = 20;
  static const maxTitle = 120;
  static const maxDescription = 1000;
  static const maxSuccessMessage = 500;
  static const maxLabel = 200;

  /// A checkbox's label is its consent statement, so it may be longer.
  static const maxConsentLabel = 600;
  static const maxPlaceholder = 120;
  static const maxOptionLabel = 100;
  static const maxShortText = 200;
  static const maxLongText = 3000;
  static const maxEmail = 254;
  static const maxPhone = 25;
  static const maxNote = 2000;
  static const maxHelpText = 300;
  static const maxErrorMessage = 200;
  static const maxNumber = 30;
  static const maxContentText = 2000;
  static const maxContentBlocks = 30;
}

/// Thrown by the forms services with a message for the admin.
class FormsException implements Exception {
  FormsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The requester isn't allowed to manage forms or read submissions.
class FormsUnauthorizedException implements Exception {
  FormsUnauthorizedException(this.role);

  final String role;

  @override
  String toString() => 'Only administrators can manage website forms and their submissions.';
}

/// A form field's kind. Stored as [id]; anything else is unknown and
/// refused.
enum FormFieldType {
  shortText('short_text', 'Short text'),
  email('email', 'Email'),
  phone('phone', 'Phone'),
  dropdown('dropdown', 'Dropdown'),
  radio('radio', 'Radio buttons'),
  checkbox('checkbox', 'Checkbox'),
  longText('long_text', 'Long text'),
  date('date', 'Date'),
  number('number', 'Number'),

  /// Documents ([FormAttachments]): configurable now, but visitors can't
  /// upload until a secure upload path exists.
  attachment('attachment', 'Document upload');

  const FormFieldType(this.id, this.label);

  final String id;
  final String label;

  bool get hasOptions => this == dropdown || this == radio;

  /// Typed in, with a placeholder.
  bool get isText => this == shortText || this == email || this == phone || this == longText || this == date || this == number;

  static FormFieldType? parse(Object? value) {
    for (final t in values) {
      if (t.id == value) return t;
    }
    return null;
  }
}

/// Stable ids: fields `f_…`, options `o_…`, content `c_…`, forms and submissions by
/// Firestore id (or a client key for submissions).
class FormIds {
  static final _random = Random.secure();
  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final fieldPattern = RegExp(r'^f_[a-z0-9]{8}$');
  static final optionPattern = RegExp(r'^o_[a-z0-9]{8}$');
  static final blockPattern = RegExp(r'^c_[a-z0-9]{8}$');
  static final docPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// A submission key: chosen once per filled-in form, so sending it again
  /// (a double click, a retry after a lost connection) stores one
  /// submission.
  static final submissionKeyPattern = RegExp(r'^[A-Za-z0-9]{20,64}$');

  static String _suffix(int n) => String.fromCharCodes([for (var i = 0; i < n; i++) _chars.codeUnitAt(_random.nextInt(_chars.length))]);
  static String field() => 'f_${_suffix(8)}';
  static String option() => 'o_${_suffix(8)}';
  static String block() => 'c_${_suffix(8)}';
  static String submissionKey() => _suffix(32);
}

/// The entries of stored [raw] this version doesn't read ([known] are the
/// keys it does): kept as they are and written back unchanged, so saving a
/// form never loses what a newer version stored.
Map<String, Object?> formExtraKeys(Map<dynamic, dynamic> raw, Set<String> known) => {
      for (final e in raw.entries)
        if (e.key is String && !known.contains(e.key)) e.key as String: e.value,
    };

/// Whether two stored values are the same (maps and lists by content).
bool formDeepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.entries.every((e) => b.containsKey(e.key) && formDeepEquals(e.value, b[e.key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!formDeepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

@immutable
class FormFieldOption {
  const FormFieldOption({required this.id, required this.label, this.extra = const {}});

  factory FormFieldOption.create(String label) => FormFieldOption(id: FormIds.option(), label: LocalizedText(en: label));

  /// The keys an option has; any other stored key is kept in [extra].
  static const knownKeys = {'id', 'label'};

  final String id;
  final LocalizedText label;

  /// Stored keys this version doesn't read, written back unchanged.
  final Map<String, Object?> extra;

  Map<String, dynamic> toMap() => {...extra, 'id': id, 'label': label.toMap()};

  FormFieldOption copyWith({LocalizedText? label}) => FormFieldOption(id: id, label: label ?? this.label, extra: extra);

  @override
  bool operator ==(Object other) => other is FormFieldOption && other.id == id && other.label == label && formDeepEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(id, label, extra.length);
}

/// One item of a form, in the order visitors see it: a question
/// ([WebsiteFormField]) or content between questions ([FormContentBlock]:
/// a section heading, text, an image or a divider). Every item has a
/// stable id that never changes when it is moved or edited, so earlier
/// submissions (which keep a snapshot of the questions) stay readable.
@immutable
sealed class FormItem {
  const FormItem();

  /// Reads a stored item: content blocks are marked `kind: content`;
  /// anything else is a question (as stored before content existed).
  factory FormItem.fromMap(Object? raw) =>
      raw is Map && raw['kind'] == FormContentBlock.kind ? FormContentBlock.fromMap(raw) : WebsiteFormField.fromMap(raw);

  String get id;
  Map<String, dynamic> toMap();
  List<String> problems({required bool complete});

  /// The same item with new ids (its own and its options'), for a
  /// duplicated form.
  FormItem withFreshIds();

  /// How the builder names it ("Email", "Section heading: About you").
  String get displayLabel;
}

/// One question of a form. [type] is null when the stored type is unknown
/// ([rawType]): such a field is kept as stored but refused by validation.
///
/// Optional settings, each stored only when set (so a question saved
/// before they existed is stored exactly as before): [helpText] under the
/// question, [errorMessage] in place of the standard one, [minLength] and
/// [maxLength] for text, [min] and [max] for numbers, [minDate] and
/// [maxDate] for dates, and an attachment's allowed file types, size and
/// count.
@immutable
class WebsiteFormField extends FormItem {
  const WebsiteFormField({
    required this.id,
    required this.type,
    required this.label,
    this.rawType,
    this.required = false,
    this.placeholder = const LocalizedText(),
    this.options = const [],
    this.helpText = const LocalizedText(),
    this.errorMessage = const LocalizedText(),
    this.minLength,
    this.maxLength,
    this.min,
    this.max,
    this.minDate,
    this.maxDate,
    this.allowedFileTypes = FormAttachments.defaultTypes,
    this.maxFileSizeMb = FormAttachments.defaultMaxSizeMb,
    this.maxFiles = 1,
    this.rows,
    this.counter,
    this.resize,
    this.width,
    this.defaultValue,
    this.hidden = false,
    this.malformed = const [],
    this.extra = const {},
  });

  /// The keys a question has; any other stored key is kept in [extra].
  static const knownKeys = {
    'id', 'type', 'label', 'required', 'placeholder', 'options', 'helpText', 'errorMessage', 'minLength', 'maxLength', 'min', 'max', 'minDate', 'maxDate', //
    'allowedFileTypes', 'maxFileSizeMb', 'maxFiles', 'rows', 'counter', 'resize', 'width', 'defaultValue', 'hidden',
  };

  /// Long text: the rows shown at first (and the fewest), 2 to 12; 4
  /// unless set.
  static const minRows = 2;
  static const maxRows = 12;
  static const defaultRows = 4;

  /// The character counter: `auto` (unset; long text, and text with a
  /// most-characters limit, show it), `show` or `hide`.
  static const counters = ['auto', 'show', 'hide'];

  /// Long text's height: `grow` (unset; from its rows up as the answer
  /// grows, to [maxRows] or more) or `fixed` (its rows; longer answers
  /// scroll inside).
  static const resizes = ['grow', 'fixed'];

  /// How much of a row a question takes on wider screens (`full`, `half`,
  /// `third`); unset, short questions pair up two to a row as before. On
  /// phones every question takes the whole row.
  static const widths = ['full', 'half', 'third'];

  factory WebsiteFormField.create(FormFieldType type, String label, {bool required = false, List<String> options = const [], String placeholder = ''}) =>
      WebsiteFormField(
        id: FormIds.field(),
        type: type,
        label: LocalizedText(en: label),
        required: required,
        placeholder: LocalizedText(en: placeholder),
        options: [for (final o in options) FormFieldOption.create(o)],
      );

  /// Reads a stored field, noting anything malformed ([malformed]) rather
  /// than failing.
  factory WebsiteFormField.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    final problems = <String>[];
    final rawOptions = map['options'];
    final options = <FormFieldOption>[];
    if (rawOptions != null && rawOptions is! List) problems.add('its options can’t be read');
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is Map && o['id'] is String) {
          options.add(FormFieldOption(id: o['id'] as String, label: LocalizedText.fromMap(o['label']), extra: formExtraKeys(o, FormFieldOption.knownKeys)));
        } else {
          problems.add('an option can’t be read');
        }
      }
    }
    if (raw is! Map) problems.add('it can’t be read');
    int? whole(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is int) return v;
      problems.add('its $key can’t be read');
      return null;
    }

    num? number(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is num && v.isFinite) return v;
      problems.add('its $key can’t be read');
      return null;
    }

    String? day(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is String) return v;
      problems.add('its $key can’t be read');
      return null;
    }

    String? choice(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is String) return v;
      problems.add('its $key can’t be read');
      return null;
    }

    final defaultValue = map['defaultValue'];
    if (defaultValue != null && defaultValue is! String) problems.add('its default answer can’t be read');
    if (map['hidden'] != null && map['hidden'] is! bool) problems.add('its visibility can’t be read');
    final types = map['allowedFileTypes'];
    if (types != null && (types is! List || types.any((t) => t is! String))) problems.add('its file types can’t be read');
    return WebsiteFormField(
      id: map['id'] is String ? map['id'] as String : '',
      type: FormFieldType.parse(map['type']),
      rawType: map['type']?.toString(),
      label: LocalizedText.fromMap(map['label']),
      required: map['required'] == true,
      placeholder: LocalizedText.fromMap(map['placeholder']),
      options: options,
      helpText: LocalizedText.fromMap(map['helpText']),
      errorMessage: LocalizedText.fromMap(map['errorMessage']),
      minLength: whole('minLength'),
      maxLength: whole('maxLength'),
      min: number('min'),
      max: number('max'),
      minDate: day('minDate'),
      maxDate: day('maxDate'),
      allowedFileTypes: types is List && types.every((t) => t is String) ? [for (final t in types) t as String] : FormAttachments.defaultTypes,
      maxFileSizeMb: whole('maxFileSizeMb') ?? FormAttachments.defaultMaxSizeMb,
      maxFiles: whole('maxFiles') ?? 1,
      rows: whole('rows'),
      counter: choice('counter'),
      resize: choice('resize'),
      width: choice('width'),
      defaultValue: defaultValue is String ? defaultValue : null,
      hidden: map['hidden'] == true,
      malformed: problems,
      extra: {
        ...formExtraKeys(map, knownKeys),
        // A placeholder on a type that shows none (say, a dropdown that was
        // short text): kept as stored, so changing the type back finds it.
        if (map.containsKey('placeholder') && !(FormFieldType.parse(map['type'])?.isText ?? false)) 'placeholder': map['placeholder'],
      },
    );
  }

  @override
  final String id;
  final FormFieldType? type;

  /// The stored type, as read (for an unknown type's message).
  final String? rawType;
  final LocalizedText label;
  final bool required;
  final LocalizedText placeholder;

  /// Dropdown and radio buttons only.
  final List<FormFieldOption> options;

  /// Shown under the question.
  final LocalizedText helpText;

  /// Shown instead of the standard message when the answer isn't accepted.
  final LocalizedText errorMessage;

  /// Short and long text: the fewest and most characters accepted.
  final int? minLength;
  final int? maxLength;

  /// Numbers: the smallest and largest accepted.
  final num? min;
  final num? max;

  /// Dates (`YYYY-MM-DD`): the earliest and latest accepted.
  final String? minDate;
  final String? maxDate;

  /// Attachments: file types (extensions from [FormAttachments.types]),
  /// the largest file in MB, and how many files.
  final List<String> allowedFileTypes;
  final int maxFileSizeMb;
  final int maxFiles;

  /// Long text's first (and fewest) rows ([defaultRows] unless set).
  final int? rows;

  /// The character counter ([counters]; null is `auto`).
  final String? counter;

  /// Long text's height ([resizes]; null is `grow`).
  final String? resize;

  /// Its share of a row on wider screens ([widths]; null is automatic).
  final String? width;

  /// The answer filled in at first, as an answer is written (text, a
  /// number, `YYYY-MM-DD`, or an option's id). Never for a checkbox, so
  /// consent is never given in advance.
  final String? defaultValue;

  /// Hidden from visitors: kept in the form (and its settings), but left
  /// out of the version visitors see, so it is never asked nor required.
  final bool hidden;

  /// What couldn't be read when it was loaded.
  final List<String> malformed;

  /// Stored keys this version doesn't read, written back unchanged (in
  /// the draft, the visitor copy and submission snapshots alike).
  final Map<String, Object?> extra;

  /// The longest answer accepted.
  int get maxAnswerLength => maxLength ?? _typeMaxLength;

  /// Long text's rows at first.
  int get visibleRows => (rows ?? defaultRows).clamp(minRows, maxRows);

  /// Whether the character counter is shown.
  bool get showsCounter => switch (counter) {
        'show' => true,
        'hide' => false,
        _ => type == FormFieldType.longText || maxLength != null,
      };

  /// Its share of a row on wider screens, or null (automatic).
  double? get widthFraction => switch (width) { 'full' => 1.0, 'half' => 0.5, 'third' => 1 / 3, _ => null };

  /// Whether this type can have a default answer.
  bool get takesDefault => type != null && type != FormFieldType.checkbox && type != FormFieldType.attachment;

  int get _typeMaxLength => switch (type) {
        FormFieldType.longText => FormLimits.maxLongText,
        FormFieldType.email => FormLimits.maxEmail,
        FormFieldType.phone => FormLimits.maxPhone,
        FormFieldType.number => FormLimits.maxNumber,
        _ => FormLimits.maxShortText,
      };

  @override
  String get displayLabel => '${type?.label ?? 'Unsupported field'}${label.en.trim().isEmpty ? '' : ': ${label.en.trim()}'}';

  @override
  Map<String, dynamic> toMap() => {
        ...extra,
        'id': id,
        'type': type?.id ?? rawType,
        'label': label.toMap(),
        'required': required,
        if ((type?.isText ?? false) || (!extra.containsKey('placeholder') && !placeholder.isEmpty)) 'placeholder': placeholder.toMap(),
        if (type?.hasOptions ?? false) 'options': [for (final o in options) o.toMap()],
        if (!helpText.isEmpty) 'helpText': helpText.toMap(),
        if (!errorMessage.isEmpty) 'errorMessage': errorMessage.toMap(),
        'minLength': ?minLength,
        'maxLength': ?maxLength,
        'min': ?min,
        'max': ?max,
        'minDate': ?minDate,
        'maxDate': ?maxDate,
        if (type == FormFieldType.attachment) ...{
          'allowedFileTypes': allowedFileTypes,
          'maxFileSizeMb': maxFileSizeMb,
          'maxFiles': maxFiles,
        },
        'rows': ?rows,
        'counter': ?counter,
        'resize': ?resize,
        'width': ?width,
        'defaultValue': ?defaultValue,
        if (hidden) 'hidden': true,
      };

  WebsiteFormField copyWith({
    FormFieldType? type,
    LocalizedText? label,
    bool? required,
    LocalizedText? placeholder,
    List<FormFieldOption>? options,
    LocalizedText? helpText,
    LocalizedText? errorMessage,
    int? Function()? minLength,
    int? Function()? maxLength,
    num? Function()? min,
    num? Function()? max,
    String? Function()? minDate,
    String? Function()? maxDate,
    List<String>? allowedFileTypes,
    int? maxFileSizeMb,
    int? maxFiles,
    int? Function()? rows,
    String? Function()? counter,
    String? Function()? resize,
    String? Function()? width,
    String? Function()? defaultValue,
    bool? hidden,
  }) =>
      WebsiteFormField(
        id: id,
        type: type ?? this.type,
        rawType: (type ?? this.type)?.id ?? rawType,
        label: label ?? this.label,
        required: required ?? this.required,
        placeholder: placeholder ?? this.placeholder,
        options: options ?? this.options,
        helpText: helpText ?? this.helpText,
        errorMessage: errorMessage ?? this.errorMessage,
        minLength: minLength != null ? minLength() : this.minLength,
        maxLength: maxLength != null ? maxLength() : this.maxLength,
        min: min != null ? min() : this.min,
        max: max != null ? max() : this.max,
        minDate: minDate != null ? minDate() : this.minDate,
        maxDate: maxDate != null ? maxDate() : this.maxDate,
        allowedFileTypes: allowedFileTypes ?? this.allowedFileTypes,
        maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
        maxFiles: maxFiles ?? this.maxFiles,
        rows: rows != null ? rows() : this.rows,
        counter: counter != null ? counter() : this.counter,
        resize: resize != null ? resize() : this.resize,
        width: width != null ? width() : this.width,
        defaultValue: defaultValue != null ? defaultValue() : this.defaultValue,
        hidden: hidden ?? this.hidden,
        extra: extra,
      );

  /// The same question with new ids (its own and its options'; a default
  /// option follows its option).
  @override
  WebsiteFormField withFreshIds() {
    final fresh = {for (final o in options) o.id: FormIds.option()};
    return WebsiteFormField(
        id: FormIds.field(),
        type: type,
        rawType: rawType,
        label: label,
        required: required,
        placeholder: placeholder,
        options: [for (final o in options) FormFieldOption(id: fresh[o.id]!, label: o.label, extra: o.extra)],
        helpText: helpText,
        errorMessage: errorMessage,
        minLength: minLength,
        maxLength: maxLength,
        min: min,
        max: max,
        minDate: minDate,
        maxDate: maxDate,
        allowedFileTypes: allowedFileTypes,
        maxFileSizeMb: maxFileSizeMb,
        maxFiles: maxFiles,
        rows: rows,
        counter: counter,
        resize: resize,
        width: width,
        defaultValue: type?.hasOptions ?? false ? (fresh[defaultValue] ?? defaultValue) : defaultValue,
        hidden: hidden,
        extra: extra,
      );
  }

  String optionLabel(String optionId) {
    for (final o in options) {
      if (o.id == optionId) return o.label.en;
    }
    return optionId;
  }

  /// Problems with this field's definition. [complete]: also what must be
  /// filled in before the form can be activated.
  @override
  List<String> problems({required bool complete}) {
    final type = this.type;
    final cap = _typeMaxLength;
    final from = minDate == null ? null : parseFormDate(minDate!);
    final to = maxDate == null ? null : parseFormDate(maxDate!);
    final textual = type == FormFieldType.shortText || type == FormFieldType.longText;
    return [
      ...malformed,
      if (!FormIds.fieldPattern.hasMatch(id)) 'its id isn’t valid',
      if (type == null) 'its type “${rawType ?? ''}” isn’t supported',
      ...label.problems(type == FormFieldType.checkbox ? FormLimits.maxConsentLabel : FormLimits.maxLabel, 'The label'),
      if (complete && label.en.trim().isEmpty) 'enter its label in English',
      ...placeholder.problems(FormLimits.maxPlaceholder, 'The placeholder'),
      ...helpText.problems(FormLimits.maxHelpText, 'The help text'),
      ...errorMessage.problems(FormLimits.maxErrorMessage, 'The error message'),
      if (type != null && !type.hasOptions && options.isNotEmpty) 'only dropdowns and radio buttons have options',
      if (type?.hasOptions ?? false) ...[
        if (options.length > FormLimits.maxOptions) 'at most ${FormLimits.maxOptions} options',
        if (complete && options.length < 2) 'add at least two options',
        if (options.map((o) => o.id).toSet().length != options.length) 'two options have the same id',
        for (final (i, o) in options.indexed) ...[
          if (!FormIds.optionPattern.hasMatch(o.id)) 'option ${i + 1}: its id isn’t valid',
          ...o.label.problems(FormLimits.maxOptionLabel, 'Option ${i + 1}'),
          if (complete && o.label.en.trim().isEmpty) 'option ${i + 1}: enter its label in English',
        ],
        if (complete && {for (final o in options) o.label.en.trim().toLowerCase()}.length != options.length) 'two options have the same label',
      ],
      if ((minLength != null || maxLength != null) && !textual) 'only short and long text have a length limit',
      if (minLength != null && (minLength! < 0 || minLength! > cap)) 'the minimum length must be between 0 and $cap',
      if (maxLength != null && (maxLength! < 1 || maxLength! > cap)) 'the maximum length must be between 1 and $cap',
      if (minLength != null && maxLength != null && minLength! > maxLength!) 'the minimum length is more than the maximum',
      if ((min != null || max != null) && type != FormFieldType.number) 'only numbers have a smallest and largest value',
      if (min != null && max != null && min! > max!) 'the smallest value is more than the largest',
      if ((minDate != null || maxDate != null) && type != FormFieldType.date) 'only dates have an earliest and latest date',
      if (minDate != null && from == null) 'the earliest date must be written YYYY-MM-DD',
      if (maxDate != null && to == null) 'the latest date must be written YYYY-MM-DD',
      if (from != null && to != null && from.isAfter(to)) 'the earliest date is after the latest',
      if (rows != null && type != FormFieldType.longText) 'only long text has rows',
      if (rows != null && (rows! < minRows || rows! > maxRows)) 'show $minRows to $maxRows rows',
      if (counter != null && !counters.contains(counter)) 'its counter setting “$counter” isn’t supported',
      if (counter != null && !textual) 'only short and long text have a character counter',
      if (resize != null && !resizes.contains(resize)) 'its height setting “$resize” isn’t supported',
      if (resize != null && type != FormFieldType.longText) 'only long text has a height setting',
      if (width != null && !widths.contains(width)) 'its width “$width” isn’t supported',
      if (defaultValue != null && type != null && !takesDefault) 'a ${type.label.toLowerCase()} has no default answer',
      if (defaultValue != null && takesDefault && defaultValue!.trim().isNotEmpty && validateFormAnswers([copyWith(required: false)], {id: defaultValue}).errors.isNotEmpty)
        'its default answer isn’t one it accepts',
      if (type == FormFieldType.attachment) ...[
        if (allowedFileTypes.isEmpty) 'choose at least one file type',
        if (allowedFileTypes.any((t) => !FormAttachments.types.containsKey(t))) 'a file type isn’t supported',
        if (allowedFileTypes.toSet().length != allowedFileTypes.length) 'a file type is listed twice',
        if (maxFileSizeMb < 1 || maxFileSizeMb > FormAttachments.maxSizeMb) 'the largest file must be 1 to ${FormAttachments.maxSizeMb} MB',
        if (maxFiles < 1 || maxFiles > FormAttachments.maxFiles) 'allow 1 to ${FormAttachments.maxFiles} files',
      ],
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is WebsiteFormField &&
      other.id == id &&
      (other.type?.id ?? other.rawType) == (type?.id ?? rawType) &&
      other.label == label &&
      other.required == required &&
      other.placeholder == placeholder &&
      listEquals(other.options, options) &&
      other.helpText == helpText &&
      other.errorMessage == errorMessage &&
      other.minLength == minLength &&
      other.maxLength == maxLength &&
      other.min == min &&
      other.max == max &&
      other.minDate == minDate &&
      other.maxDate == maxDate &&
      formDeepEquals(other.extra, extra) &&
      other.rows == rows &&
      other.counter == counter &&
      other.resize == resize &&
      other.width == width &&
      other.defaultValue == defaultValue &&
      other.hidden == hidden &&
      (type != FormFieldType.attachment ||
          (listEquals(other.allowedFileTypes, allowedFileTypes) && other.maxFileSizeMb == maxFileSizeMb && other.maxFiles == maxFiles));

  @override
  int get hashCode => Object.hash(id, type?.id ?? rawType, label, required, placeholder, Object.hashAll(options), helpText, errorMessage, minLength, maxLength, min, max, minDate, maxDate, Object.hash(rows, counter, resize, width, defaultValue, hidden, extra.length));
}

/// Document attachments: the file types a field may allow and the limits.
///
/// **Visitors can't upload yet** ([publicUploadsEnabled] is false): there
/// is no trusted upload path or verified Storage rules, so attachment
/// fields are shown disabled, never required, and any answer to one is
/// refused. Documents must never go to a world-readable Storage path or be
/// served by public URLs; the backend must check each file's type and
/// size when uploads are built (`docs/website_forms.md`).
class FormAttachments {
  static const publicUploadsEnabled = false;

  /// Extension → MIME type.
  static const types = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'png': 'image/png',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  };
  static const defaultTypes = ['pdf'];
  static const defaultMaxSizeMb = 5;
  static const maxSizeMb = 10;
  static const maxFiles = 5;

  static List<String> mimeTypesFor(List<String> extensions) => [for (final e in extensions) ?types[e]];
}

/// Content between questions.
enum FormBlockType {
  heading('heading', 'Section heading'),
  text('text', 'Text or instructions'),
  image('image', 'Image'),
  divider('divider', 'Divider'),

  /// Starts a new step of a multi-step form ([WebsiteForm.multiStep]); its
  /// title names the step. On a single-page form it shows nothing.
  pageBreak('page_break', 'Page break');

  const FormBlockType(this.id, this.label);

  final String id;
  final String label;

  static FormBlockType? parse(Object? value) {
    for (final t in values) {
      if (t.id == value) return t;
    }
    return null;
  }
}

/// Content placed anywhere among a form's questions: a section heading
/// (with an optional description), text or instructions, an image from
/// the website media library (by id only: alt text, publication and
/// consent come from the library), or a divider.
@immutable
class FormContentBlock extends FormItem {
  const FormContentBlock({
    required this.id,
    required this.type,
    this.rawType,
    this.title = const LocalizedText(),
    this.body = const LocalizedText(),
    this.mediaId = '',
    this.hidden = false,
    this.malformed = const [],
    this.extra = const {},
  });

  /// The keys a content item has; any other stored key is kept in [extra].
  static const knownKeys = {'kind', 'id', 'type', 'title', 'body', 'mediaId', 'hidden'};

  factory FormContentBlock.create(FormBlockType type) => FormContentBlock(id: FormIds.block(), type: type);

  factory FormContentBlock.fromMap(Map<dynamic, dynamic> map) {
    final media = map['mediaId'];
    return FormContentBlock(
      id: map['id'] is String ? map['id'] as String : '',
      type: FormBlockType.parse(map['type']),
      rawType: map['type']?.toString(),
      title: LocalizedText.fromMap(map['title']),
      body: LocalizedText.fromMap(map['body']),
      mediaId: media is String ? media : '',
      hidden: map['hidden'] == true,
      malformed: [
        if (media != null && media is! String) 'its image can’t be read',
        if (map['hidden'] != null && map['hidden'] is! bool) 'its visibility can’t be read',
      ],
      extra: formExtraKeys(map, knownKeys),
    );
  }

  /// How stored content blocks are marked.
  static const kind = 'content';

  @override
  final String id;
  final FormBlockType? type;
  final String? rawType;

  /// A section heading's text.
  final LocalizedText title;

  /// A section's description, the text, or an image's caption.
  final LocalizedText body;

  /// An image block's website image.
  final String mediaId;

  /// Hidden from visitors (kept in the form, left out of the version
  /// visitors see).
  final bool hidden;
  final List<String> malformed;

  /// Stored keys this version doesn't read, written back unchanged.
  final Map<String, Object?> extra;

  @override
  String get displayLabel {
    final text = (type == FormBlockType.heading || type == FormBlockType.pageBreak ? title : body).en.trim();
    return '${type?.label ?? 'Unsupported content'}${text.isEmpty ? '' : ': ${text.length > 40 ? '${text.substring(0, 40)}…' : text}'}';
  }

  @override
  Map<String, dynamic> toMap() => {
        ...extra,
        'kind': kind,
        'id': id,
        'type': type?.id ?? rawType,
        if (type == FormBlockType.heading || type == FormBlockType.pageBreak) 'title': title.toMap(),
        if (type == FormBlockType.heading || type == FormBlockType.text || type == FormBlockType.image) 'body': body.toMap(),
        if (type == FormBlockType.image) 'mediaId': mediaId.trim(),
        if (hidden) 'hidden': true,
      };

  FormContentBlock copyWith({LocalizedText? title, LocalizedText? body, String? mediaId, bool? hidden}) => FormContentBlock(
        id: id,
        type: type,
        rawType: rawType,
        title: title ?? this.title,
        body: body ?? this.body,
        mediaId: mediaId ?? this.mediaId,
        hidden: hidden ?? this.hidden,
        extra: extra,
      );

  @override
  FormContentBlock withFreshIds() => FormContentBlock(id: FormIds.block(), type: type, rawType: rawType, title: title, body: body, mediaId: mediaId, hidden: hidden, extra: extra);

  @override
  List<String> problems({required bool complete}) => [
        ...malformed,
        if (!FormIds.blockPattern.hasMatch(id)) 'its id isn’t valid',
        if (type == null) 'its type “${rawType ?? ''}” isn’t supported',
        ...title.problems(FormLimits.maxTitle, 'The heading'),
        ...body.problems(FormLimits.maxContentText, 'The text'),
        if (complete && type == FormBlockType.heading && title.en.trim().isEmpty) 'enter the heading in English',
        if (complete && type == FormBlockType.text && body.en.trim().isEmpty) 'enter the text in English',
        if (type == FormBlockType.image && mediaId.trim().isNotEmpty && !FormIds.docPattern.hasMatch(mediaId.trim())) 'its image can’t be identified',
        if (complete && type == FormBlockType.image && mediaId.trim().isEmpty) 'choose its image',
      ];

  @override
  bool operator ==(Object other) =>
      other is FormContentBlock &&
      other.id == id &&
      (other.type?.id ?? other.rawType) == (type?.id ?? rawType) &&
      other.title == title &&
      other.body == body &&
      other.mediaId == mediaId &&
      other.hidden == hidden &&
      formDeepEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(id, type?.id ?? rawType, title, body, mediaId, hidden, extra.length);
}

/// A form's schema problems, each prefixed with where it is.
///
/// [items] (or, for a list of questions only, [fields]) in order.
/// [complete]: also what must be filled in before activation (a title,
/// labels, options, a success message, at least one field).
/// [requireMetadata]: also the description and cover image every form
/// needs before it is activated (visitor copies saved before they existed
/// are still shown, so the public website doesn't check them).
List<String> formSchemaProblems({
  required LocalizedText title,
  List<WebsiteFormField>? fields,
  List<FormItem>? items,
  required LocalizedText successMessage,
  LocalizedText description = const LocalizedText(),
  String? coverMediaId,
  String internalDescription = '',
  LocalizedText completionTitle = const LocalizedText(),
  required bool complete,
  bool requireMetadata = false,
}) {
  final all = items ?? fields ?? const <FormItem>[];
  final questions = all.whereType<WebsiteFormField>().toList();
  final content = all.whereType<FormContentBlock>().toList();
  final ids = <String>{};
  final cover = coverMediaId?.trim() ?? '';
  return [
    ...title.problems(FormLimits.maxTitle, 'The title'),
    if (complete && title.en.trim().isEmpty) 'Enter the form’s title in English.',
    ...description.problems(FormLimits.maxDescription, 'The description'),
    if (requireMetadata && description.en.trim().isEmpty) 'Enter the form’s description in English.',
    if (cover.isNotEmpty && !FormIds.docPattern.hasMatch(cover)) 'The cover image can’t be identified.',
    if (requireMetadata && cover.isEmpty) 'Choose the form’s cover image.',
    if (internalDescription.trim().length > FormLimits.maxDescription) 'The internal description must be ${FormLimits.maxDescription} characters or fewer.',
    ...successMessage.problems(FormLimits.maxSuccessMessage, 'The success message'),
    if (complete && successMessage.en.trim().isEmpty) 'Enter the success message in English.',
    if (questions.length > FormLimits.maxFields) 'A form can have at most ${FormLimits.maxFields} fields.',
    if (content.length > FormLimits.maxContentBlocks) 'A form can have at most ${FormLimits.maxContentBlocks} headings, texts, images and dividers.',
    if (complete && questions.isEmpty) 'Add at least one field.',
    if (complete && questions.isNotEmpty && questions.every((q) => q.hidden)) 'Every field is hidden: show at least one to visitors.',
    ...completionTitle.problems(FormLimits.maxTitle, 'The completion heading'),
    for (final (i, f) in questions.indexed) ...[
      if (!ids.add(f.id)) 'Field ${i + 1}: its id is used by another field.',
      for (final p in f.problems(complete: complete)) 'Field ${i + 1}${f.label.en.trim().isEmpty ? '' : ' (${f.label.en.trim()})'}: ${p.endsWith('.') ? p : '$p.'}',
    ],
    for (final (i, b) in content.indexed) ...[
      if (!ids.add(b.id)) 'Content ${i + 1}: its id is used by another item.',
      for (final p in b.problems(complete: complete)) 'Content ${i + 1} (${b.type?.label ?? 'unsupported'}): ${p.endsWith('.') ? p : '$p.'}',
    ],
  ];
}

List<WebsiteFormField> _fieldsFrom(Object? raw) => raw is List ? [for (final f in raw) WebsiteFormField.fromMap(f)] : const [];

/// The items stored in [map]: `items` when present, else (stored before
/// content blocks existed) its `fields`.
List<FormItem> _itemsFrom(Map<String, dynamic> map) {
  final raw = map['items'];
  return raw is List ? [for (final i in raw) FormItem.fromMap(i)] : _fieldsFrom(map['fields']);
}

/// [items] with its questions replaced, in order, by [fields] (content
/// stays where it is; extra fields go at the end).
List<FormItem> _replaceFields(List<FormItem> items, List<WebsiteFormField> fields) {
  final next = fields.iterator;
  final result = <FormItem>[];
  for (final item in items) {
    if (item is FormContentBlock) {
      result.add(item);
    } else if (next.moveNext()) {
      result.add(next.current);
    }
  }
  while (next.moveNext()) {
    result.add(next.current);
  }
  return result;
}

/// Every website image [items] and [coverMediaId] use.
List<String> _mediaIds(String? coverMediaId, List<FormItem> items) => {
      if ((coverMediaId ?? '').trim().isNotEmpty) coverMediaId!.trim(),
      for (final b in items.whereType<FormContentBlock>())
        if (b.type == FormBlockType.image && b.mediaId.trim().isNotEmpty) b.mediaId.trim(),
    }.toList();

String? _cover(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

enum WebsiteFormStatus {
  /// Being written; never shown to visitors.
  draft('draft', 'Draft'),

  /// Visitors can see and submit its active version.
  active('active', 'Active'),

  /// Taken off the website; its submissions are kept.
  inactive('inactive', 'Inactive');

  const WebsiteFormStatus(this.id, this.label);

  final String id;
  final String label;

  static WebsiteFormStatus parse(Object? value) => values.firstWhere((s) => s.id == value, orElse: () => draft);
}

/// A form as administrators edit it (in [FormCollections.forms]).
///
/// [version] is the number of the version visitors see (or last saw):
/// each activation of a changed schema gives it the next number, so a
/// submission's version says exactly which questions it answered. 0 means
/// it has never been active. Editing an active form changes only this
/// definition; visitors keep the active version until it is activated
/// again.
///
/// Its content is [items] (questions and content, in order); [fields] are
/// its questions. Both are stored, so a reader from before content blocks
/// existed still finds the questions.
@immutable
class WebsiteForm {
  WebsiteForm({
    required this.id,
    required this.schoolId,
    required this.title,
    this.description = const LocalizedText(),
    this.coverMediaId,
    this.internalDescription = '',
    List<FormItem>? items,
    List<WebsiteFormField> fields = const [],
    this.successMessage = const LocalizedText(),
    this.status = WebsiteFormStatus.draft,
    this.version = 0,
    this.template = 'custom',
    this.createdAt,
    this.updatedAt,
    this.activatedAt,
    this.activatedSchema,
    this.multiStep = false,
    this.reviewStep = false,
    this.completionTitle = const LocalizedText(),
    this.extra = const {},
  }) : items = List.unmodifiable(items ?? fields);

  /// Every key this version writes on a form's document.
  static const knownKeys = {
    'title', 'description', 'coverMediaId', 'internalDescription', 'items', 'fields', 'mediaIds', 'successMessage', 'multiStep', 'reviewStep', //
    'completionTitle', 'schoolId', 'status', 'version', 'template', 'createdAt', 'updatedAt', 'updatedById', 'updatedByName', 'activatedAt',
    'activatedSchema', 'deactivatedAt', 'duplicatedFrom',
  };

  factory WebsiteForm.fromMap(String id, Map<String, dynamic> map) => WebsiteForm(
        id: id,
        schoolId: map['schoolId']?.toString() ?? '',
        title: LocalizedText.fromMap(map['title']),
        description: LocalizedText.fromMap(map['description']),
        coverMediaId: _cover(map['coverMediaId']),
        internalDescription: map['internalDescription']?.toString() ?? '',
        items: _itemsFrom(map),
        successMessage: LocalizedText.fromMap(map['successMessage']),
        status: WebsiteFormStatus.parse(map['status']),
        version: map['version'] is int ? map['version'] as int : 0,
        template: map['template']?.toString() ?? 'custom',
        createdAt: _date(map['createdAt']),
        updatedAt: _date(map['updatedAt']),
        activatedAt: _date(map['activatedAt']),
        activatedSchema: PublicWebsiteForm.tryParse(map['activatedSchema'] is Map ? Map<String, dynamic>.from(map['activatedSchema'] as Map) : null),
        multiStep: map['multiStep'] == true,
        reviewStep: map['reviewStep'] == true,
        completionTitle: LocalizedText.fromMap(map['completionTitle']),
        extra: formExtraKeys(map, knownKeys),
      );

  final String id;
  final String schoolId;
  final LocalizedText title;

  /// Shown in steps, one per [FormBlockType.pageBreak] (single page, the
  /// default, unless set).
  final bool multiStep;

  /// A multi-step form's last step: every answer to check before sending.
  final bool reviewStep;

  /// Shown above the success message after sending (optional).
  final LocalizedText completionTitle;

  /// Stored keys this version doesn't read. Saving leaves them in place
  /// (only what it writes changes) and a duplicate carries them; the
  /// visitor copy never has them, as it holds only what visitors see.
  final Map<String, Object?> extra;

  /// Shown to visitors under the title.
  final LocalizedText description;

  /// The website image shown at the top of the form.
  final String? coverMediaId;

  /// For administrators only; never on the website.
  final String internalDescription;

  /// Questions and content, in order.
  final List<FormItem> items;

  /// Shown to visitors after they submit.
  final LocalizedText successMessage;
  final WebsiteFormStatus status;
  final int version;

  /// The starter template it was created from.
  final String template;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? activatedAt;

  /// The version last activated (kept privately here, so activating the
  /// same questions again after deactivation keeps its number).
  final PublicWebsiteForm? activatedSchema;

  /// Its questions, in order.
  List<WebsiteFormField> get fields => items.whereType<WebsiteFormField>().toList();

  /// Every website image it uses (cover and image blocks).
  List<String> get mediaIds => _mediaIds(coverMediaId, items);

  /// The editable content (what Save draft writes).
  Map<String, dynamic> toContentMap() => {
        'title': title.toMap(),
        'description': description.toMap(),
        'coverMediaId': coverMediaId,
        'internalDescription': internalDescription.trim(),
        'items': [for (final i in items) i.toMap()],
        'fields': [for (final f in fields) f.toMap()],
        'mediaIds': mediaIds,
        'successMessage': successMessage.toMap(),
        'multiStep': multiStep,
        'reviewStep': reviewStep,
        'completionTitle': completionTitle.toMap(),
      };

  /// [fields] replaces the questions (content stays where it is); [items]
  /// replaces everything.
  WebsiteForm copyWith({
    LocalizedText? title,
    LocalizedText? description,
    String? Function()? coverMediaId,
    String? internalDescription,
    List<FormItem>? items,
    List<WebsiteFormField>? fields,
    LocalizedText? successMessage,
    bool? multiStep,
    bool? reviewStep,
    LocalizedText? completionTitle,
  }) =>
      WebsiteForm(
        id: id,
        schoolId: schoolId,
        title: title ?? this.title,
        description: description ?? this.description,
        coverMediaId: coverMediaId != null ? coverMediaId() : this.coverMediaId,
        internalDescription: internalDescription ?? this.internalDescription,
        items: items ?? (fields != null ? _replaceFields(this.items, fields) : this.items),
        successMessage: successMessage ?? this.successMessage,
        status: status,
        version: version,
        template: template,
        createdAt: createdAt,
        updatedAt: updatedAt,
        activatedAt: activatedAt,
        activatedSchema: activatedSchema,
        multiStep: multiStep ?? this.multiStep,
        reviewStep: reviewStep ?? this.reviewStep,
        completionTitle: completionTitle ?? this.completionTitle,
        extra: extra,
      );

  /// [complete]: everything activation needs, the description and cover
  /// image included.
  List<String> problems({required bool complete}) => formSchemaProblems(
        title: title,
        items: items,
        successMessage: successMessage,
        description: description,
        coverMediaId: coverMediaId,
        internalDescription: internalDescription,
        completionTitle: completionTitle,
        complete: complete,
        requireMetadata: complete,
      );

  /// What visitors would see of this definition, as version [version]:
  /// without its hidden questions and content ([includeHidden]: with
  /// them, for the builder's canvas only).
  PublicWebsiteForm toPublic(int version, {bool includeHidden = false}) => PublicWebsiteForm(
        id: id,
        schoolId: schoolId,
        title: title.trimmed(),
        description: description.trimmed(),
        coverMediaId: coverMediaId,
        items: [
          for (final i in items)
            if (includeHidden || !(i is WebsiteFormField ? i.hidden : (i as FormContentBlock).hidden)) i,
        ],
        successMessage: successMessage.trimmed(),
        version: version,
        multiStep: multiStep,
        reviewStep: multiStep && reviewStep,
        completionTitle: completionTitle.trimmed(),
      );
}

/// The active version of a form, as the public website reads it (in
/// [FormCollections.publicForms], at the form's id): its title,
/// description, cover image (by id), questions and content, success
/// message, version and school — never its internal description, status
/// history, who edited it or anything about its submissions.
@immutable
class PublicWebsiteForm {
  PublicWebsiteForm({
    required this.id,
    required this.schoolId,
    required this.title,
    this.description = const LocalizedText(),
    this.coverMediaId,
    List<FormItem>? items,
    List<WebsiteFormField> fields = const [],
    required this.successMessage,
    required this.version,
    this.multiStep = false,
    this.reviewStep = false,
    this.completionTitle = const LocalizedText(),
  }) : items = List.unmodifiable(items ?? fields);

  /// The stored fields, and only these (with [optionalStoredFields]).
  static const storedFields = {'formId', 'schoolId', 'title', 'description', 'coverMediaId', 'items', 'fields', 'mediaIds', 'successMessage', 'version', 'activatedAt'};

  /// Stored only when set, so a single-page form's copy is exactly as
  /// before.
  static const optionalStoredFields = {'multiStep', 'reviewStep', 'completionTitle'};

  /// The form in [data], or null when it isn't a usable form (missing,
  /// malformed, inconsistent, or with any schema problem): visitors then
  /// see nothing.
  static PublicWebsiteForm? tryParse(Map<String, dynamic>? data) {
    if (data == null) return null;
    final id = data['formId'];
    final version = data['version'];
    if (id is! String || !FormIds.docPattern.hasMatch(id) || version is! int || version < 1) return null;
    final form = PublicWebsiteForm(
      id: id,
      schoolId: data['schoolId']?.toString() ?? '',
      title: LocalizedText.fromMap(data['title']),
      description: LocalizedText.fromMap(data['description']),
      coverMediaId: _cover(data['coverMediaId']),
      items: _itemsFrom(data),
      successMessage: LocalizedText.fromMap(data['successMessage']),
      version: version,
      multiStep: data['multiStep'] == true,
      reviewStep: data['reviewStep'] == true,
      completionTitle: LocalizedText.fromMap(data['completionTitle']),
    );
    // The questions are stored twice (in their items, and alone): both
    // must agree, since submissions are checked against them.
    if (data['items'] is List && !listEquals(_fieldsFrom(data['fields']), form.fields)) return null;
    return form.schemaProblems().isEmpty && form.schoolId.isNotEmpty ? form : null;
  }

  final String id;
  final String schoolId;
  final LocalizedText title;
  final LocalizedText description;
  final String? coverMediaId;
  final List<FormItem> items;
  final LocalizedText successMessage;
  final int version;
  final bool multiStep;
  final bool reviewStep;
  final LocalizedText completionTitle;

  List<WebsiteFormField> get fields => items.whereType<WebsiteFormField>().toList();
  List<String> get mediaIds => _mediaIds(coverMediaId, items);

  List<String> schemaProblems() => formSchemaProblems(
      title: title, items: items, successMessage: successMessage, description: description, coverMediaId: coverMediaId, completionTitle: completionTitle, complete: true);

  Map<String, dynamic> toMap() => {
        'formId': id,
        'schoolId': schoolId,
        'title': title.toMap(),
        'description': description.toMap(),
        'coverMediaId': coverMediaId ?? '',
        'items': [for (final i in items) i.toMap()],
        'fields': [for (final f in fields) f.toMap()],
        'mediaIds': mediaIds,
        'successMessage': successMessage.toMap(),
        'version': version,
        if (multiStep) 'multiStep': true,
        if (reviewStep) 'reviewStep': true,
        if (!completionTitle.isEmpty) 'completionTitle': completionTitle.toMap(),
      };

  /// Whether visitors would see the same form.
  bool sameSchemaAs(PublicWebsiteForm? other) =>
      other != null &&
      other.title == title &&
      other.description == description &&
      other.coverMediaId == coverMediaId &&
      other.successMessage == successMessage &&
      other.multiStep == multiStep &&
      other.reviewStep == reviewStep &&
      other.completionTitle == completionTitle &&
      listEquals(other.items, items);
}

// ------------------------------------------------------------ answers

/// Why an answer isn't accepted, as a key for [FormStrings].
enum FormAnswerError { required, tooLong, tooShort, email, phone, date, number, outOfRange, option, invalid }

/// [answers] checked against [fields]: the accepted values (trimmed text,
/// option ids, true/false, `YYYY-MM-DD` dates, numbers as written; empty
/// optional answers left out) and, per field id, why an answer isn't
/// accepted. Answers to fields the form doesn't have are refused (under
/// `_form`). Attachment fields take no answer while uploads are disabled
/// ([FormAttachments.publicUploadsEnabled]): they are never required, and
/// an answer to one is refused.
///
/// The same check runs in the browser (for messages) and in the submission
/// service (which never trusts the browser's).
({Map<String, Object> values, Map<String, FormAnswerError> errors}) validateFormAnswers(List<WebsiteFormField> fields, Map<String, Object?> answers) {
  final values = <String, Object>{};
  final errors = <String, FormAnswerError>{};
  final known = {for (final f in fields) f.id};
  if (answers.keys.any((k) => !known.contains(k))) errors['_form'] = FormAnswerError.invalid;
  for (final f in fields) {
    final raw = answers[f.id];
    final type = f.type;
    if (type == null) {
      errors[f.id] = FormAnswerError.invalid;
      continue;
    }
    if (type == FormFieldType.attachment) {
      if (raw != null) errors[f.id] = FormAnswerError.invalid;
      continue;
    }
    if (type == FormFieldType.checkbox) {
      if (raw != null && raw is! bool) {
        errors[f.id] = FormAnswerError.invalid;
      } else if (f.required && raw != true) {
        errors[f.id] = FormAnswerError.required;
      } else {
        values[f.id] = raw == true;
      }
      continue;
    }
    if (raw != null && raw is! String) {
      errors[f.id] = FormAnswerError.invalid;
      continue;
    }
    final text = (raw as String? ?? '').trim();
    if (text.isEmpty) {
      if (f.required) errors[f.id] = FormAnswerError.required;
      continue;
    }
    if (text.length > f.maxAnswerLength) {
      errors[f.id] = FormAnswerError.tooLong;
      continue;
    }
    final problem = switch (type) {
      FormFieldType.shortText || FormFieldType.longText => f.minLength != null && text.length < f.minLength! ? FormAnswerError.tooShort : null,
      FormFieldType.email => _email.hasMatch(text) ? null : FormAnswerError.email,
      FormFieldType.phone => _isPhone(text) ? null : FormAnswerError.phone,
      FormFieldType.date => _dateProblem(f, text),
      FormFieldType.number => _numberProblem(f, text),
      FormFieldType.dropdown || FormFieldType.radio => f.options.any((o) => o.id == text) ? null : FormAnswerError.option,
      _ => null,
    };
    if (problem != null) {
      errors[f.id] = problem;
    } else {
      values[f.id] = text;
    }
  }
  return (values: values, errors: errors);
}

FormAnswerError? _dateProblem(WebsiteFormField f, String text) {
  final date = parseFormDate(text);
  if (date == null) return FormAnswerError.date;
  final from = f.minDate == null ? null : parseFormDate(f.minDate!);
  final to = f.maxDate == null ? null : parseFormDate(f.maxDate!);
  if ((from != null && date.isBefore(from)) || (to != null && date.isAfter(to))) return FormAnswerError.outOfRange;
  return null;
}

FormAnswerError? _numberProblem(WebsiteFormField f, String text) {
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) return FormAnswerError.number;
  final value = num.parse(text);
  if ((f.min != null && value < f.min!) || (f.max != null && value > f.max!)) return FormAnswerError.outOfRange;
  return null;
}

final _email = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$");

/// Digits with an optional leading +, spaces, dots, dashes and brackets:
/// 7 to 15 digits (the international maximum).
bool _isPhone(String text) {
  if (!RegExp(r'^\+?[0-9 ().-]+$').hasMatch(text)) return false;
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '').length;
  return digits >= 7 && digits <= 15;
}

/// A real calendar date written `YYYY-MM-DD`, or null.
DateTime? parseFormDate(String text) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final date = DateTime(y, mo, d);
  if (date.year != y || date.month != mo || date.day != d || y < 1900 || y > 2200) return null;
  return date;
}

// ------------------------------------------------------------ submissions

enum FormSubmissionStatus {
  newSubmission('new', 'New'),
  contacted('contacted', 'Contacted'),
  inProgress('in_progress', 'In Progress'),
  closed('closed', 'Closed'),
  spam('spam', 'Spam');

  const FormSubmissionStatus(this.id, this.label);

  final String id;
  final String label;

  static FormSubmissionStatus? parse(Object? value) {
    for (final s in values) {
      if (s.id == value) return s;
    }
    return null;
  }
}

/// One stored submission (in [FormCollections.submissions]), with the
/// snapshot of the fields it answered, so it stays readable after the form
/// is edited or deactivated.
@immutable
class FormSubmission {
  const FormSubmission({
    required this.id,
    required this.reference,
    required this.formId,
    required this.formVersion,
    required this.formTitle,
    required this.schoolId,
    required this.fields,
    required this.answers,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory FormSubmission.fromMap(String id, Map<String, dynamic> map) {
    final answers = map['answers'];
    return FormSubmission(
      id: id,
      reference: map['reference']?.toString() ?? id,
      formId: map['formId']?.toString() ?? '',
      formVersion: map['formVersion'] is int ? map['formVersion'] as int : 0,
      formTitle: map['formTitle']?.toString() ?? '',
      schoolId: map['schoolId']?.toString() ?? '',
      fields: _fieldsFrom(map['fields']),
      answers: answers is Map ? {for (final e in answers.entries) e.key.toString(): e.value as Object?} : const {},
      status: FormSubmissionStatus.parse(map['status']) ?? FormSubmissionStatus.newSubmission,
      createdAt: _date(map['createdAt']),
      updatedAt: _date(map['updatedAt']),
    );
  }

  final String id;

  /// What the visitor is told ("WF-…"), to quote when they get in touch.
  final String reference;
  final String formId;
  final int formVersion;

  /// The form's English title when it was submitted.
  final String formTitle;
  final String schoolId;

  /// The fields as they were when it was submitted.
  final List<WebsiteFormField> fields;
  final Map<String, Object?> answers;
  final FormSubmissionStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// [field]'s answer in words: an option's label, Yes/No, or the text.
  String answerText(WebsiteFormField field) {
    final value = answers[field.id];
    return switch (field.type) {
      FormFieldType.checkbox => value == true ? 'Yes' : 'No',
      FormFieldType.attachment => '',
      FormFieldType.dropdown || FormFieldType.radio => value is String ? field.optionLabel(value) : '',
      _ => value?.toString() ?? '',
    };
  }

  /// Text to search: the reference, the form and every answer.
  String get searchText => [reference, formTitle, for (final f in fields) answerText(f)].join(' ').toLowerCase();
}

/// The reference a visitor is given for submission [id].
String formSubmissionReference(String id) => 'WF-${id.substring(0, min(8, id.length)).toUpperCase()}';

// ------------------------------------------------------------ templates

/// A starting point for a new form: its fields are copied into the new
/// form (with their own ids) and can then be changed like any other.
class FormTemplate {
  const FormTemplate._(this.id, this.name, this.description, this._fields, this._success, this._formDescription);

  final String id;
  final String name;

  /// What the template is for (in the template list).
  final String description;
  final List<WebsiteFormField> Function() _fields;
  final String _success;
  final String _formDescription;

  List<WebsiteFormField> buildFields() => _fields();
  LocalizedText get successMessage => LocalizedText(en: _success);

  /// The new form's description for visitors (a cover image must still be
  /// chosen before it can be activated).
  LocalizedText get formDescription => LocalizedText(en: _formDescription);

  static FormTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  static const _consent = 'I agree that the school may use these details to reply to me.';

  static final all = <FormTemplate>[
    FormTemplate._(
      'admission_enquiry',
      'Admission Enquiry',
      'Parents asking about a place for their child',
      () => [
        WebsiteFormField.create(FormFieldType.shortText, 'Parent or guardian name', required: true),
        WebsiteFormField.create(FormFieldType.email, 'Email', required: true, placeholder: 'name@example.com'),
        WebsiteFormField.create(FormFieldType.phone, 'Phone', required: true),
        WebsiteFormField.create(FormFieldType.shortText, 'Child’s name', required: true),
        WebsiteFormField.create(FormFieldType.date, 'Child’s date of birth', required: true),
        WebsiteFormField.create(FormFieldType.dropdown, 'Programme of interest', required: true, options: ['Toddler', 'Primary', 'Elementary']),
        WebsiteFormField.create(FormFieldType.longText, 'Anything you’d like us to know'),
        WebsiteFormField.create(FormFieldType.checkbox, _consent, required: true),
      ],
      'Thank you for your enquiry. Our admissions team will contact you soon.',
      'Tell us about your child and the programme you are interested in, and our admissions team will be in touch.',
    ),
    FormTemplate._(
      'general_enquiry',
      'General Enquiry',
      'Any question for the school',
      () => [
        WebsiteFormField.create(FormFieldType.shortText, 'Your name', required: true),
        WebsiteFormField.create(FormFieldType.email, 'Email', required: true, placeholder: 'name@example.com'),
        WebsiteFormField.create(FormFieldType.phone, 'Phone'),
        WebsiteFormField.create(FormFieldType.longText, 'Your message', required: true),
        WebsiteFormField.create(FormFieldType.checkbox, _consent, required: true),
      ],
      'Thank you for your message. We will reply soon.',
      'Send us your question and we will reply as soon as we can.',
    ),
    FormTemplate._(
      'event_registration',
      'Event Registration',
      'Sign-ups for an open day, workshop or event',
      () => [
        WebsiteFormField.create(FormFieldType.shortText, 'Your name', required: true),
        WebsiteFormField.create(FormFieldType.email, 'Email', required: true, placeholder: 'name@example.com'),
        WebsiteFormField.create(FormFieldType.phone, 'Phone', required: true),
        WebsiteFormField.create(FormFieldType.radio, 'Number attending', required: true, options: ['1', '2', '3', '4 or more']),
        WebsiteFormField.create(FormFieldType.longText, 'Questions or requirements'),
        WebsiteFormField.create(FormFieldType.checkbox, _consent, required: true),
      ],
      'Thank you for registering. We look forward to seeing you.',
      'Register your place, and tell us how many people are coming.',
    ),
    FormTemplate._(
      'custom',
      'Custom Form',
      'Start with one question and build your own',
      () => [WebsiteFormField.create(FormFieldType.shortText, 'Your name', required: true)],
      'Thank you. We have received your response.',
      'Please fill in this form.',
    ),
  ];
}
