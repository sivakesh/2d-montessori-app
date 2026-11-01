import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import 'field_spec.dart';
import 'website_block.dart';

/// The Asymmetric gallery block (`asymmetric_gallery`): 1–12 photographs
/// in an editorial composition. Everything is a setting: the arrangement,
/// the feature image and where it sits, proportions, shapes, gaps and the
/// images shown, separately for desktop, tablets and phones (each
/// Automatic until set); how images look (defaults for the block, and per
/// image); captions; links and the larger view.
///
/// Only settings that are changed are stored. Layout is computed here, from
/// the settings and the width available ([AsymmetricLayout.compute]), as
/// rectangles within that width: the editor's canvas and the website use
/// the same code, so they always agree, and nothing is wider than the page.
int? _int(StructuredBlock block, String key) => block.values[key] as int?;

abstract final class AsymmetricGallery {
  static const type = 'asymmetric_gallery';
  static const maxImages = 12;

  static const arrangements = ['editorial', 'feature', 'mosaic', 'staggered', 'custom'];
  static const arrangementLabels = {
    'editorial': 'Asymmetric editorial',
    'feature': 'Large feature image with supporting images',
    'mosaic': 'Mosaic',
    'staggered': 'Staggered grid',
    'custom': 'Custom arrangement',
  };
  static const positions = ['left', 'right', 'top', 'bottom'];
  static const featureWidths = ['40', '45', '50', '55', '60', '65', 'custom'];

  /// Image shapes (width:height); `auto` is the photograph's own shape (or
  /// the block's), `custom` a ratio entered by the editor.
  static const aspects = ['auto', '1:1', '5:4', '4:5', '4:3', '3:2', '16:9', 'custom'];
  static const aspectLabels = {
    'auto': 'Automatic',
    '1:1': 'Square (1:1)',
    '5:4': 'Landscape (5:4)',
    '4:5': 'Portrait (4:5)',
    '4:3': '4:3',
    '3:2': '3:2',
    '16:9': 'Wide (16:9)',
    'custom': 'Custom ratio',
  };
  static const supportingLayouts = ['auto', 'column', 'grid', 'row'];
  static const columnCounts = ['auto', '2', '3', '4', '5', '6'];
  static const spans = ['auto', '1', '2', '3', '4', '5', '6'];

  /// The most a shape may be wide (4:1) or tall (1:4).
  static const maxRatio = 4.0;

  static const screens = ['desktop', 'tablet', 'mobile'];
  static const screenNames = {'desktop': 'desktop', 'tablet': 'tablets', 'mobile': 'phones'};

  /// A setting's key for [screen] (desktop keys are plain: `arrangement`,
  /// `tabletArrangement`, `mobileArrangement`).
  static String keyFor(String screen, String name) => screen == 'desktop' ? name : '$screen${name[0].toUpperCase()}${name.substring(1)}';

  /// "W:H" as width / height, or null (not a ratio, or beyond 4:1 / 1:4).
  static double? parseRatio(String text) {
    final m = RegExp(r'^\s*(\d{1,4}(?:\.\d{1,3})?)\s*[:/x]\s*(\d{1,4}(?:\.\d{1,3})?)\s*$').firstMatch(text);
    if (m == null) return null;
    final w = double.parse(m.group(1)!);
    final h = double.parse(m.group(2)!);
    if (w <= 0 || h <= 0) return null;
    final r = w / h;
    return r > maxRatio + 1e-9 || r < 1 / maxRatio - 1e-9 ? null : r;
  }

  /// The ratio of shape option [option] (with its custom text), or null for
  /// Automatic (or a custom ratio not yet valid).
  static double? ratioOf(String option, String custom) => switch (option) {
        'custom' => parseRatio(custom),
        'auto' => null,
        _ => parseRatio(option),
      };

  // ----------------------------------------------------------- fields

  static const _autoNote = {
    'desktop': 'Automatic',
    'tablet': 'Automatic (as on desktop)',
    'mobile': 'Automatic',
  };

