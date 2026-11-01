import 'package:flutter/widgets.dart' show StringCharacters;

import 'field_spec.dart';

/// The Testimonials block (`testimonials`): quotes from families, students
/// and educators as cards, each with an avatar (a profile photo, else the
/// person's initials) and an optional star rating, and every part of the
/// presentation a setting (Automatic until set).
///
/// Nothing is invented: a testimonial has no rating, role, date, place or
/// verification label until the editor enters one, and only settings that
/// are changed are stored.
abstract final class Testimonials {
  static const type = 'testimonials';
  static const maxItems = 12;

  /// A testimonial's rating choices: none (the default), or 0 to 5 stars
  /// in half stars.
  static const ratings = ['none', '0', '0.5', '1', '1.5', '2', '2.5', '3', '3.5', '4', '4.5', '5'];

  static const layouts = ['vertical', 'horizontal', 'compact'];

  /// [item]'s rating (0 to 5), or null when it has none.
  static double? ratingOf(BlockItem item) {
    final r = double.tryParse(item.string('rating'));
    return r == null || r < 0 || r > 5 ? null : r;
  }

  /// [rating] as it is written: "4", "4.5".
  static String ratingText(double rating) => rating == rating.roundToDouble() ? rating.toInt().toString() : rating.toString();

  /// The initials of [name]: the first letter of its first two words
  /// ("Tanveer Razi" → TR, "Yasmeen" → Y), upper case; '' without a word.
  /// A word's leading punctuation is skipped; a letter is a whole
  /// character (a Tamil letter with its vowel sign).
  static String initialsOf(String name) {
    final letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
    final out = StringBuffer();
    var words = 0;
    for (final word in name.trim().split(RegExp(r'\s+'))) {
      final start = word.indexOf(letter);
      if (start < 0) continue;
      out.write(word.substring(start).characters.first.toUpperCase());
      if (++words == 2) break;
    }
    return out.toString();
  }

  // ----------------------------------------------------------- fields

  static bool _rated(Map<String, Object?> item, Map<String, Object?> block) => (item['rating'] ?? 'none') != 'none';
  static bool _hasPhoto(Map<String, Object?> item, Map<String, Object?> block) => (item['photoMediaId'] as String? ?? '').trim().isNotEmpty;
  static bool _avatarsOn(Map<String, Object?> values, Map<String, Object?> block) => block['showAvatars'] != false;
  static bool _avatarBorder(Map<String, Object?> values, Map<String, Object?> block) => _avatarsOn(values, block) && (block['avatarBorderWidth'] ?? '0') != '0';
  static bool _ratingsOn(Map<String, Object?> values, Map<String, Object?> block) => block['showRatings'] != false;
  static bool _cardBorder(Map<String, Object?> values, Map<String, Object?> block) => (block['cardBorderWidth'] ?? '1') != '0';

  static const _details = 'More details (optional)';

  static const itemFields = <FieldSpec>[
    TextFieldSpec('name', 'Name', maxLength: 80),
    TextFieldSpec('role', 'Role or relationship (e.g. Parent, Student, Educator)', maxLength: 80, omitDefault: true),
    TextFieldSpec('quote', 'Testimonial text', maxLength: 1200, multiline: true, required: true),
    MediaFieldSpec('photoMediaId', 'Profile photo (optional; otherwise their initials are shown)', omitDefault: true, removable: true),
    TextFieldSpec('photoAlt', 'Profile photo description (alt text; replaces the Media library’s)', maxLength: 200, omitDefault: true, shownWhen: _hasPhoto),
    ChoiceFieldSpec('rating', 'Rating', options: ratings, initial: 'none', omitDefault: true, optionLabels: {
      'none': 'No rating',
      '0': '0 stars',
      '0.5': '½ star',
      '1': '1 star',
      '1.5': '1½ stars',
      '2': '2 stars',
      '2.5': '2½ stars',
      '3': '3 stars',
      '3.5': '3½ stars',
      '4': '4 stars',
      '4.5': '4½ stars',
      '5': '5 stars',
    }),
    ToggleFieldSpec('hideRating', 'Hide this testimonial’s rating', omitDefault: true, shownWhen: _rated),
    TextFieldSpec('date', 'Date (as it should appear, e.g. March 2025)', maxLength: 40, omitDefault: true, group: _details),
    TextFieldSpec('location', 'Location', maxLength: 80, omitDefault: true, group: _details),
    TextFieldSpec('verification', 'Verification label (e.g. Verified parent); shown only when entered', maxLength: 40, omitDefault: true, group: _details),
  ];

