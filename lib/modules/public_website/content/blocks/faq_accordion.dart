import 'field_spec.dart';
import 'website_block.dart';

/// The FAQ accordion block (`faq`): an optional heading and description,
/// then questions that open to show their answers. One answer open at a
/// time (opening one closes the other) or several; all closed at first, or
/// the first open. Items may start a category (a small heading above them,
/// e.g. Admissions, Fees), optional.
///
/// Every presentation setting is optional (Automatic until set: the
/// defaults below, matching the site's warm, quiet look) and only those
/// changed are stored. Sizes and spacing can differ on tablets and phones;
/// a screen without its own follows the larger one. Malformed values fall
/// back to the defaults (and are flagged in the editor).
abstract final class FaqAccordion {
  static const type = 'faq';
  static const maxItems = 60;

  static const single = 'single';
  static const multiple = 'multiple';
  static const modes = [single, multiple];

  static const closed = 'none';
  static const first = 'first';
  static const initialStates = [closed, first];

  static const weights = ['auto', '400', '500', '600', '700', '800'];
  static const lineHeights = ['auto', '1.3', '1.4', '1.5', '1.6', '1.7', '1.8', '2.0'];

  /// The default icons, from the shared library (WebsiteIcons).
  static const expandIcon = 'plus';
  static const collapseIcon = 'minus';

  // Defaults (px) on desktop, tablets and phones.
  static const questionSizes = (desktop: 18, tablet: 18, mobile: 16);
  static const answerSizes = (desktop: 16, tablet: 16, mobile: 15);
  static const paddings = (desktop: 24, tablet: 22, mobile: 18);
  static const gaps = (desktop: 16, tablet: 14, mobile: 12);
  static const defaultRadius = 16;
  static const defaultContainerRadius = 16;
  static const defaultIconSize = 18;
  static const defaultQuestionWeight = 600;
  static const defaultAnswerWeight = 400;
  static const defaultLineHeight = 1.6;

  // ----------------------------------------------------------- reading

  static int? _n(StructuredBlock b, String k) => b.values[k] is int ? b.values[k] as int : null;

  /// [key] (desktop), `tablet…` and `mobile…` on [screen] ('desktop',
  /// 'tablet', 'mobile'): a screen without its own follows the larger one;
  /// clamped to [min]–[max].
  static double responsive(StructuredBlock b, String key, String screen, ({int desktop, int tablet, int mobile}) defaults, int min, int max) {
    final cap = key[0].toUpperCase() + key.substring(1);
    final desktop = _n(b, key);
    final tablet = _n(b, 'tablet$cap') ?? desktop;
    final mobile = _n(b, 'mobile$cap') ?? tablet;
    final v = switch (screen) {
      'mobile' => mobile ?? defaults.mobile,
      'tablet' => tablet ?? defaults.tablet,
      _ => desktop ?? defaults.desktop,
    };
    return v.clamp(min, max).toDouble();
  }

  static double questionSize(StructuredBlock b, String screen) => responsive(b, 'questionSize', screen, questionSizes, 12, 40);
  static double answerSize(StructuredBlock b, String screen) => responsive(b, 'answerSize', screen, answerSizes, 12, 32);
  static double padding(StructuredBlock b, String screen) => responsive(b, 'itemPadding', screen, paddings, 8, 64);
  static double gap(StructuredBlock b, String screen) => responsive(b, 'itemGap', screen, gaps, 0, 48);
  static double radius(StructuredBlock b) => (_n(b, 'radius') ?? defaultRadius).clamp(0, 40).toDouble();

  /// The FAQ container's corners (its own setting, independent of the
  /// cards'): 16 px unless set, also for blocks saved before it existed.
  static double containerRadius(StructuredBlock b) => (_n(b, 'containerRadius') ?? defaultContainerRadius).clamp(0, 48).toDouble();
  static double iconSize(StructuredBlock b) => (_n(b, 'iconSize') ?? defaultIconSize).clamp(12, 40).toDouble();
  static double borderWidth(StructuredBlock b) => double.tryParse(b.string('borderWidth')) ?? 1;