  static List<FieldSpec> _screenFields(String screen) {
    final group = 'Layout on ${screenNames[screen]}';
    String k(String name) => keyFor(screen, name);
    final auto = _autoNote[screen]!;
    return [
      ChoiceFieldSpec(k('arrangement'), 'Arrangement', options: ['auto', ...arrangements], initial: 'auto', omitDefault: true, group: group, optionLabels: {
        'auto': switch (screen) {
          'desktop' => 'Automatic (Asymmetric editorial)',
          'tablet' => 'Automatic (as on desktop)',
          _ => 'Automatic (feature on top, the rest two by two)',
        },
        ...arrangementLabels,
      }),
      ChoiceFieldSpec(k('featurePosition'), 'Feature image position', options: ['auto', ...positions], initial: 'auto', omitDefault: true, group: group, optionLabels: {
        'auto': screen == 'mobile' ? 'Automatic (top)' : (screen == 'tablet' ? auto : 'Automatic (left)'),
        'left': 'Left',
        'right': 'Right',
        'top': 'Top',
        'bottom': 'Bottom',
      }),
      ChoiceFieldSpec(k('featureWidth'), 'Feature image width (beside the others)', options: ['auto', ...featureWidths], initial: 'auto', omitDefault: true, group: group, optionLabels: {
        'auto': screen == 'tablet' ? auto : 'Automatic (60% editorial, 55% feature)',
        for (final w in featureWidths) w: w == 'custom' ? 'Custom' : '$w%',
      }),
      NumberFieldSpec(k('featureWidthCustom'), 'Custom feature width', min: 25, max: 80, unit: '%', automaticLabel: 'Choose Custom above, then enter it', group: group),
      NumberFieldSpec(k('featureHeight'), 'Feature image height', min: 120, max: 1000, unit: 'px', automaticLabel: 'Automatic (from its shape)', group: group),
      ChoiceFieldSpec(k('featureAspect'), 'Feature image shape', options: aspects, initial: 'auto', omitDefault: true, group: group,
          optionLabels: {...aspectLabels, 'auto': screen == 'tablet' ? auto : 'Automatic (the photograph’s own)'}),
      TextFieldSpec(k('featureAspectCustom'), 'Custom feature shape (width:height, e.g. 7:5)', maxLength: 11, translatable: false, omitDefault: true, group: group),
      ChoiceFieldSpec(k('supportingLayout'), 'Supporting images', options: supportingLayouts, initial: 'auto', omitDefault: true, group: group, optionLabels: const {
        'auto': 'Automatic',
        'column': 'One above another',
        'grid': 'Two by two',
        'row': 'Side by side',
      }),
      ChoiceFieldSpec(k('supportingAspect'), 'Supporting image shape', options: aspects, initial: 'auto', omitDefault: true, group: group,
          optionLabels: {...aspectLabels, 'auto': screen == 'tablet' ? auto : 'Automatic'}),
      TextFieldSpec(k('supportingAspectCustom'), 'Custom supporting shape (width:height)', maxLength: 11, translatable: false, omitDefault: true, group: group),
      ChoiceFieldSpec(k('columns'), 'Columns (mosaic, staggered, custom)', options: columnCounts, initial: 'auto', omitDefault: true, group: group, optionLabels: {
        'auto': switch (screen) {
          'desktop' => 'Automatic (4 mosaic, 3 staggered, 6 custom)',
          'tablet' => 'Automatic (3 mosaic, 2 staggered, 4 custom)',
          _ => 'Automatic (2)',
        },
      }),
      NumberFieldSpec(k('gapX'), 'Space between images, across', min: 0, max: 96, unit: 'px', automaticLabel: 'Automatic (the image gap)', group: group),
      NumberFieldSpec(k('gapY'), 'Space between images, down', min: 0, max: 96, unit: 'px', automaticLabel: 'Automatic (the image gap)', group: group),
    ];
  }

  static String? _badge(List<BlockItem> items, int index) {
    final marked = items.indexWhere((i) => i.value<bool>('feature') == true);
    if (marked == index) return 'Feature image';
    if (marked < 0 && index == 0) return 'Feature image (first, automatically)';
    return null;
  }

  static const _imageLook = 'Shape and appearance (this image)';
  static const _imageLink = 'Caption, link and larger view';
  static const _imageScreens = 'Screen sizes and order';
  static const _imageSpans = 'Size in a custom arrangement';