  static const _layout = 'Layout';
  static const _avatars = 'Avatars';
  static const _ratingsGroup = 'Ratings';
  static const _card = 'Card appearance';
  static const _section = 'Section size and spacing';

  static const _aligns = ['auto', 'start', 'center', 'end'];

  static const fields = <FieldSpec>[
    TextFieldSpec('eyebrow', 'Small label above the heading', maxLength: 60, omitDefault: true),
    TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true, omitDefault: true),
    TextFieldSpec('description', 'Description', maxLength: 600, multiline: true, omitDefault: true),
    ItemsFieldSpec('testimonials', 'Testimonials', itemLabel: 'Testimonial', minItems: 1, maxItems: maxItems, itemFields: itemFields),
    ChoiceFieldSpec('layout', 'Card layout', options: layouts, initial: 'vertical', omitDefault: true, group: _layout, optionLabels: {
      'vertical': 'Vertical (avatar above the text)',
      'horizontal': 'Horizontal (avatar beside the text)',
      'compact': 'Compact (the person below the text)',
    }),
    ChoiceFieldSpec('desktopColumns', 'Cards per row on desktop', options: ['auto', '1', '2', '3', '4'], initial: 'auto', omitDefault: true, group: _layout, optionLabels: {'auto': 'Automatic (3, or fewer testimonials)'}),
    ChoiceFieldSpec('tabletColumns', 'Cards per row on tablets', options: ['auto', '1', '2', '3'], initial: 'auto', omitDefault: true, group: _layout, optionLabels: {'auto': 'Automatic (2)'}),
    ChoiceFieldSpec('mobileColumns', 'Cards per row on phones', options: ['auto', '1', '2'], initial: 'auto', omitDefault: true, group: _layout, optionLabels: {'auto': 'Automatic (1)'}),
    NumberFieldSpec('gap', 'Space between cards', min: 0, max: 64, unit: 'px', automaticLabel: 'Automatic (24 px, 16 on phones)', group: _layout),
    ChoiceFieldSpec('contentAlign', 'Content alignment in a card', options: _aligns, initial: 'auto', omitDefault: true, group: _layout, optionLabels: {
      'auto': 'Automatic (centred when vertical, else left)',
      'start': 'Left',
      'center': 'Centre',
      'end': 'Right',
    }),
    NumberFieldSpec('elementGap', 'Space between avatar, name, rating and text', min: 0, max: 40, unit: 'px', automaticLabel: 'Automatic (12 px)', group: _layout),
    ToggleFieldSpec('showAvatars', 'Show avatars (photo, else initials)', initial: true, omitDefault: true, group: _avatars),
    NumberFieldSpec('avatarSize', 'Avatar size', min: 24, max: 120, unit: 'px', automaticLabel: 'Automatic (56 px, 40 compact)', group: _avatars, shownWhen: _avatarsOn),
    ColorFieldSpec('avatarBackground', 'Initials background', automaticLabel: 'the site’s soft gold', omitDefault: true, group: _avatars, shownWhen: _avatarsOn),
    ColorFieldSpec('avatarTextColor', 'Initials colour', automaticLabel: 'the site’s dark green', omitDefault: true, group: _avatars, shownWhen: _avatarsOn),
    ChoiceFieldSpec('avatarAlign', 'Avatar alignment', options: _aligns, initial: 'auto', omitDefault: true, group: _avatars, shownWhen: _avatarsOn, optionLabels: {
      'auto': 'Automatic (as the content)',
      'start': 'Left (top when beside the text)',
      'center': 'Centre',
      'end': 'Right (bottom when beside the text)',
    }),
    ChoiceFieldSpec('avatarBorderWidth', 'Avatar border', options: ['0', '1', '2', '3', '4'], initial: '0', omitDefault: true, group: _avatars, shownWhen: _avatarsOn,
        optionLabels: {'0': 'None', '1': '1 px', '2': '2 px', '3': '3 px', '4': '4 px'}),
    ColorFieldSpec('avatarBorderColor', 'Avatar border colour', automaticLabel: 'white', omitDefault: true, group: _avatars, shownWhen: _avatarBorder),
    ToggleFieldSpec('showRatings', 'Show ratings (testimonials with one)', initial: true, omitDefault: true, group: _ratingsGroup),
    ColorFieldSpec('starColor', 'Star colour', automaticLabel: 'amber', omitDefault: true, group: _ratingsGroup, shownWhen: _ratingsOn),
    ColorFieldSpec('emptyStarColor', 'Empty star colour', automaticLabel: 'grey', omitDefault: true, group: _ratingsGroup, shownWhen: _ratingsOn),
    NumberFieldSpec('starSize', 'Star size', min: 12, max: 40, unit: 'px', automaticLabel: 'Automatic (18 px)', group: _ratingsGroup, shownWhen: _ratingsOn),
    ChoiceFieldSpec('ratingAlign', 'Rating alignment', options: _aligns, initial: 'auto', omitDefault: true, group: _ratingsGroup, shownWhen: _ratingsOn, optionLabels: {
      'auto': 'Automatic (as the content)',
      'start': 'Left',
      'center': 'Centre',
      'end': 'Right',
    }),
    ChoiceFieldSpec('ratingNumber', 'Rating as a number', options: ['none', 'number', 'outOf'], initial: 'none', omitDefault: true, group: _ratingsGroup, shownWhen: _ratingsOn, optionLabels: {
      'none': 'Stars only',
      'number': 'Stars and the number (4.5)',
      'outOf': 'Stars and “4.5 / 5”',
    }),
    ColorFieldSpec('cardBackground', 'Card background', automaticLabel: 'white', omitDefault: true, group: _card),
    ChoiceFieldSpec('cardBorderWidth', 'Card border', options: ['0', '1', '2', '4'], initial: '1', omitDefault: true, group: _card, optionLabels: {'0': 'None', '1': '1 px', '2': '2 px', '4': '4 px'}),
    ColorFieldSpec('cardBorderColor', 'Card border colour', automaticLabel: 'the site’s line colour', omitDefault: true, group: _card, shownWhen: _cardBorder),
    NumberFieldSpec('cardRadius', 'Card corner radius', min: 0, max: 48, unit: 'px', automaticLabel: 'Automatic (16 px)', group: _card),
    NumberFieldSpec('cardPadding', 'Card padding', min: 8, max: 64, unit: 'px', automaticLabel: 'Automatic (28 px; 20 compact or on phones)', group: _card),
    ChoiceFieldSpec('cardShadow', 'Card shadow', options: ['none', 'soft', 'strong'], initial: 'soft', omitDefault: true, group: _card, optionLabels: {'none': 'None', 'soft': 'Soft', 'strong': 'Strong'}),
    NumberFieldSpec('maxWidth', 'Maximum width', min: 320, max: 1600, unit: 'px', automaticLabel: 'Automatic (the content width)', group: _section),
    ChoiceFieldSpec('align', 'Heading alignment', options: ['start', 'center', 'end'], initial: 'center', omitDefault: true, group: _section, optionLabels: {
      'start': 'Left',
      'center': 'Centre',
      'end': 'Right',
    }),
    NumberFieldSpec('paddingTop', 'Space at the top', min: 0, max: 160, unit: 'px', automaticLabel: 'Automatic (none)', group: _section),
    NumberFieldSpec('paddingBottom', 'Space at the bottom', min: 0, max: 160, unit: 'px', automaticLabel: 'Automatic (none)', group: _section),
  ];
}
