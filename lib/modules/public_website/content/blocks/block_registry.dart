import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../website_content_models.dart';
import '../website_custom_page.dart';
import '../website_design.dart';
import 'block_ids.dart';
import 'block_limits.dart';
import 'field_spec.dart';
import 'website_block.dart';

/// A block type: its stored name, schema version, admin label and fields,
/// plus any rule its fields alone can't express. Everything generic —
/// parsing, saving, validation, images used, translatable text — follows
/// from [fields].
@immutable
class BlockDefinition {
  const BlockDefinition({
    required this.type,
    required this.version,
    required this.label,
    required this.fields,
    this.extraChecks,
    this.styleKeys = BlockStyle.basic,
    this.description = '',
  });

  final String type;

  /// The display options (`style` keys) this type offers and its renderer
  /// honours. Other stored style keys are kept but not offered.
  final List<String> styleKeys;

  /// One line for the "Add" menus.
  final String description;

  /// The newest stored version this app understands. A block saved with a
  /// newer version is kept unchanged as an [UnsupportedBlock].
  final int version;
  final String label;
  final List<FieldSpec> fields;

  /// Type-specific problems (in addition to the field checks).
  final List<String> Function(StructuredBlock block)? extraChecks;

  FieldSpec? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// Display options (a block's `style`), and their allowed values. A key a
/// block doesn't set is inherited: from the section around it, then the
/// site's design. Colours are palette references (`token:<id>`) or
/// `#RRGGBB` ([SiteDesign]); `background` also keeps its first values
/// (`white` = none, `sage`, `gold`).
class BlockStyle {
  static const backgrounds = ['white', 'sage', 'gold'];
  static const spacings = ['none', 'compact', 'normal', 'spacious'];

  /// Inner space (px), top and bottom; on phones at most 48.
  static const paddings = ['0', '16', '24', '32', '48', '56', '72', '80', '88', '96'];
  static const aligns = ['start', 'center', 'end'];
  static const fontSizes = ['small', 'normal', 'large'];

  /// Content width: narrow 760, content 960, wide 1160 px.
  static const widths = ['narrow', 'content', 'wide'];
  static const borderWidths = ['0', '1', '2', '4'];

  /// Space between columns, and between rows when columns wrap or stack
  /// (px), in a section or columns block. Unset: today's (40 between
  /// columns; 24 to 32 between stacked columns).
  static const gaps = ['0', '8', '16', '24', '32', '40', '48', '64'];

  static const colorKeys = ['background', 'textColor', 'headingColor', 'buttonColor', 'buttonTextColor', 'borderColor', 'lineColor'];

  /// A block's own font sizes (px), in place of the site typography: its
  /// headings (the hero's and page header's title too) and its body text.
  /// Unset: the site typography (and the block's text size option).
  static const sizeKeys = {
    'headingFontSize': FontSizeRange(14, 72, 26),
    'bodyFontSize': SiteDesign.bodyRange,
  };

  /// Every block offers these.
  static const basic = ['background', 'spacing'];

  /// The allowed values of choice key [key] (null for colour keys and
  /// keys this version doesn't know).
  static List<String>? optionsFor(String key) => switch (key) {
        'spacing' => spacings,
        'padding' || 'paddingTop' || 'paddingBottom' => paddings,
        'align' => aligns,
        'fontSize' => fontSizes,
        'width' => widths,
        'borderWidth' => borderWidths,
        'columnGap' || 'rowGap' => gaps,
        _ => null,
      };

  /// Why [value] can't be the value of style [key], or null when it can
  /// (or [key] isn't one this version knows: it is kept as stored).
  static String? problem(String key, Object? value) {
    if (key == 'background') {
      return backgrounds.contains(value) || SiteDesign.isColorValue(value) ? null : '“$value” is not a background option';
    }
    if (colorKeys.contains(key)) return SiteDesign.isColorValue(value) ? null : '“$value” is not a colour';
    if (sizeKeys[key] case final range?) {
      return range.allows(value) ? null : 'its ${key == 'headingFontSize' ? 'heading' : 'text'} size must be ${range.min.round()} to ${range.max.round()} px';
    }
    final options = optionsFor(key);
    if (options != null && !options.contains(value)) return '“$value” is not a $key option';
    return null;
  }

  /// The value a block shows with when it stores none
  /// ([StructuredBlock.background], [StructuredBlock.spacing]).
  static const defaults = {'background': 'white', 'spacing': 'normal'};