  static final List<FieldSpec> itemFields = [
    const MediaFieldSpec('mediaId', 'Image', required: true),
    const ToggleFieldSpec('feature', 'Feature image', exclusive: true, omitDefault: true),
    const TextFieldSpec('alt', 'Alt text (describes the image; replaces the Media library’s)', maxLength: 300, omitDefault: true),
    const ToggleFieldSpec('decorative', 'Decorative only (no alt text; screen readers skip it)', omitDefault: true),
    const TextFieldSpec('caption', 'Caption (replaces the library’s)', maxLength: 300, omitDefault: true),
    const ChoiceFieldSpec('captionPlacement', 'Caption placement', options: ['auto', 'below', 'overlay', 'none'], initial: 'auto', omitDefault: true, group: _imageLink, optionLabels: {
      'auto': 'Automatic (the block’s)',
      'below': 'Below the image',
      'overlay': 'Over the image',
      'none': 'No caption',
    }),
    const LinkFieldSpec('target', 'Link (optional)', omitDefault: true, group: _imageLink),
    const ChoiceFieldSpec('action', 'When clicked', options: ['auto', 'link', 'lightbox', 'none'], initial: 'auto', omitDefault: true, group: _imageLink, optionLabels: {
      'auto': 'Automatic (its link, else the larger view)',
      'link': 'Follow the link',
      'lightbox': 'Open the larger view',
      'none': 'Nothing',
    }),
    const ToggleFieldSpec('newTab', 'Open other websites in a new tab', initial: true, omitDefault: true, group: _imageLink),
    ChoiceFieldSpec('aspect', 'Shape', options: aspects, initial: 'auto', omitDefault: true, group: _imageLook, optionLabels: {...aspectLabels, 'auto': 'Automatic (the layout’s)'}),
    const TextFieldSpec('aspectCustom', 'Custom shape (width:height)', maxLength: 11, translatable: false, omitDefault: true, group: _imageLook),
    const ChoiceFieldSpec('weight', 'Relative size', options: ['auto', '1', '2', '3'], initial: 'auto', omitDefault: true, group: _imageLook, optionLabels: {
      'auto': 'Automatic (normal)',
      '1': 'Normal',
      '2': 'Larger',
      '3': 'Largest',
    }),
    const ChoiceFieldSpec('fit', 'Fit', options: ['auto', 'cover', 'contain'], initial: 'auto', omitDefault: true, group: _imageLook, optionLabels: {
      'auto': 'Automatic (the block’s)',
      'cover': 'Cover (fill, cropping the edges)',
      'contain': 'Contain (whole image)',
    }),
    const NumberFieldSpec('focalX', 'Focus across (0 = left, 100 = right)', min: 0, max: 100, unit: '%', automaticLabel: 'Automatic (the block’s, else the Media library’s)', group: _imageLook),
    const NumberFieldSpec('focalY', 'Focus down (0 = top, 100 = bottom)', min: 0, max: 100, unit: '%', automaticLabel: 'Automatic (the block’s, else the Media library’s)', group: _imageLook),
    const NumberFieldSpec('radius', 'Corner radius', min: 0, max: 48, unit: 'px', automaticLabel: 'Automatic (the block’s)', group: _imageLook),
    const ChoiceFieldSpec('borderWidth', 'Border', options: ['auto', '0', '1', '2', '4'], initial: 'auto', omitDefault: true, group: _imageLook, optionLabels: {
      'auto': 'Automatic (the block’s)',
      '0': 'None',
      '1': '1 px',
      '2': '2 px',
      '4': '4 px',
    }),
    const ColorFieldSpec('borderColor', 'Border colour', automaticLabel: 'the block’s border colour', omitDefault: true, group: _imageLook),
    const ColorFieldSpec('overlayColor', 'Overlay colour', automaticLabel: 'the block’s overlay', omitDefault: true, group: _imageLook),
    const NumberFieldSpec('overlayOpacity', 'Overlay strength', min: 0, max: 90, unit: '%', automaticLabel: 'Automatic (the block’s)', group: _imageLook),
    const ChoiceFieldSpec('hover', 'On hover', options: ['auto', 'none', 'zoom', 'lift', 'dim'], initial: 'auto', omitDefault: true, group: _imageLook, optionLabels: _hoverLabels),
    const ChoiceFieldSpec('shadow', 'Shadow', options: ['auto', 'none', 'soft', 'strong'], initial: 'auto', omitDefault: true, group: _imageLook, optionLabels: _shadowLabels),
    const ToggleFieldSpec('visible', 'Show this image', initial: true, omitDefault: true, group: _imageScreens),
    for (final s in screens) ToggleFieldSpec(hideKey(s), 'Hide on ${screenNames[s]}', omitDefault: true, group: _imageScreens),
    for (final s in screens)
      NumberFieldSpec(keyFor(s, 'order'), 'Position on ${screenNames[s]} (1 = first)', min: 1, max: maxImages, automaticLabel: s == 'desktop' ? 'Automatic (the order above)' : 'Automatic (as on desktop)', group: _imageScreens),
    for (final s in screens) ...[
      ChoiceFieldSpec(keyFor(s, 'colSpan'), 'Columns wide on ${screenNames[s]}', options: spans, initial: 'auto', omitDefault: true, group: _imageSpans, optionLabels: const {'auto': 'Automatic'}),
      ChoiceFieldSpec(keyFor(s, 'rowSpan'), 'Rows tall on ${screenNames[s]}', options: spans, initial: 'auto', omitDefault: true, group: _imageSpans, optionLabels: const {'auto': 'Automatic'}),
    ],
  ];

  static const _hoverLabels = {
    'auto': 'Automatic (the block’s)',
    'none': 'Nothing',
    'zoom': 'Zoom in slightly',
    'lift': 'Lift',
    'dim': 'Darken slightly',
  };
  static const _shadowLabels = {
    'auto': 'Automatic (the block’s)',
    'none': 'None',
    'soft': 'Soft',
    'strong': 'Strong',
  };

  static const _look = 'Image appearance (every image)';
  static const _captions = 'Captions';
  static const _spacing = 'Size and spacing';
  static const _viewing = 'Larger view';

