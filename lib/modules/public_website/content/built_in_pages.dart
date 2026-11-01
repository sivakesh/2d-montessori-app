import '../public_routes.dart';
import '../public_strings.dart';
import 'blocks/block_registry.dart';
import 'blocks/field_spec.dart';
import 'blocks/website_block.dart';
import 'website_content_models.dart';

/// The public website's built-in pages, as the visual editor knows them.
/// Each can be built with blocks, stored in its own document of the page
/// drafts and live pages collections: the managed pages' existing slot
/// documents (`home`, `admissions` …, next to their headline, introduction
/// and image, which stay untouched for older versions of the app) and a
/// `contact` document.
///
/// A built-in page shows its blocks only once they are published; until
/// then, and after "Return to the built-in page", it shows exactly what it
/// showed before.
enum BuiltInPage {
  home('home', PublicRoutes.home, 'Home'),
  admissions('admissions', PublicRoutes.admissions, 'Admissions'),
  teacherTraining('teacher_training', PublicRoutes.teacherTraining, 'Teacher Training'),
  programs('programs', PublicRoutes.programs, 'Programs'),
  gallery('gallery', PublicRoutes.gallery, 'Gallery'),
  contact('contact', PublicRoutes.contact, 'Contact');

  const BuiltInPage(this.id, this.route, this.label);

  /// Document id in the page drafts and live pages collections.
  final String id;
  final String route;
  final String label;

  /// The managed content slot (headline, introduction, image) this page
  /// already has; Contact has none.
  WebsitePageSlot? get slot => WebsitePageSlot.parse(id);

  static BuiltInPage? parse(String id) {
    for (final page in values) {
      if (page.id == id) return page;
    }
    return null;
  }

  static BuiltInPage? forRoute(String route) {
    for (final page in values) {
      if (page.route == route) return page;
    }
    return null;
  }
}

/// Builds the blocks that reproduce a built-in page as it is today: the
/// site's own wording in English and Tamil, and the page's managed
/// headline, introduction and image (every language kept). Ids are
/// derived from the page (`home__hero`, …), so converting again gives the
/// same ids and translation paths. Nothing is stored here.
class BuiltInPageAdapter {
  BuiltInPageAdapter._();

  static final _en = PublicStrings.of(PublicLanguage.english);
  static final _ta = PublicStrings.of(PublicLanguage.tamil);

  static LocalizedText _t(String Function(PublicStrings s) pick) => LocalizedText(en: pick(_en), ta: pick(_ta));

  /// [managed] when it has text, otherwise the built-in wording.
  static LocalizedText _or(LocalizedText? managed, LocalizedText builtIn) => managed == null || managed.isEmpty ? builtIn : managed;

  static StructuredBlock _block(BlockDefinition d, String id, Map<String, Object?> values, {Map<String, dynamic> style = const {}}) =>
      StructuredBlock(definition: d, id: id, values: {for (final f in d.fields) f.key: f.defaultValue, ...values}, style: style);

  static StructuredBlock _section(String id, List<WebsiteBlock> children, Map<String, dynamic> style) => _block(
        BlockRegistry.section,
        id,
        {
          'layout': '1',
          'columns': [BlockColumn(id: '${id}__c1', blocks: children)],
        },
        style: style,
      );