  /// Whether [style] looks exactly like no style: empty, or only the
  /// default values written out.
  static bool isDefault(Map<String, dynamic> style) => style.entries.every((e) => defaults[e.key] == e.value);
}

/// Icons a card or feature can show (by stored name).
const blockIconNames = [
  'family', 'school', 'spa', 'grid', 'care', 'star', 'book', 'palette', 'nature', 'heart', 'calendar', 'place', 'phone', 'mail', 'question', 'quote', 'check', //
];

const _buttonItem = [
  TextFieldSpec('label', 'Button label', maxLength: 40, required: true, translationRequired: true),
  LinkFieldSpec('target', 'Button link', required: true),
  ChoiceFieldSpec('variant', 'Button style', options: ['primary', 'secondary', 'link', 'back'], initial: 'primary'),
];

/// The column layouts a columns block or a section offers (relative
/// widths); `1` is a single column (sections only).
const columnLayouts = {'1': [1], '1:1': [1, 1], '1:2': [1, 2], '2:1': [2, 1], '1:1:1': [1, 1, 1], '1:1:1:1': [1, 1, 1, 1]};

/// How the editor names a column layout.
const columnLayoutLabels = {
  '1': 'One column',
  '1:1': 'Two equal columns',
  '1:2': 'Two columns, wider right',
  '2:1': 'Two columns, wider left',
  '1:1:1': 'Three columns',
  '1:1:1:1': 'Four columns',
};

/// Items per row on each screen size, for blocks of repeated items
/// (cards, points, images). `auto` is the block's own layout from before
/// these settings existed.
const _perRowFields = [
  ChoiceFieldSpec('desktopColumns', 'Per row on desktop', options: ['auto', '1', '2', '3', '4'], initial: 'auto', optionLabels: {'auto': 'Automatic (all in one row)'}, omitDefault: true),
  ChoiceFieldSpec('tabletColumns', 'Per row on tablets', options: ['auto', '1', '2', '3'], initial: 'auto', optionLabels: {'auto': 'Automatic (as on desktop)'}, omitDefault: true),
  ChoiceFieldSpec('mobileColumns', 'Per row on phones', options: ['auto', '1', '2'], initial: 'auto', optionLabels: {'auto': 'Automatic (one per row)'}, omitDefault: true),
];

/// Container types: they hold blocks in columns, and can't be nested in
/// each other.
const containerTypes = {'columns', 'section'};

List<String> _containerChecks(StructuredBlock b) {
  final widths = columnLayouts[b.string('layout')];
  final cols = b.columns('columns');
  return [
    if (widths != null && cols.length != widths.length) 'it needs ${widths.length} column${widths.length == 1 ? '' : 's'} for this layout',
    for (final c in cols)
      for (final child in c.blocks)
        if (child is StructuredBlock && containerTypes.contains(child.type)) '${b.definition.label.toLowerCase()} can’t contain ${child.definition.label.toLowerCase()}',
  ];
}

/// The block types this app knows, and the generic operations on blocks.
class BlockRegistry {
  BlockRegistry._();

  static final text = BlockDefinition(
    type: 'text',
    version: 1,
    label: 'Text',
    description: 'A heading and paragraphs',
    styleKeys: const ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'align', 'fontSize', 'borderColor', 'width'],
    fields: const [
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      TextFieldSpec('body', 'Text', maxLength: 3000, multiline: true),
    ],
    extraChecks: (b) => b.text('heading').en.trim().isEmpty && b.text('body').en.trim().isEmpty ? ['add a heading or some text'] : const [],
  );

  static const image = BlockDefinition(
    type: 'image',
    version: 1,
    label: 'Image',
    description: 'One photograph with a caption',
    styleKeys: ['background', 'spacing', 'borderColor', 'width'],
    fields: [
      MediaFieldSpec('mediaId', 'Image', required: true),
      TextFieldSpec('alt', 'Alt text (optional, replaces the library’s)', maxLength: 250),
      TextFieldSpec('caption', 'Caption', maxLength: 300),
      ChoiceFieldSpec('aspect', 'Shape', options: ['16:9', '4:3', '1:1', '3:4', 'original'], initial: '16:9'),
    ],
  );

  static const columns = BlockDefinition(
    type: 'columns',
    version: 1,
    label: 'Columns',
    description: 'Blocks side by side',
    styleKeys: ['background', 'spacing', 'textColor', 'headingColor', 'borderColor', 'width', 'columnGap', 'rowGap'],
    fields: [
      ChoiceFieldSpec('layout', 'Column widths', options: ['1:1', '1:2', '2:1', '1:1:1', '1:1:1:1'], initial: '1:1', optionLabels: columnLayoutLabels),
      ColumnsFieldSpec('columns', 'Columns'),
    ],
    extraChecks: _containerChecks,
  );