  static final List<FieldSpec> fields = [
    const TextFieldSpec('heading', 'Heading', maxLength: 120, translationRequired: true, omitDefault: true),
    const TextFieldSpec('description', 'Description', maxLength: 600, multiline: true, omitDefault: true),
    ItemsFieldSpec('images', 'Images', itemLabel: 'Image', minItems: 1, maxItems: maxImages, itemFields: itemFields, badge: _badge),
    for (final s in screens) ..._screenFields(s),
    const ChoiceFieldSpec('fit', 'Fit', options: ['cover', 'contain'], initial: 'cover', omitDefault: true, group: _look, optionLabels: {
      'cover': 'Cover (fill the shape, cropping the edges)',
      'contain': 'Contain (the whole image)',
    }),
    const NumberFieldSpec('focalX', 'Focus across (0 = left, 100 = right)', min: 0, max: 100, unit: '%', automaticLabel: 'Automatic (each image’s, from the Media library)', group: _look),
    const NumberFieldSpec('focalY', 'Focus down (0 = top, 100 = bottom)', min: 0, max: 100, unit: '%', automaticLabel: 'Automatic (each image’s, from the Media library)', group: _look),
    const NumberFieldSpec('radius', 'Corner radius', min: 0, max: 48, unit: 'px', automaticLabel: 'Automatic (16 px)', group: _look),
    const ChoiceFieldSpec('borderWidth', 'Border', options: ['0', '1', '2', '4'], initial: '0', omitDefault: true, group: _look, optionLabels: {'0': 'None', '1': '1 px', '2': '2 px', '4': '4 px'}),
    const ColorFieldSpec('borderColor', 'Border colour', automaticLabel: 'the site’s line colour', omitDefault: true, group: _look),
    const ColorFieldSpec('overlayColor', 'Overlay colour', automaticLabel: 'no overlay', omitDefault: true, group: _look),
    const NumberFieldSpec('overlayOpacity', 'Overlay strength', min: 0, max: 90, unit: '%', automaticLabel: 'Automatic (30% with a colour)', group: _look),
    const ChoiceFieldSpec('hover', 'On hover', options: ['none', 'zoom', 'lift', 'dim'], initial: 'none', omitDefault: true, group: _look, optionLabels: {
      'none': 'Nothing',
      'zoom': 'Zoom in slightly',
      'lift': 'Lift',
      'dim': 'Darken slightly',
    }),
    const ChoiceFieldSpec('shadow', 'Shadow', options: ['none', 'soft', 'strong'], initial: 'none', omitDefault: true, group: _look, optionLabels: {'none': 'None', 'soft': 'Soft', 'strong': 'Strong'}),
    const ToggleFieldSpec('showCaptions', 'Show captions', initial: true, omitDefault: true, group: _captions),
    const ChoiceFieldSpec('captionPlacement', 'Caption placement', options: ['below', 'overlay'], initial: 'below', omitDefault: true, group: _captions, optionLabels: {
      'below': 'Below the image',
      'overlay': 'Over the image',
    }),
    const ChoiceFieldSpec('captionAlign', 'Caption alignment', options: ['start', 'center', 'end'], initial: 'start', omitDefault: true, group: _captions, optionLabels: {
      'start': 'Left',
      'center': 'Centre',
      'end': 'Right',
    }),
    const NumberFieldSpec('captionSize', 'Caption size', min: 11, max: 24, unit: 'px', automaticLabel: 'Automatic (14 px)', group: _captions),
    const ChoiceFieldSpec('captionWeight', 'Caption weight', options: ['normal', 'medium', 'bold'], initial: 'normal', omitDefault: true, group: _captions, optionLabels: {
      'normal': 'Regular',
      'medium': 'Medium',
      'bold': 'Bold',
    }),
    const ChoiceFieldSpec('captionStyle', 'Caption style', options: ['normal', 'italic'], initial: 'normal', omitDefault: true, group: _captions, optionLabels: {'normal': 'Upright', 'italic': 'Italic'}),
    const ColorFieldSpec('captionColor', 'Caption colour', automaticLabel: 'the text colour (white over an image)', omitDefault: true, group: _captions),
    const ColorFieldSpec('captionBackground', 'Caption background (over an image)', automaticLabel: 'a dark shade', omitDefault: true, group: _captions),
    const NumberFieldSpec('maxWidth', 'Maximum width', min: 320, max: 1600, unit: 'px', automaticLabel: 'Automatic (the content width)', group: _spacing),
    const NumberFieldSpec('gap', 'Image gap', min: 0, max: 96, unit: 'px', automaticLabel: 'Automatic (20 px desktop, 16 tablets, 12 phones)', group: _spacing),
    const ChoiceFieldSpec('align', 'Alignment', options: ['start', 'center', 'end'], initial: 'center', omitDefault: true, group: _spacing, optionLabels: {
      'start': 'Left',
      'center': 'Centre',
      'end': 'Right',
    }),
    const NumberFieldSpec('paddingTop', 'Space at the top', min: 0, max: 160, unit: 'px', automaticLabel: 'Automatic (none)', group: _spacing),
    const NumberFieldSpec('paddingBottom', 'Space at the bottom', min: 0, max: 160, unit: 'px', automaticLabel: 'Automatic (none)', group: _spacing),
    const NumberFieldSpec('backgroundPadding', 'Padding inside the background colour', min: 0, max: 96, unit: 'px', automaticLabel: 'Automatic (32 px, 20 on phones)', group: _spacing),
    const ToggleFieldSpec('lightbox', 'Clicking an image opens a larger view', initial: true, omitDefault: true, group: _viewing),
  ];