  /// The blocks for [page], given its managed [content] (the draft being
  /// edited, else what is live; null when it has none).
  static List<WebsiteBlock> blocksFor(BuiltInPage page, WebsitePageContent? content) {
    final id = page.id;
    final headline = content?.headline;
    final intro = content?.intro;
    final image = content?.imageMediaId ?? '';
    switch (page) {
      case BuiltInPage.home:
        return [
          _section('home__s_hero', [
            _block(BlockRegistry.hero, 'home__hero', {
              'eyebrow': _t((s) => s.heroEyebrow),
              'heading': _or(headline, _t((s) => s.heroTitle)),
              'body': _or(intro, _t((s) => s.heroBody)),
              'mediaId': image,
              'decor': true,
            }),
          ], const {'width': 'wide', 'padding': '88', 'spacing': 'none'}),
          _section('home__s_pathways', [
            _block(BlockRegistry.cards, 'home__pathways', {
              'heading': _t((s) => s.pathwaysTitle),
              'cards': [
                BlockItem(id: 'home__families', values: {
                  'icon': 'family',
                  'title': _t((s) => s.familiesTitle),
                  'body': _t((s) => s.familiesBody),
                  'linkLabel': _t((s) => s.familiesCta),
                  'target': PublicRoutes.admissions,
                  'accent': 'primary',
                }),
                BlockItem(id: 'home__educators', values: {
                  'icon': 'school',
                  'title': _t((s) => s.educatorsTitle),
                  'body': _t((s) => s.educatorsBody),
                  'linkLabel': _t((s) => s.educatorsCta),
                  'target': PublicRoutes.teacherTraining,
                  'accent': 'secondary',
                }),
              ],
            }),
          ], const {'width': 'wide', 'padding': '72', 'spacing': 'none', 'background': 'token:surface'}),
          _section('home__s_approach', [
            _block(BlockRegistry.features, 'home__approach', {
              'eyebrow': _t((s) => s.approachEyebrow),
              'heading': _t((s) => s.approachTitle),
              'items': [
                BlockItem(id: 'home__p_child', values: {'icon': 'spa', 'title': _t((s) => s.principleChildTitle), 'body': _t((s) => s.principleChildBody)}),
                BlockItem(id: 'home__p_environment', values: {'icon': 'grid', 'title': _t((s) => s.principleEnvironmentTitle), 'body': _t((s) => s.principleEnvironmentBody)}),
                BlockItem(id: 'home__p_independence', values: {'icon': 'care', 'title': _t((s) => s.principleIndependenceTitle), 'body': _t((s) => s.principleIndependenceBody)}),
              ],
            }),
          ], const {'width': 'wide', 'padding': '80', 'spacing': 'none'}),
        ];
      case BuiltInPage.gallery:
        return [
          _section('gallery__s_header', [
            _block(BlockRegistry.pageHeader, 'gallery__header', {
              'heading': _or(headline, _t((s) => s.gallery)),
              'intro': _or(intro, _t((s) => s.galleryIntro)),
              'mediaId': image,
              'placeholder': false,
            }),
          ], const {'width': 'narrow', 'paddingTop': '88', 'paddingBottom': '48', 'spacing': 'none'}),
          _section('gallery__s_feed', [
            _block(BlockRegistry.galleryFeed, 'gallery__feed', const {}),
          ], const {'width': 'wide', 'paddingTop': '0', 'paddingBottom': '88', 'spacing': 'none'}),
        ];
      case BuiltInPage.admissions || BuiltInPage.teacherTraining || BuiltInPage.programs || BuiltInPage.contact:
        final hasSlot = page.slot != null;
        return [
          _section('${id}__s_page', [
            _block(BlockRegistry.pageHeader, '${id}__header', {
              'heading': _or(headline, _t((s) => s.labelFor(page.route))),
              'intro': _or(intro, _t((s) => s.introFor(page.route))),
              'mediaId': image,
              // Pages with an image slot show a decorative placeholder
              // until a photograph is published.
              'placeholder': hasSlot,
            }),
            _block(BlockRegistry.notice, '${id}__notice', {'title': _t((s) => s.comingSoonTitle), 'body': _t((s) => s.comingSoonBody)}),
            _block(BlockRegistry.buttons, '${id}__back', {
              'align': 'start',
              'buttons': [
                BlockItem(id: '${id}__back_home', values: {'label': _t((s) => s.backHome), 'target': PublicRoutes.home, 'variant': 'back'}),
              ],
            }, style: const {'spacing': 'normal'}),
          ], const {'width': 'narrow', 'padding': '96', 'spacing': 'none'}),
        ];
    }
  }
}
