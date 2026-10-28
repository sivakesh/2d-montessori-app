import '../website_content_models.dart';
import 'block_ids.dart';
import 'block_registry.dart';
import 'field_spec.dart';
import 'website_block.dart';

/// A ready-made section the editor can add: a [BlockRegistry.section]
/// holding ordinary blocks with starter text, which the school replaces.
/// Every preset is valid as created (it can be saved at once), and every
/// id in it is new.
class SectionPreset {
  const SectionPreset._(this.id, this.label, this.description, this._build);

  final String id;
  final String label;
  final String description;
  final StructuredBlock Function() _build;

  /// A new section with fresh ids.
  StructuredBlock create() => _build();

  static StructuredBlock _child(BlockDefinition d, Map<String, Object?> values, {Map<String, dynamic> style = const {}}) {
    final block = BlockRegistry.create(d);
    return block.copyWith(values: {...block.values, ...values}, style: style);
  }

  static LocalizedText _en(String text) => LocalizedText(en: text);

  static BlockItem _button(String label, String target, {String variant = 'primary'}) =>
      BlockItem(id: BlockIds.item(), values: {'label': _en(label), 'target': target, 'variant': variant});

  static StructuredBlock _section(String name, String layout, List<List<WebsiteBlock>> columns, {Map<String, dynamic> style = const {}}) {
    final section = BlockRegistry.create(BlockRegistry.section);
    return section.copyWith(
      values: {
        ...section.values,
        'name': _en(name),
        'layout': layout,
        'columns': [for (final blocks in columns) BlockColumn(id: BlockIds.column(), blocks: blocks)],
      },
      style: style,
    );
  }

  static StructuredBlock _text(String heading, String body, {Map<String, dynamic> style = const {}}) =>
      _child(BlockRegistry.text, {'heading': _en(heading), 'body': _en(body)}, style: style);

  static final all = [
    SectionPreset._('blank', 'Blank section', 'An empty band to fill with blocks', () => _section('Section', '1', [[]])),
    SectionPreset._(
      'hero',
      'Hero',
      'Large heading, introduction and a button',
      () => _section('Hero', '1', [
        [
          _child(BlockRegistry.hero, {
            'eyebrow': _en('WELCOME'),
            'heading': _en('A calm, thoughtful place to learn and grow'),
            'body': _en('Introduce your school in a sentence or two.'),
            'decor': true,
            'buttons': [_button('Explore admissions', '/admissions')],
          }),
        ],
      ], style: const {'padding': '88', 'width': 'wide', 'spacing': 'none'}),
    ),
    SectionPreset._(
      'about',
      'About',
      'Two columns: who you are, and what makes you different',
      () => _section('About', '1:1', [
        [_text('About us', 'Tell families who you are and what you believe about children’s learning.')],
        [_text('Our story', 'Share how the school began and what guides it today.')],
      ]),
    ),
    SectionPreset._(
      'programs',
      'Programs',
      'Three programs side by side',
      () => _section('Programs', '1:1:1', [
        [_text('Toddler', 'Ages, days and what a morning looks like.')],
        [_text('Primary', 'Ages, days and what a morning looks like.')],
        [_text('Elementary', 'Ages, days and what a morning looks like.')],
      ], style: const {'background': 'token:sageLight'}),
    ),
    SectionPreset._(
      'features',
      'Features',
      'Key points with icons',
      () => _section('Features', '1', [
        [
          _child(BlockRegistry.features, {
            'eyebrow': _en('WHY FAMILIES CHOOSE US'),
            'heading': _en('What makes us different'),
            'items': [
              BlockItem(id: BlockIds.item(), values: {'icon': 'spa', 'title': _en('Follow the child'), 'body': _en('Learning that responds to each child.')}),
              BlockItem(id: BlockIds.item(), values: {'icon': 'grid', 'title': _en('Prepared environment'), 'body': _en('Orderly, purposeful spaces.')}),
              BlockItem(id: BlockIds.item(), values: {'icon': 'care', 'title': _en('Independence'), 'body': _en('Everyday practice in doing things for oneself.')}),
            ],
          }),
        ],
      ], style: const {'width': 'wide'}),
    ),
    SectionPreset._(
      'testimonials',
      'Testimonials',
      'Three quotes from families',
      () => _section('Testimonials', '1:1:1', [
        for (final n in [1, 2, 3]) [_text('“A quote from a family.”', '— Parent $n', style: const {'align': 'center'})],
      ], style: const {'background': 'token:goldLight'}),
    ),
    SectionPreset._(
      'gallery',
      'Gallery',
      'The school’s published photographs, with filters',
      () => _section('Gallery', '1', [
        [_text('Life at school', ''), _child(BlockRegistry.galleryFeed, const {})],
      ], style: const {'width': 'wide'}),
    ),
    SectionPreset._(
      'events',
      'Events',
      'Upcoming calendar events shown on the website',
      () => _section('Events', '1', [
        [_child(BlockRegistry.eventsFeed, {'heading': _en('Upcoming events')})],
      ]),
    ),
    SectionPreset._(
      'announcements',
      'Announcements',
      'The latest school announcements shown on the website',
      () => _section('Announcements', '1', [
        [_child(BlockRegistry.announcementsFeed, {'heading': _en('Announcements')})],
      ]),
    ),
    SectionPreset._(
      'faq',
      'FAQ',
      'Common questions and their answers',
      () => _section('FAQ', '1', [
        [
          _text('Frequently asked questions', ''),
          _text('What ages do you welcome?', 'Answer the question here.', style: const {'spacing': 'compact'}),
          _text('How do admissions work?', 'Answer the question here.', style: const {'spacing': 'compact'}),
          _text('Can we visit?', 'Answer the question here.', style: const {'spacing': 'compact'}),
        ],
      ], style: const {'width': 'narrow'}),
    ),
    SectionPreset._(
      'cta',
      'Call to action',
      'A heading, text and a button',
      () => _section('Call to action', '1', [
        [
          _child(BlockRegistry.cta, {
            'heading': _en('Come and see us'),
            'body': _en('Book a visit to see a morning in our classrooms.'),
            'buttons': [_button('Contact us', '/contact')],
          }),
        ],
      ]),
    ),
    SectionPreset._(
      'contact',
      'Contact',
      'How to reach the school',
      () => _section('Contact', '1:1', [
        [_text('Contact us', 'Add your address and opening hours here.')],
        [
          _text('Visit or call', 'Add your phone number and email here.'),
          _child(BlockRegistry.buttons, {
            'buttons': [_button('Admissions', '/admissions', variant: 'secondary')],
          }),
        ],
      ], style: const {'background': 'token:sageLight'}),
    ),
  ];

  static SectionPreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}