  /// What can't be saved: two feature images, custom widths and shapes not
  /// filled in (or not a ratio), and a "follow the link" with no link.
  static List<String> problems(StructuredBlock block) {
    final out = <String>[];
    final items = block.items('images');
    if (items.where((i) => i.value<bool>('feature') == true).length > 1) out.add('only one image can be the feature image');
    String ratioProblem(String where) => '$where: enter a shape as width:height, such as 7:5 (from 4:1 to 1:4)';
    for (final s in screens) {
      final where = 'Layout on ${screenNames[s]}';
      if (block.string(keyFor(s, 'featureWidth')) == 'custom' && _int(block, keyFor(s, 'featureWidthCustom')) == null) {
        out.add('$where: enter the custom feature width');
      }
      for (final which in ['feature', 'supporting']) {
        if (block.string(keyFor(s, '${which}Aspect')) == 'custom' && parseRatio(block.text(keyFor(s, '${which}AspectCustom')).en) == null) {
          out.add(ratioProblem('$where, $which image shape'));
        }
      }
    }
    for (final (i, item) in items.indexed) {
      final where = 'Image ${i + 1}';
      if (item.string('aspect') == 'custom' && parseRatio(item.text('aspectCustom').en) == null) out.add(ratioProblem(where));
      if (item.string('action') == 'link' && item.string('target').trim().isEmpty) out.add('$where: enter the link to follow, or choose another click action');
    }
    return out;
  }

  // ---------------------------------------------------------- settings

  /// The settings in effect on [screen] (Automatic resolved).
  static AsymmetricSettings settings(StructuredBlock block, String screen) {
    String opt(String s, String name) => block.string(keyFor(s, name));
    final desktop = _resolve(block, 'desktop', null, opt);
    if (screen == 'desktop') return desktop;
    return _resolve(block, screen, desktop, opt);
  }

  static AsymmetricSettings _resolve(StructuredBlock block, String screen, AsymmetricSettings? desktop, String Function(String, String) opt) {
    String own(String name) => opt(screen, name);
    final mobile = screen == 'mobile';
    // Phones: a feature on top and the rest two by two, unless the desktop
    // composition is already a grid (then the same, in two columns).
    final arrangement = switch (own('arrangement')) {
      'auto' || '' => switch (screen) {
          'desktop' => 'editorial',
          'tablet' => desktop!.arrangement,
          _ => desktop!.arrangement == 'mosaic' || desktop.arrangement == 'staggered' || desktop.arrangement == 'custom' ? desktop.arrangement : 'feature',
        },
      final a => a,
    };
    final position = switch (own('featurePosition')) {
      'auto' || '' => mobile ? 'top' : desktop?.position ?? 'left',
      final p => p,
    };
    final widthOption = own('featureWidth');
    final fraction = switch (widthOption) {
      'custom' => (_int(block, keyFor(screen, 'featureWidthCustom')) ?? 60) / 100,
      'auto' || '' => desktop != null && opt('desktop', 'featureWidth') != 'auto' ? desktop.featureFraction : (arrangement == 'editorial' ? 0.6 : 0.55),
      final w => (int.tryParse(w) ?? 60) / 100,
    };
    double? shape(String which) {
      final option = own('${which}Aspect');
      if (option == 'auto' || option.isEmpty) {
        return desktop == null ? null : (which == 'feature' ? desktop.featureRatio : desktop.supportingRatio);
      }
      return ratioOf(option, block.text(keyFor(screen, '${which}AspectCustom')).en);
    }

    final columnsOption = int.tryParse(own('columns'));
    final columns = columnsOption ??
        switch ((screen, arrangement)) {
          ('mobile', _) => 2,
          ('tablet', 'mosaic') => 3,
          ('tablet', 'custom') => 4,
          ('tablet', _) => 2,
          (_, 'mosaic') => 4,
          (_, 'custom') => 6,
          _ => 3,
        };
    final gap = (_int(block, 'gap') ?? switch (screen) { 'desktop' => 20, 'tablet' => 16, _ => 12 }).toDouble();
    return AsymmetricSettings(
      screen: screen,
      arrangement: arrangement,
      position: position,
      featureFraction: fraction.clamp(0.25, 0.8),
      featureHeight: _int(block, keyFor(screen, 'featureHeight'))?.toDouble() ?? (desktop != null && !mobile ? desktop.featureHeight : null),
      featureRatio: shape('feature'),
      supportingRatio: shape('supporting'),
      supportingLayout: switch (own('supportingLayout')) {
        'auto' || '' => mobile && arrangement == 'feature' ? 'grid' : desktop?.supportingLayout ?? 'auto',
        final l => l,
      },
      columns: columns,
      gapX: _int(block, keyFor(screen, 'gapX'))?.toDouble() ?? gap,
      gapY: _int(block, keyFor(screen, 'gapY'))?.toDouble() ?? gap,
    );
  }

  /// [item]'s position on [screen] (its own, else desktop's, else [index]).
  static int orderOf(BlockItem item, String screen, int index) =>
      item.value<int>(keyFor(screen, 'order')) ?? (screen == 'desktop' ? null : item.value<int>('order')) ?? index + 1;

  /// Whether [item] is shown on [screen].
  static bool shownOn(BlockItem item, String screen) => item.value<bool>('visible') != false && item.value<bool>(hideKey(screen)) != true;

  /// The key of "Hide on [screen]" (`hideDesktop`, `hideTablet`, `hideMobile`).
  static String hideKey(String screen) => 'hide${screen[0].toUpperCase()}${screen.substring(1)}';