  static int _weight(StructuredBlock b, String key, int fallback) => int.tryParse(b.string(key)) ?? fallback;
  static int questionWeight(StructuredBlock b) => _weight(b, 'questionWeight', defaultQuestionWeight);
  static int answerWeight(StructuredBlock b) => _weight(b, 'answerWeight', defaultAnswerWeight);
  static double lineHeight(StructuredBlock b) => double.tryParse(b.string('answerLineHeight')) ?? defaultLineHeight;

  static bool multipleOpen(StructuredBlock b) => b.string('mode') == multiple;
  static bool firstOpen(StructuredBlock b) => b.string('initiallyOpen') == first;

  /// The icon ids (an unset or removed one: the default).
  static String expandIconOf(StructuredBlock b) => _icon(b.string('expandIcon'), expandIcon);
  static String collapseIconOf(StructuredBlock b) => _icon(b.string('collapseIcon'), collapseIcon);
  static String _icon(String id, String fallback) => id.trim().isEmpty || id == IconFieldSpec.none ? fallback : id;

  // ----------------------------------------------------------- fields

  static bool _circle(Map<String, Object?> values, Map<String, Object?> block) => block['iconCircle'] != false;

  static const _behaviour = 'Behaviour';
  static const _question = 'Questions';
  static const _answer = 'Answers';
  static const _items = 'Items and container';
  static const _icons = 'Icons';

  static const _questionWeights = {'auto': 'Automatic (semi-bold)', '400': 'Regular', '500': 'Medium', '600': 'Semi-bold', '700': 'Bold', '800': 'Extra bold'};
  static const _answerWeights = {'auto': 'Automatic (regular)', '400': 'Regular', '500': 'Medium', '600': 'Semi-bold', '700': 'Bold', '800': 'Extra bold'};

  static const itemFields = <FieldSpec>[
    TextFieldSpec('category', 'Category heading (optional; shown above this question, e.g. Admissions)', maxLength: 80, omitDefault: true),
    TextFieldSpec('question', 'Question', maxLength: 300, required: true, translationRequired: true),
    TextFieldSpec('answer', 'Answer (line breaks are kept)', maxLength: 4000, multiline: true, required: true),
  ];