  /// A full-width band of the page with its own background, padding and
  /// content width, holding blocks in one to four columns. Sections are
  /// the page's building blocks: the "Add section" layouts create them.
  static const section = BlockDefinition(
    type: 'section',
    version: 1,
    label: 'Section',
    description: 'A full-width band holding blocks',
    styleKeys: ['background', 'spacing', 'padding', 'paddingTop', 'paddingBottom', 'width', 'columnGap', 'rowGap', 'textColor', 'headingColor', 'buttonColor', 'buttonTextColor', 'borderColor', 'borderWidth', 'align'],
    fields: [
      TextFieldSpec('name', 'Section name (for the editor only)', maxLength: 60, translatable: false),
      // Optional text above the columns; not stored while empty.
      TextFieldSpec('eyebrow', 'Small heading above the title', maxLength: 60, omitDefault: true),
      TextFieldSpec('heading', 'Section heading', maxLength: 160, translationRequired: true, omitDefault: true),
      TextFieldSpec('description', 'Section description', maxLength: 1000, multiline: true, omitDefault: true),
      ChoiceFieldSpec('layout', 'Columns', options: ['1', '1:1', '1:2', '2:1', '1:1:1', '1:1:1:1'], initial: '1', optionLabels: columnLayoutLabels),
      ColumnsFieldSpec('columns', 'Columns'),
    ],
    extraChecks: _containerChecks,
  );