  /// [item]'s span ('colSpan' or 'rowSpan') on [screen], or null
  /// (Automatic: its own on a bigger screen, else the layout's).
  static int? spanOf(BlockItem item, String screen, String name) {
    for (final s in screens.take(screens.indexOf(screen) + 1).toList().reversed) {
      if (int.tryParse(item.string(keyFor(s, name))) case final n?) return n;
    }
    return null;
  }

}

/// The resolved layout settings for one screen size.
@immutable
class AsymmetricSettings {
  const AsymmetricSettings({
    required this.screen,
    required this.arrangement,
    required this.position,
    required this.featureFraction,
    required this.featureHeight,
    required this.featureRatio,
    required this.supportingRatio,
    required this.supportingLayout,
    required this.columns,
    required this.gapX,
    required this.gapY,
  });

  final String screen;
  final String arrangement;
  final String position;

  /// The feature image's share of the width beside the others.
  final double featureFraction;
  final double? featureHeight;

  /// Shapes (width / height); null: each photograph's own.
  final double? featureRatio;
  final double? supportingRatio;
  final String supportingLayout;
  final int columns;
  final double gapX;
  final double gapY;

  bool get beside => position == 'left' || position == 'right';
}

/// One image to place.
@immutable
class AsymmetricTile {
  const AsymmetricTile({required this.id, required this.naturalRatio, this.ratio, this.feature = false, this.weight = 1, this.colSpan, this.rowSpan});

  final String id;

  /// The photograph's own shape (width / height).
  final double naturalRatio;

  /// Its own shape, if set (else the layout's, else [naturalRatio]).
  final double? ratio;
  final bool feature;

  /// Relative size (1–3) beside the other supporting images.
  final int weight;
  final int? colSpan;
  final int? rowSpan;
}

/// A placed image.
@immutable
class AsymmetricPlacement {
  const AsymmetricPlacement(this.id, this.rect);

  final String id;
  final Rect rect;

  @override
  String toString() => '$id $rect';
}

/// Where each image goes, in reading order, and the composition's height.
@immutable
class AsymmetricLayoutResult {
  const AsymmetricLayoutResult(this.placements, this.height);

  final List<AsymmetricPlacement> placements;
  final double height;

  Rect rectOf(String id) => placements.firstWhere((p) => p.id == id).rect;
}

/// The layout engine: [tiles] (in order; at most one feature) laid out in
/// [width] by [settings]. Every rectangle is within 0..[width]. [extraBelow]
/// is the room a tile needs under its image (a caption), added where tiles
/// keep their own height (staggered); elsewhere the caption shares the
/// tile's rectangle.
abstract final class AsymmetricLayout {
  static AsymmetricLayoutResult compute(List<AsymmetricTile> tiles, AsymmetricSettings settings, double width, {double Function(AsymmetricTile tile, double width)? extraBelow}) {
    final w = width.isFinite && width > 0 ? width.floorToDouble() : 0.0;
    if (tiles.isEmpty || w == 0) return const AsymmetricLayoutResult([], 0);
    final placed = switch (settings.arrangement) {
      'mosaic' || 'custom' => _grid(tiles, settings, w),
      'staggered' => _staggered(tiles, settings, w, extraBelow),
      _ => _feature(tiles, settings, w, editorial: settings.arrangement == 'editorial'),
    };
    var height = 0.0;
    for (final p in placed) {
      height = math.max(height, p.rect.bottom);
    }
    placed.sort((a, b) {
      final dy = (a.rect.top - b.rect.top);
      if (dy.abs() > 0.5) return dy.sign.toInt();
      return (a.rect.left - b.rect.left).sign.toInt();
    });
    return AsymmetricLayoutResult(placed, height);
  }

  static double _clampRatio(double r) => r.clamp(1 / AsymmetricGallery.maxRatio, AsymmetricGallery.maxRatio);

  static double _ratio(AsymmetricTile t, AsymmetricSettings s) =>
      _clampRatio(t.ratio ?? (t.feature ? s.featureRatio : s.supportingRatio) ?? (t.naturalRatio > 0 ? t.naturalRatio : 4 / 3));

  /// [tiles] side by side (or one above another) filling [box], each by
  /// its weight.
  static List<AsymmetricPlacement> _line(List<AsymmetricTile> tiles, Rect box, double gap, {required bool vertical}) {
    final total = tiles.fold<int>(0, (n, t) => n + t.weight);
    final room = (vertical ? box.height : box.width) - gap * (tiles.length - 1);
    var at = vertical ? box.top : box.left;
    return [
      for (final (i, t) in tiles.indexed)
        () {
          final length = i == tiles.length - 1 ? (vertical ? box.bottom : box.right) - at : (room * t.weight / total).floorToDouble();
          final rect = vertical ? Rect.fromLTWH(box.left, at, box.width, length) : Rect.fromLTWH(at, box.top, length, box.height);
          at += length + gap;
          return AsymmetricPlacement(t.id, rect);
        }(),
    ];
  }