  static const fields = <FieldSpec>[
    TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true, omitDefault: true),
    TextFieldSpec('description', 'Description', maxLength: 600, multiline: true, omitDefault: true),
    ItemsFieldSpec('items', 'Questions', itemLabel: 'Question', minItems: 1, maxItems: maxItems, itemFields: itemFields, duplicable: true),
    ChoiceFieldSpec('mode', 'Opening answers', options: modes, initial: single, omitDefault: true, group: _behaviour, optionLabels: {
      single: 'One at a time (opening one closes the other)',
      multiple: 'Several at once',
    }),
    ChoiceFieldSpec('initiallyOpen', 'When the page opens', options: initialStates, initial: closed, omitDefault: true, group: _behaviour, optionLabels: {
      closed: 'All answers closed',
      first: 'The first answer open',
    }),
    NumberFieldSpec('questionSize', 'Question size on desktop', min: 12, max: 40, unit: 'px', automaticLabel: 'Automatic (18 px)', group: _question),
    NumberFieldSpec('tabletQuestionSize', 'Question size on tablets', min: 12, max: 40, unit: 'px', automaticLabel: 'Automatic (as on desktop, else 18 px)', group: _question),
    NumberFieldSpec('mobileQuestionSize', 'Question size on phones', min: 12, max: 40, unit: 'px', automaticLabel: 'Automatic (as on tablets, else 16 px)', group: _question),
    ChoiceFieldSpec('questionWeight', 'Question weight', options: weights, initial: 'auto', omitDefault: true, group: _question, optionLabels: _questionWeights),
    ColorFieldSpec('questionColor', 'Question colour', automaticLabel: 'the site’s deep forest green', omitDefault: true, group: _question),
    ChoiceFieldSpec('questionAlign', 'Question alignment', options: ['start', 'center', 'end'], initial: 'start', omitDefault: true, group: _question, optionLabels: {
      'start': 'Left',
      'center': 'Centre',
      'end': 'Right',
    }),
    NumberFieldSpec('answerSize', 'Answer size on desktop', min: 12, max: 32, unit: 'px', automaticLabel: 'Automatic (16 px)', group: _answer),
    NumberFieldSpec('tabletAnswerSize', 'Answer size on tablets', min: 12, max: 32, unit: 'px', automaticLabel: 'Automatic (as on desktop, else 16 px)', group: _answer),
    NumberFieldSpec('mobileAnswerSize', 'Answer size on phones', min: 12, max: 32, unit: 'px', automaticLabel: 'Automatic (as on tablets, else 15 px)', group: _answer),
    ChoiceFieldSpec('answerWeight', 'Answer weight', options: weights, initial: 'auto', omitDefault: true, group: _answer, optionLabels: _answerWeights),
    ColorFieldSpec('answerColor', 'Answer colour', automaticLabel: 'the site’s muted text', omitDefault: true, group: _answer),
    ChoiceFieldSpec('answerLineHeight', 'Answer line height', options: lineHeights, initial: 'auto', omitDefault: true, group: _answer, optionLabels: {'auto': 'Automatic (1.6)'}),
    // Four separate backgrounds and borders: this container (behind the
    // heading, description and every question; `sectionBackground`, its key
    // since the block was added), each question card, and the card's border
    // closed and open. The section around the block keeps its own
    // background (the section's Design panel).
    ColorFieldSpec('sectionBackground', 'FAQ container background (behind the heading, description and all questions)',
        automaticLabel: 'the site’s warm white', omitDefault: true, group: _items),
    NumberFieldSpec('containerRadius', 'Corner radius of the FAQ container', min: 0, max: 48, unit: 'px', automaticLabel: 'Automatic (16 px)', group: _items),
    ColorFieldSpec('itemBackground', 'Question card background', automaticLabel: 'white', omitDefault: true, group: _items),
    ColorFieldSpec('borderColor', 'Question card border colour', automaticLabel: 'the site’s line colour', omitDefault: true, group: _items),
    ColorFieldSpec('openBorderColor', 'Question card border colour when open', automaticLabel: 'the site’s gold', omitDefault: true, group: _items),
    ChoiceFieldSpec('borderWidth', 'Question card border width', options: ['0', '1', '2', '3'], initial: '1', omitDefault: true, group: _items, optionLabels: {'0': 'None', '1': '1 px', '2': '2 px', '3': '3 px'}),
    NumberFieldSpec('radius', 'Question card corner radius', min: 0, max: 40, unit: 'px', automaticLabel: 'Automatic (16 px)', group: _items),
    NumberFieldSpec('itemGap', 'Space between questions on desktop', min: 0, max: 48, unit: 'px', automaticLabel: 'Automatic (16 px)', group: _items),
    NumberFieldSpec('tabletItemGap', 'Space between questions on tablets', min: 0, max: 48, unit: 'px', automaticLabel: 'Automatic (as on desktop, else 14 px)', group: _items),
    NumberFieldSpec('mobileItemGap', 'Space between questions on phones', min: 0, max: 48, unit: 'px', automaticLabel: 'Automatic (as on tablets, else 12 px)', group: _items),
    NumberFieldSpec('itemPadding', 'Padding inside a question on desktop', min: 8, max: 64, unit: 'px', automaticLabel: 'Automatic (24 px)', group: _items),
    NumberFieldSpec('tabletItemPadding', 'Padding inside a question on tablets', min: 8, max: 64, unit: 'px', automaticLabel: 'Automatic (as on desktop, else 22 px)', group: _items),
    NumberFieldSpec('mobileItemPadding', 'Padding inside a question on phones', min: 8, max: 64, unit: 'px', automaticLabel: 'Automatic (as on tablets, else 18 px)', group: _items),
    IconFieldSpec('expandIcon', 'Icon when closed', initial: expandIcon, omitDefault: true, group: _icons),
    IconFieldSpec('collapseIcon', 'Icon when open', initial: collapseIcon, omitDefault: true, group: _icons),
    ColorFieldSpec('iconColor', 'Icon colour', automaticLabel: 'the site’s deep forest green', omitDefault: true, group: _icons),
    NumberFieldSpec('iconSize', 'Icon size', min: 12, max: 40, unit: 'px', automaticLabel: 'Automatic (18 px)', group: _icons),
    ToggleFieldSpec('iconCircle', 'Circle around the icon', initial: true, omitDefault: true, group: _icons),
    ColorFieldSpec('iconCircleColor', 'Circle colour', automaticLabel: 'the site’s line colour', omitDefault: true, group: _icons, shownWhen: _circle),
  ];
}