  /// A page's opening: small label, large heading, introduction, and a
  /// photograph beside it (or decorative shapes), with optional buttons.
  static const hero = BlockDefinition(
    type: 'hero',
    version: 1,
    label: 'Hero',
    description: 'Large heading, introduction and photograph',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'buttonColor', 'buttonTextColor', 'width'],
    fields: [
      TextFieldSpec('eyebrow', 'Small label above the heading', maxLength: 60),
      TextFieldSpec('heading', 'Heading', maxLength: 160, required: true, translationRequired: true),
      TextFieldSpec('body', 'Introduction', maxLength: 1000, multiline: true),
      MediaFieldSpec('mediaId', 'Photograph (optional)'),
      ToggleFieldSpec('decor', 'Decorative shapes when there is no photograph', initial: true),
      ItemsFieldSpec('buttons', 'Buttons', itemLabel: 'Button', itemFields: _buttonItem, maxItems: 2),
    ],
  );

  /// Linked cards with an icon (e.g. "For Families", "For Educators").
  static const cards = BlockDefinition(
    type: 'cards',
    version: 1,
    label: 'Cards',
    description: 'Linked cards with icons',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'width'],
    fields: [
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      ..._perRowFields,
      ItemsFieldSpec('cards', 'Cards', itemLabel: 'Card', minItems: 1, maxItems: 8, itemFields: [
        ChoiceFieldSpec('icon', 'Icon', options: blockIconNames, initial: 'star'),
        TextFieldSpec('title', 'Title', maxLength: 80, required: true, translationRequired: true),
        TextFieldSpec('body', 'Text', maxLength: 400, multiline: true),
        TextFieldSpec('linkLabel', 'Link text', maxLength: 60),
        LinkFieldSpec('target', 'Link (optional)'),
        ChoiceFieldSpec('accent', 'Accent', options: ['primary', 'secondary'], initial: 'primary'),
      ]),
    ],
  );

  /// Short points with icons (e.g. the Montessori principles).
  static const features = BlockDefinition(
    type: 'features',
    version: 1,
    label: 'Features',
    description: 'Points with icons in a row',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'width'],
    fields: [
      TextFieldSpec('eyebrow', 'Small label', maxLength: 60),
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      ..._perRowFields,
      ItemsFieldSpec('items', 'Points', itemLabel: 'Point', minItems: 1, maxItems: 8, itemFields: [
        ChoiceFieldSpec('icon', 'Icon', options: blockIconNames, initial: 'check'),
        TextFieldSpec('title', 'Title', maxLength: 80, required: true, translationRequired: true),
        TextFieldSpec('body', 'Text', maxLength: 400, multiline: true),
      ]),
    ],
  );

  /// A page's title, introduction and banner photograph.
  static const pageHeader = BlockDefinition(
    type: 'page_header',
    version: 1,
    label: 'Page title',
    description: 'Title, introduction and banner',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'width'],
    fields: [
      TextFieldSpec('heading', 'Title', maxLength: 120, required: true, translationRequired: true),
      TextFieldSpec('intro', 'Introduction', maxLength: 600, multiline: true),
      MediaFieldSpec('mediaId', 'Banner photograph (optional)'),
      ToggleFieldSpec('placeholder', 'Decorative placeholder when there is no photograph'),
    ],
  );

  /// A highlighted note in a tinted box.
  static const notice = BlockDefinition(
    type: 'notice',
    version: 1,
    label: 'Notice',
    description: 'A highlighted note',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'borderColor', 'width'],
    fields: [
      TextFieldSpec('title', 'Title', maxLength: 120, translationRequired: true),
      TextFieldSpec('body', 'Text', maxLength: 600, multiline: true),
    ],
    extraChecks: _titleOrText,
  );

  /// The school's whole published gallery, with its category filters and
  /// lightbox (what the Gallery page shows).
  static const galleryFeed = BlockDefinition(
    type: 'gallery_feed',
    version: 1,
    label: 'School gallery',
    description: 'Every published gallery photograph, with filters (to choose photographs, use Photo gallery)',
    styleKeys: ['background', 'spacing', 'width'],
    fields: [],
  );

  /// The school's upcoming events that an admin has shown on the website
  /// (Calendar → Show on website), soonest first. Visitors see only these
  /// sanitized copies; the calendar itself is never read for them.
  ///
  /// Layout: a list (one per row), a grid of cards, or compact cards, with
  /// columns per screen size (grid and compact cards). A block saved before
  /// these settings existed shows the defaults (a 3/2/1-column grid); its
  /// earlier `display` value is kept as stored but no longer used.
  static const eventsFeed = BlockDefinition(
    type: 'events_feed',
    version: 1,
    label: 'Upcoming events',
    description: 'Calendar events shown on the website, soonest first',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'width'],
    fields: [
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      ChoiceFieldSpec('maxItems', 'Events shown at most', options: ['3', '4', '6', '9', '12'], initial: '6'),
      ChoiceFieldSpec('layout', 'Layout', options: ['list', 'grid', 'compact_cards'], initial: 'grid', optionLabels: {
        'list': 'List (one per row)',
        'grid': 'Grid of cards',
        'compact_cards': 'Compact cards',
      }),
      ChoiceFieldSpec('desktopColumns', 'Columns on desktop', options: ['1', '2', '3', '4'], initial: '3'),
      ChoiceFieldSpec('tabletColumns', 'Columns on tablets', options: ['1', '2', '3'], initial: '2'),
      ChoiceFieldSpec('mobileColumns', 'Columns on phones', options: ['1', '2'], initial: '1'),
      ToggleFieldSpec('showImages', 'Show event images', initial: true),
    ],
  );

  /// The school's announcements an admin has shown on the website
  /// (Notifications → Public website), newest first. Visitors see only
  /// these sanitized copies; the school's notifications are never read for
  /// them. Same layouts and columns as [eventsFeed]; previews never show
  /// the message (its page does).
  static const announcementsFeed = BlockDefinition(
    type: 'announcements_feed',
    version: 1,
    label: 'Announcements',
    description: 'School announcements shown on the website, newest first',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'width'],
    fields: [
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      ChoiceFieldSpec('maxItems', 'Announcements shown at most', options: ['3', '4', '6', '9', '12'], initial: '6'),
      ChoiceFieldSpec('layout', 'Layout', options: ['list', 'grid', 'compact_cards'], initial: 'grid', optionLabels: {
        'list': 'List (one per row)',
        'grid': 'Grid of cards',
        'compact_cards': 'Compact cards',
      }),
      ChoiceFieldSpec('desktopColumns', 'Columns on desktop', options: ['1', '2', '3', '4'], initial: '3'),
      ChoiceFieldSpec('tabletColumns', 'Columns on tablets', options: ['1', '2', '3'], initial: '2'),
      ChoiceFieldSpec('mobileColumns', 'Columns on phones', options: ['1', '2'], initial: '1'),
      ToggleFieldSpec('showImages', 'Show announcement images', initial: true),
      ToggleFieldSpec('showCategory', 'Show the category', initial: true),
      ToggleFieldSpec('highlightPinned', 'Pinned announcements first, marked “Pinned”', initial: true),
    ],
  );

  /// A website form (Settings → Website forms) with a heading and an
  /// introduction. The block holds only the form's id; visitors see the
  /// form's active version, and nothing when it isn't active.
  static const form = BlockDefinition(
    type: 'form',
    version: 1,
    label: 'Form',
    description: 'An enquiry or registration form from Website forms',
    styleKeys: ['background', 'spacing', 'textColor', 'headingColor', 'width'],
    fields: [
      FormRefFieldSpec('formId', 'Form', required: true),
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      TextFieldSpec('intro', 'Introduction', maxLength: 600, multiline: true),
    ],
  );

  static List<String> _titleOrText(StructuredBlock b) =>
      b.text('title').en.trim().isEmpty && b.text('body').en.trim().isEmpty ? const ['add a title or some text'] : const [];

  static const cta = BlockDefinition(
    type: 'cta',
    version: 1,
    label: 'Call to action',
    description: 'A heading, text and buttons in a box',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'buttonColor', 'buttonTextColor', 'borderColor', 'width'],
    fields: [
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      TextFieldSpec('body', 'Text', maxLength: 3000, multiline: true),
      ItemsFieldSpec('buttons', 'Buttons', itemLabel: 'Button', itemFields: _buttonItem, minItems: 1, maxItems: 2),
    ],
  );

  static const buttons = BlockDefinition(
    type: 'buttons',
    version: 1,
    label: 'Buttons',
    description: 'One to four buttons',
    styleKeys: ['background', 'spacing', 'buttonColor', 'buttonTextColor', 'width'],
    fields: [
      ChoiceFieldSpec('align', 'Alignment', options: ['start', 'center'], initial: 'start'),
      ItemsFieldSpec('buttons', 'Buttons', itemLabel: 'Button', itemFields: _buttonItem, minItems: 1, maxItems: 4),
    ],
  );

  /// Photographs chosen from the media library, in the order set here.
  /// Each can have its own caption (else the library's) and a link (else
  /// tapping opens the lightbox). The settings added after the first
  /// version default to how the grid looked before: 2 per row on phones,
  /// the desktop count on tablets, 4:3 images, every image, captions shown.
  static const gallery = BlockDefinition(
    type: 'gallery',
    version: 1,
    label: 'Photo gallery',
    description: 'Photographs you choose, in your order',
    styleKeys: ['background', 'spacing', 'textColor', 'headingColor', 'headingFontSize', 'width'],
    fields: [
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      ChoiceFieldSpec('columns', 'Images per row on desktop', options: ['1', '2', '3', '4', '5', '6'], initial: '3'),
      ChoiceFieldSpec('tabletColumns', 'Images per row on tablets', options: ['auto', '1', '2', '3', '4'], initial: 'auto', optionLabels: {'auto': 'Automatic (as on desktop)'}, omitDefault: true),
      ChoiceFieldSpec('mobileColumns', 'Images per row on phones', options: ['1', '2', '3'], initial: '2', omitDefault: true),
      ChoiceFieldSpec('aspect', 'Image shape', options: ['4:3', '1:1', '3:4', '16:9'], initial: '4:3', optionLabels: {
        '4:3': 'Landscape (4:3)',
        '1:1': 'Square',
        '3:4': 'Portrait (3:4)',
        '16:9': 'Wide (16:9)',
      }, omitDefault: true),
      ChoiceFieldSpec('limit', 'Images shown', options: ['all', '3', '4', '6', '8', '9', '12'], initial: 'all', optionLabels: {'all': 'All chosen images'}, omitDefault: true),
      ToggleFieldSpec('showCaptions', 'Show captions', initial: true, omitDefault: true),
      ItemsFieldSpec('images', 'Images', itemLabel: 'Image', minItems: 1, maxItems: CustomPage.maxGridImages, itemFields: [
        MediaFieldSpec('mediaId', 'Image', required: true),
        TextFieldSpec('caption', 'Caption (optional, replaces the library’s)', maxLength: 300, omitDefault: true),
        LinkFieldSpec('target', 'Link (optional; otherwise the image opens larger)', omitDefault: true),
      ]),
    ],
  );

  /// A Google map of a place the editor enters (an address or a place
  /// name), shown with Google's keyless embed, with an optional
  /// "Get directions" link (also the fallback when the map can't load) and
  /// text beside it. Nothing is hard-coded: every page sets its own place.
  static const map = BlockDefinition(
    type: 'map',
    version: 1,
    label: 'Map',
    description: 'A Google map of an address, with directions',
    styleKeys: ['background', 'spacing', 'textColor', 'bodyFontSize', 'headingColor', 'headingFontSize', 'width'],
    fields: [
      TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true),
      TextFieldSpec('address', 'Address or place name', maxLength: 300, required: true, translatable: false),
      ChoiceFieldSpec('mapType', 'Map type', options: ['roadmap', 'satellite'], initial: 'roadmap', optionLabels: {'roadmap': 'Map', 'satellite': 'Satellite'}),
      ChoiceFieldSpec('zoom', 'Zoom', options: ['10', '12', '13', '14', '15', '16', '17', '18'], initial: '15', optionLabels: {
        '10': '10 (city)',
        '12': '12',
        '13': '13',
        '14': '14',
        '15': '15 (neighbourhood)',
        '16': '16',
        '17': '17',
        '18': '18 (street)',
      }),
      ChoiceFieldSpec('height', 'Map height', options: ['240', '320', '400', '480'], initial: '320', optionLabels: {'240': '240 px', '320': '320 px', '400': '400 px', '480': '480 px'}),
      ToggleFieldSpec('showDirections', 'Show a “Get directions” link', initial: true),
      TextFieldSpec('details', 'Address and contact text (optional)', maxLength: 600, multiline: true),
    ],
    extraChecks: _mapChecks,
  );

  static List<String> _mapChecks(StructuredBlock b) {
    final address = b.text('address').en;
    return [if (address.contains(RegExp(r'[<>]'))) 'the address can’t contain < or >'];
  }

  static const divider = BlockDefinition(
    type: 'divider',
    version: 1,
    label: 'Divider',
    description: 'A thin line with space around it',
    styleKeys: ['spacing', 'lineColor', 'width'],
    fields: [ChoiceFieldSpec('size', 'Space', options: ['small', 'medium', 'large'], initial: 'medium')],
  );

  /// Every known block type, in the order the "Add block" menus show.
  static final List<BlockDefinition> all = [text, image, columns, cta, buttons, gallery, divider, section, hero, cards, features, pageHeader, notice, galleryFeed, eventsFeed, announcementsFeed, form, map];

  /// The block types that can go inside a section or columns.
  static List<BlockDefinition> get nestable => [for (final d in all) if (!containerTypes.contains(d.type)) d];

  static BlockDefinition? definition(String type) {
    for (final d in all) {
      if (d.type == type) return d;
    }
    return null;
  }

  // ------------------------------------------------------------ parsing

  /// [raw] as a block: a [StructuredBlock] when its type is known and its
  /// version supported, otherwise an [UnsupportedBlock] kept as stored.
  static WebsiteBlock parse(Object? raw) {
    if (raw is! Map) return UnsupportedBlock(raw);
    final definition = raw['type'] is String ? BlockRegistry.definition(raw['type'] as String) : null;
    final version = raw['v'];
    final id = raw['id'];
    if (definition == null || id is! String || (version != null && (version is! int || version < 1 || version > definition.version))) {
      return UnsupportedBlock(raw);
    }
    final parsed = parseFieldValues(raw, definition.fields);
    final values = Map<String, Object?>.of(parsed.values);
    final preserved = Map<String, Object?>.of(parsed.preserved);
    for (final field in definition.fields.whereType<ColumnsFieldSpec>()) {
      if (!preserved.containsKey(field.key)) values[field.key] = [for (final c in raw[field.key] as List? ?? const []) _parseColumn(c as Map)];
    }
    final style = raw['style'];
    if (style != null && style is! Map) preserved['style'] = style;
    return StructuredBlock(
      definition: definition,
      id: id,
      hidden: raw['hidden'] == true,
      style: style is Map ? {for (final e in style.entries) e.key.toString(): e.value} : const {},
      values: values,
      preserved: preserved,
    );
  }

  static BlockColumn _parseColumn(Map raw) => BlockColumn(
        id: raw['id'] is String ? raw['id'] as String : '',
        blocks: raw['blocks'] is List ? [for (final b in raw['blocks'] as List) parse(b)] : const [],
        preserved: {for (final e in raw.entries) if (e.key != 'id' && e.key != 'blocks') e.key.toString(): e.value},
      );

  static List<WebsiteBlock> parseList(Object? raw) => raw is List ? [for (final b in raw) parse(b)] : const [];

  /// The stored form of [blocks] (unsupported entries exactly as stored).
  static List<Object?> toMapList(List<WebsiteBlock> blocks) => storedBlockList(blocks);

  // ------------------------------------------------------------ creating

  /// A new, empty block of [type] with fresh ids (and the minimum items,
  /// or the layout's columns).
  static StructuredBlock create(BlockDefinition definition) {
    final values = <String, Object?>{for (final f in definition.fields) f.key: f.defaultValue};
    for (final f in definition.fields) {
      if (f is ItemsFieldSpec) {
        values[f.key] = [
          for (var i = 0; i < f.minItems; i++) BlockItem(id: BlockIds.item(), values: {for (final g in f.itemFields) g.key: g.defaultValue}),
        ];
      }
      if (f is ColumnsFieldSpec) {
        final widths = columnLayouts[values['layout']] ?? const [1, 1];
        values[f.key] = [for (final _ in widths) BlockColumn(id: BlockIds.column())];
      }
    }
    return StructuredBlock(definition: definition, id: BlockIds.block(), values: values);
  }

  /// A copy of [block] with fresh ids for it and everything inside it
  /// (items, columns and their blocks), so a duplicate never shares a
  /// translation path with its original. An unsupported block gets a new
  /// id too, if it had one.
  static WebsiteBlock duplicate(WebsiteBlock block) {
    if (block is UnsupportedBlock) return block.id.isEmpty ? block : UnsupportedBlock({...block.raw, 'id': BlockIds.block()});
    final b = block as StructuredBlock;
    final values = Map<String, Object?>.of(b.values);
    for (final f in b.definition.fields) {
      if (f is ItemsFieldSpec) values[f.key] = [for (final item in b.items(f.key)) item.withId(BlockIds.item())];
      if (f is ColumnsFieldSpec) {
        values[f.key] = [
          for (final c in b.columns(f.key)) c.copyWith(id: BlockIds.column(), blocks: [for (final child in c.blocks) duplicate(child)]),
        ];
      }
    }
    return b.copyWith(id: BlockIds.block(), values: values);
  }

  // ------------------------------------------------------------ walking

  /// [blocks] and every block inside their columns, depth first.
  static Iterable<WebsiteBlock> flatten(List<WebsiteBlock> blocks) sync* {
    for (final b in blocks) {
      yield b;
      if (b is StructuredBlock) {
        for (final f in b.definition.fields.whereType<ColumnsFieldSpec>()) {
          for (final c in b.columns(f.key)) {
            yield* flatten(c.blocks);
          }
        }
      }
    }
  }

  /// [blocks] without their hidden blocks, at every depth (a hidden section
  /// or columns block goes with everything inside it): what a published
  /// page stores, so a public document never carries content visitors
  /// aren't shown. The draft keeps the hidden blocks. Unsupported blocks
  /// stored as hidden are left out too; other blocks are unchanged.
  static List<WebsiteBlock> withoutHidden(List<WebsiteBlock> blocks) => [
        for (final b in blocks)
          if (b is StructuredBlock && !b.hidden)
            _withoutHiddenInside(b)
          else if (b is UnsupportedBlock && b.raw['hidden'] != true)
            b,
      ];

  static StructuredBlock _withoutHiddenInside(StructuredBlock block) {
    final containers = block.definition.fields.whereType<ColumnsFieldSpec>();
    if (containers.isEmpty) return block;
    final values = Map<String, Object?>.of(block.values);
    for (final f in containers) {
      values[f.key] = [for (final c in block.columns(f.key)) c.copyWith(blocks: withoutHidden(c.blocks))];
    }
    return block.copyWith(values: values);
  }

  /// Every image id [blocks] use (for the library's usage and publishing
  /// checks), in order, without repeats.
  static List<String> referencedMedia(List<WebsiteBlock> blocks) {
    final ids = <String>{};
    void add(Object? id) {
      if (id is String && id.trim().isNotEmpty) ids.add(id.trim());
    }

    for (final b in flatten(blocks)) {
      if (b is! StructuredBlock) continue;
      for (final f in b.definition.fields) {
        if (f is MediaFieldSpec) add(b.values[f.key]);
        if (f is ItemsFieldSpec) {
          for (final item in b.items(f.key)) {
            for (final g in f.itemFields.whereType<MediaFieldSpec>()) {
              add(item.values[g.key]);
            }
          }
        }
      }
    }
    return ids.toList();
  }

  // ------------------------------------------------------------ validation

  /// Problems with one block's own fields (not its page-level context),
  /// as messages without a location prefix. Unsupported blocks have none:
  /// they are kept, not shown.
  static List<String> blockProblems(WebsiteBlock block) {
    if (block is! StructuredBlock) return const [];
    final problems = <String>[];
    if (!BlockIds.isValid(block.id)) problems.add('its id is not valid');
    for (final key in block.preserved.keys) {
      if (block.definition.field(key) != null || key == 'style') problems.add('“$key” has a value this app can’t read');
    }
    for (final field in block.definition.fields) {
      // A value a block doesn't hold (one made before the field existed)
      // is its default, as when it is shown and saved.
      problems.addAll(_fieldProblems(field, block.values[field.key] ?? field.defaultValue, field.label));
    }
    for (final entry in block.style.entries) {
      if (BlockStyle.problem(entry.key, entry.value) case final p?) problems.add(p);
    }
    problems.addAll(block.definition.extraChecks?.call(block) ?? const []);
    return problems;
  }

  static List<String> _fieldProblems(FieldSpec field, Object? value, String label) {
    switch (field) {
      case TextFieldSpec():
        final text = value as LocalizedText? ?? const LocalizedText();
        return [
          if (field.required && text.en.trim().isEmpty) 'enter ${label.toLowerCase()} in English',
          ...text.problems(field.maxLength, label),
        ];
      case MediaFieldSpec():
        return [if (field.required && (value as String? ?? '').trim().isEmpty) 'choose ${label.toLowerCase() == 'image' ? 'an image' : label.toLowerCase()}'];
      case LinkFieldSpec():
        final target = (value as String? ?? '').trim();
        if (target.isEmpty) return [if (field.required) 'enter where the button should lead'];
        final error = SafeLinkTarget.validate(target);
        return [?error];
      case ChoiceFieldSpec():
        return [if (!field.options.contains(value)) '“$value” is not a ${label.toLowerCase()} option'];
      case ToggleFieldSpec():
        return const [];
      case FormRefFieldSpec():
        final id = (value as String? ?? '').trim();
        if (id.isEmpty) return [if (field.required) 'choose a form'];
        return [if (!FormRefFieldSpec.idPattern.hasMatch(id)) 'the chosen form can’t be identified'];
      case ItemsFieldSpec():
        final items = value as List<BlockItem>? ?? const [];
        return [
          if (items.length < field.minItems) 'add at least ${field.minItems} ${field.itemLabel.toLowerCase()}${field.minItems == 1 ? '' : 's'}',
          if (items.length > field.maxItems) 'at most ${field.maxItems} ${field.itemLabel.toLowerCase()}s',
          for (final (i, item) in items.indexed) ...[
            if (!BlockIds.isValid(item.id)) '${field.itemLabel} ${i + 1}: its id is not valid',
            for (final key in item.preserved.keys)
              if (field.itemFields.any((f) => f.key == key)) '${field.itemLabel} ${i + 1}: “$key” has a value this app can’t read',
            for (final f in field.itemFields)
              for (final p in _fieldProblems(f, item.values[f.key] ?? f.defaultValue, f.label)) '${field.itemLabel} ${i + 1}: $p',
          ],
        ];
      case ColumnsFieldSpec():
        final cols = value as List<BlockColumn>? ?? const [];
        return [
          for (final (i, c) in cols.indexed)
            if (!BlockIds.isValid(c.id)) 'column ${i + 1}: its id is not valid',
        ];
    }
  }

  /// Every problem that would stop [blocks] being saved, each starting with
  /// where it is ("Block 3 (Text): …", "Block 2 (Columns), column 1, block
  /// 1 (Image): …"): each block's fields, ids unique across the page
  /// (blocks, items and columns), nesting depth, counts and size.
  static List<String> validate(List<WebsiteBlock> blocks, {BlockLimits limits = BlockLimits.defaults}) {
    final errors = <String>[];
    final ids = <String>{};
    var count = 0;

    void claim(String id, String where) {
      if (id.isEmpty) return;
      if (!ids.add(id)) errors.add('$where: the id “$id” is used more than once on this page.');
    }

    void walk(List<WebsiteBlock> list, String prefix, int depth) {
      for (final (i, block) in list.indexed) {
        count++;
        final label = block is StructuredBlock ? block.definition.label : 'Unsupported block';
        final where = '$prefix${prefix.isEmpty ? 'Block' : 'block'} ${i + 1} ($label)';
        claim(block.id, where);
        if (block is! StructuredBlock) continue;
        for (final p in blockProblems(block)) {
          errors.add('$where: $p.');
        }
        for (final f in block.definition.fields) {
          if (f is ItemsFieldSpec) {
            for (final item in block.items(f.key)) {
              claim(item.id, where);
            }
          }
          if (f is ColumnsFieldSpec) {
            for (final (ci, c) in block.columns(f.key).indexed) {
              claim(c.id, where);
              if (depth + 1 > limits.maxNestingDepth && c.blocks.isNotEmpty) {
                errors.add('$where: blocks can be nested only ${limits.maxNestingDepth} level deep.');
                continue;
              }
              if (c.blocks.length > limits.maxColumnBlocks) errors.add('$where, column ${ci + 1}: at most ${limits.maxColumnBlocks} blocks.');
              walk(c.blocks, '$where, column ${ci + 1}, ', depth + 1);
            }
          }
        }
      }
    }

    walk(blocks, '', 0);
    if (count > limits.maxBlocks) errors.add('A page can have at most ${limits.maxBlocks} blocks.');
    final bytes = utf8.encode(jsonEncode(toMapList(blocks), toEncodable: (o) => o.toString())).length;
    if (bytes > limits.maxDocumentBytes) errors.add('This page is too large (${(bytes / 1024).ceil()} KB; at most ${limits.maxDocumentBytes ~/ 1024} KB). Split it into more pages.');
    return errors;
  }
}