  /// Rows of [perRow] filling [box] (rows the same height; a last, shorter
  /// row widens to fill).
  static List<AsymmetricPlacement> _rows(List<AsymmetricTile> tiles, Rect box, double gapX, double gapY, int perRow) {
    final rows = <List<AsymmetricTile>>[];
    for (var i = 0; i < tiles.length; i += perRow) {
      rows.add(tiles.sublist(i, math.min(i + perRow, tiles.length)));
    }
    final rowHeight = ((box.height - gapY * (rows.length - 1)) / rows.length).floorToDouble();
    return [
      for (final (r, row) in rows.indexed)
        ..._line(row, Rect.fromLTWH(box.left, box.top + r * (rowHeight + gapY), box.width, r == rows.length - 1 ? box.bottom - (box.top + r * (rowHeight + gapY)) : rowHeight), gapX, vertical: false),
    ];
  }

  /// Editorial and feature compositions: the feature beside (left, right)
  /// or across (top, bottom) the supporting images.
  static List<AsymmetricPlacement> _feature(List<AsymmetricTile> tiles, AsymmetricSettings s, double w, {required bool editorial}) {
    final feature = tiles.firstWhere((t) => t.feature, orElse: () => tiles.first);
    final rest = [for (final t in tiles) if (t.id != feature.id) t];
    final gx = s.gapX, gy = s.gapY;
    if (rest.isEmpty) {
      final h = s.featureHeight ?? w / _ratio(feature, s);
      return [AsymmetricPlacement(feature.id, Rect.fromLTWH(0, 0, w, h.floorToDouble()))];
    }
    if (s.beside) {
      final fw = ((w - gx) * s.featureFraction).floorToDouble();
      final sw = w - gx - fw;
      final ratio = s.featureRatio ?? feature.ratio ?? (editorial ? _clampRatio(feature.naturalRatio).clamp(0.6, 1.25) : _ratio(feature, s));
      final h = (s.featureHeight ?? fw / ratio).clamp(120.0, 2400.0).floorToDouble();
      final fx = s.position == 'left' ? 0.0 : sw + gx;
      final box = Rect.fromLTWH(s.position == 'left' ? fw + gx : 0, 0, sw, h);
      final layout = s.supportingLayout == 'auto' ? (editorial && rest.length >= 3 ? 'staggered' : (rest.length > 3 ? 'grid' : 'column')) : s.supportingLayout;
      final support = switch (layout) {
        'staggered' => _staggeredBox(rest, box, gx, gy),
        'grid' => _rows(rest, box, gx, gy, rest.length == 1 ? 1 : 2),
        'row' => _line(rest, box, gx, vertical: false),
        _ => _line(rest, box, gy, vertical: true),
      };
      return [AsymmetricPlacement(feature.id, Rect.fromLTWH(fx, 0, fw, h)), ...support];
    }
    // Across: the feature full width, the rest in rows above or below.
    final fh = (s.featureHeight ?? w / _ratio(feature, s)).clamp(80.0, w * 1.5).floorToDouble();
    final perRow = switch (s.supportingLayout) {
      'column' => 1,
      'grid' => 2,
      'row' => math.min(rest.length, 4),
      _ => editorial ? math.min(rest.length, 3) : math.min(rest.length, s.screen == 'mobile' ? 2 : 4),
    };
    final rowsCount = (rest.length / perRow).ceil();
    final tileW = (w - gx * (perRow - 1)) / perRow;
    final shapes = rest.map((t) => _ratio(t, s)).toList();
    final avg = shapes.reduce((a, b) => a + b) / shapes.length;
    final rowH = (tileW / avg).floorToDouble();
    final offset = editorial && perRow > 1 ? (rowH * 0.12).floorToDouble() : 0.0;
    final stripH = rowsCount * (rowH + offset) + gy * (rowsCount - 1);
    final top = s.position == 'top';
    final stripTop = top ? fh + gy : 0.0;
    final strip = _rows(rest, Rect.fromLTWH(0, stripTop, w, stripH), gx, gy, perRow);
    // Editorial: every other image a little lower.
    final shifted = [
      for (final (i, p) in strip.indexed)
        offset == 0
            ? p
            : AsymmetricPlacement(p.id, Rect.fromLTWH(p.rect.left, p.rect.top + ((i % perRow).isOdd ? offset : 0), p.rect.width, p.rect.height - offset)),
    ];
    return [AsymmetricPlacement(feature.id, Rect.fromLTWH(0, top ? 0 : stripH + gy, w, fh)), ...shifted];
  }

  /// Two columns in [box], the second set a little lower (editorial).
  static List<AsymmetricPlacement> _staggeredBox(List<AsymmetricTile> tiles, Rect box, double gx, double gy) {
    final colW = ((box.width - gx) / 2).floorToDouble();
    final offset = (box.height * 0.12).floorToDouble();
    final a = [for (final (i, t) in tiles.indexed) if (i.isEven) t];
    final b = [for (final (i, t) in tiles.indexed) if (i.isOdd) t];
    return [
      ..._line(a, Rect.fromLTWH(box.left, box.top, colW, box.height - offset), gy, vertical: true),
      ..._line(b, Rect.fromLTWH(box.left + colW + gx, box.top + offset, box.width - colW - gx, box.height - offset), gy, vertical: true),
    ];
  }

  /// Mosaic and custom: a grid of [AsymmetricSettings.columns] square-ish
  /// cells, each image spanning cells, packed in order into the first
  /// place it fits.
  static List<AsymmetricPlacement> _grid(List<AsymmetricTile> tiles, AsymmetricSettings s, double w) {
    final cols = s.columns.clamp(1, 6);
    final gx = s.gapX, gy = s.gapY;
    final cw = (w - gx * (cols - 1)) / cols;
    final rh = (cw / (s.supportingRatio ?? 1.0)).floorToDouble();
    final custom = s.arrangement == 'custom';
    (int, int) spanOf(AsymmetricTile t) {
      int c, r;
      if (t.feature) {
        if (!s.beside) {
          c = cols;
          r = 2;
        } else {
          c = custom ? (cols * 0.6).ceil() : 2;
          r = 2;
        }
      } else if (custom) {
        c = cols >= 4 ? 2 : 1;
        r = 1;
      } else {
        c = t.weight >= 2 ? 2 : 1;
        r = t.weight >= 3 ? 2 : 1;
      }
      if (custom || t.feature) {
        c = t.colSpan ?? c;
        r = t.rowSpan ?? r;
      }
      return (c.clamp(1, cols), r.clamp(1, 6));
    }

    final feature = tiles.where((t) => t.feature).firstOrNull;
    final ordered = [
      if (feature != null && s.position != 'bottom') feature,
      for (final t in tiles) if (!identical(t, feature)) t,
      if (feature != null && s.position == 'bottom') feature,
    ];
    final taken = <List<bool>>[];
    bool free(int row, int col, int c, int r) {
      for (var y = row; y < row + r; y++) {
        while (taken.length <= y) {
          taken.add(List.filled(cols, false));
        }
        for (var x = col; x < col + c; x++) {
          if (taken[y][x]) return false;
        }
      }
      return true;
    }

    final out = <AsymmetricPlacement>[];
    for (final t in ordered) {
      final (c, r) = spanOf(t);
      var placed = false;
      for (var row = 0; !placed; row++) {
        // A feature on the right starts at the right edge; at the bottom,
        // below everything else.
        final firstRow = identical(t, feature) && s.position == 'bottom' ? taken.length : 0;
        if (row < firstRow) continue;
        final starts = identical(t, feature) && s.position == 'right' ? [cols - c] : [for (var col = 0; col <= cols - c; col++) col];
        for (final col in starts) {
          if (free(row, col, c, r)) {
            for (var y = row; y < row + r; y++) {
              for (var x = col; x < col + c; x++) {
                taken[y][x] = true;
              }
            }
            out.add(AsymmetricPlacement(
              t.id,
              Rect.fromLTWH((col * (cw + gx)).floorToDouble(), row * (rh + gy), (c * cw + (c - 1) * gx).floorToDouble(), r * rh + (r - 1) * gy),
            ));
            placed = true;
            break;
          }
        }
      }
    }
    return out;
  }

  /// Staggered: columns, each image keeping its own shape, placed in the
  /// shortest column; every other column starts a little lower. The feature
  /// spans two columns (all of them at the top or bottom).
  static List<AsymmetricPlacement> _staggered(List<AsymmetricTile> tiles, AsymmetricSettings s, double w, double Function(AsymmetricTile, double)? extraBelow) {
    final cols = s.columns.clamp(1, 6);
    final gx = s.gapX, gy = s.gapY;
    final cw = (w - gx * (cols - 1)) / cols;
    final heights = [for (var i = 0; i < cols; i++) i.isOdd ? (cw * 0.2).floorToDouble() : 0.0];
    final feature = tiles.where((t) => t.feature).firstOrNull;
    final ordered = [
      if (feature != null && s.position != 'bottom') feature,
      for (final t in tiles) if (!identical(t, feature)) t,
      if (feature != null && s.position == 'bottom') feature,
    ];
    final out = <AsymmetricPlacement>[];
    for (final t in ordered) {
      final isFeature = identical(t, feature);
      final span = isFeature ? (s.beside ? math.min(cols, cols >= 3 ? 2 : cols) : cols) : 1;
      final starts = isFeature && s.position == 'left'
          ? [0]
          : isFeature && s.position == 'right'
              ? [cols - span]
              : [for (var c = 0; c <= cols - span; c++) c];
      var best = starts.first;
      double top(int c) => heights.sublist(c, c + span).reduce(math.max);
      for (final c in starts) {
        if (top(c) < top(best) - 0.5) best = c;
      }
      // A bottom feature goes under everything.
      final y = isFeature && s.position == 'bottom' ? heights.reduce(math.max) : top(best);
      final tw = (span * cw + (span - 1) * gx).floorToDouble();
      final h = (tw / _ratio(t, s)).floorToDouble() + (extraBelow?.call(t, tw) ?? 0);
      out.add(AsymmetricPlacement(t.id, Rect.fromLTWH((best * (cw + gx)).floorToDouble(), y, tw, h)));
      for (var c = best; c < best + span; c++) {
        heights[c] = y + h + gy;
      }
    }
    return out;
  }
}
