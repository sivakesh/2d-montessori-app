import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../public_website/content/website_custom_page.dart';
import '../../../public_website/content/website_design.dart';
import '../../../public_website/content/website_page_style.dart';
import '../../../public_website/content/website_site_style.dart';
import 'page_builder/website_color_field.dart';
import 'page_builder/website_size_field.dart';
import 'website_content_editors.dart';

/// The site design: the palette (the site's own colours, renamed and
/// changed as needed, plus any added — each a name and a `#RRGGBB`) and
/// the typography. Pages, header and footer that use a palette colour
/// follow it; colours set as a custom `#RRGGBB` on an element stay as
/// they are.
///
/// Keys: `website-design-color-<id>-name`, `-hex`, `-remove`;
/// `website-design-add-color`, `website-design-reset`; typography
/// ([WebsiteSizeField]): `website-design-title-size`,
/// `-title-size-mobile`, `-heading-size`, `-body-size`, `-nav-size`,
/// `-button-size`; `website-design-line-height`.
class WebsiteDesignEditor extends StatelessWidget {
  const WebsiteDesignEditor({super.key, required this.design, required this.onChanged});

  final SiteDesign design;
  final ValueChanged<SiteDesign> onChanged;

  void _setColor(int i, DesignColor color) => onChanged(design.copyWith(palette: [...design.palette]..[i] = color));

  Widget _sizes(String key, String label, List<double> options, double value, ValueChanged<double> onPick, {String Function(double)? text}) => SizedBox(
        width: 220,
        child: DropdownButtonFormField<double>(
          key: Key(key),
          initialValue: options.contains(value) ? value : null,
          isExpanded: true,
          decoration: websiteField(label),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(text?.call(o) ?? '${o.round()} px', key: Key('$key-$o')))],
          onChanged: (v) {
            if (v != null) onPick(v);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Palette colours are used across the site (headings, text, buttons, backgrounds, header and footer). Change a colour here and everything '
          'using it changes. A colour set as a custom #RRGGBB on a single element stays as it is.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        for (final (i, c) in design.palette.indexed)
          Padding(
            key: Key('website-design-color-${c.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: SiteDesign.parseHex(c.hex) ?? Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key: Key('website-design-color-${c.id}-name'),
                    initialValue: c.name,
                    maxLength: SiteDesign.maxNameLength,
                    decoration: websiteField(SiteDesign.builtInIds.contains(c.id) ? 'Name (site colour)' : 'Name'),
                    onChanged: (v) => _setColor(i, c.copyWith(name: v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: Key('website-design-color-${c.id}-hex'),
                    initialValue: c.hex,
                    maxLength: 7,
                    decoration: websiteField('HEX').copyWith(errorText: SiteDesign.isHex(c.hex) ? null : '#RRGGBB'),
                    onChanged: (v) => _setColor(i, c.copyWith(hex: v.trim().toUpperCase())),
                  ),
                ),
                if (SiteDesign.builtInIds.contains(c.id))
                  const SizedBox(width: 48)
                else
                  IconButton(
                    key: Key('website-design-color-${c.id}-remove'),
                    tooltip: 'Remove this colour (anything using it goes back to its default)',
                    onPressed: () => onChanged(design.copyWith(palette: [...design.palette]..removeAt(i))),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('website-design-add-color'),
              onPressed: design.palette.length >= SiteDesign.maxColors
                  ? null
                  : () => onChanged(design.copyWith(palette: [...design.palette, DesignColor(id: SiteDesign.newColorId(), name: 'New colour', hex: '#888888')])),
              icon: const Icon(Icons.add),
              label: const Text('Add a colour'),
            ),
            TextButton.icon(
              key: const Key('website-design-reset'),
              onPressed: design.isDefault ? null : () => onChanged(SiteDesign.defaults),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Back to the site’s own design'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Type', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _sizes('website-design-line-height', 'Line height', SiteDesign.lineHeights, design.lineHeight, (v) => onChanged(design.copyWith(lineHeight: v)), text: (v) => v.toStringAsFixed(1)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Sizes for the whole website, in pixels. A block can set its own heading or text size, which then takes the place of these.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        ..._typography(),
      ],
    );
  }
}

extension on WebsiteDesignEditor {
  /// One size control: [value] null is "the site's own" ([range]'s
  /// standard size).
  Widget _size(String key, String label, FontSizeRange range, double? value, ValueChanged<double?> onPick) => WebsiteSizeField(
        fieldKey: 'website-design-$key',
        label: label,
        range: range,
        value: value,
        inheritedValue: range.standard,
        inheritedFrom: 'the site’s own size',
        onChanged: onPick,
      );

  List<Widget> _typography() {
    // Body and heading sizes are always stored; their standard size is
    // shown as "not set".
    double? own(double v, FontSizeRange r) => v == r.standard ? null : v;
    return [
      _size('title-size', 'Page titles and hero headings', SiteDesign.titleRange, design.titleSize, (v) => onChanged(design.copyWith(titleSize: () => v))),
      _size('title-size-mobile', 'Page titles on phones', SiteDesign.titleMobileRange, design.titleSizeMobile, (v) => onChanged(design.copyWith(titleSizeMobile: () => v))),
      _size('heading-size', 'Section headings', SiteDesign.headingRange, own(design.headingSize, SiteDesign.headingRange),
          (v) => onChanged(design.copyWith(headingSize: v ?? SiteDesign.headingRange.standard))),
      _size('body-size', 'Body text and descriptions', SiteDesign.bodyRange, own(design.bodySize, SiteDesign.bodyRange),
          (v) => onChanged(design.copyWith(bodySize: v ?? SiteDesign.bodyRange.standard))),
      _size('nav-size', 'Header navigation', SiteDesign.navRange, design.navSize, (v) => onChanged(design.copyWith(navSize: () => v))),
      _size('button-size', 'Buttons', SiteDesign.buttonRange, design.buttonSize, (v) => onChanged(design.copyWith(buttonSize: () => v))),
    ];
  }
}

Widget _choice(String key, String label, Map<String, String> options, String value, ValueChanged<String> onChanged) => SizedBox(
      width: 240,
      child: DropdownButtonFormField<String>(
        key: Key(key),
        initialValue: options.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: websiteField(label),
        items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, key: Key('$key-${e.key}')))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );

Widget _text(String key, String label, String initial, ValueChanged<String> onChanged, {int? maxLength, int lines = 1, String? helper, String? error}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        key: Key(key),
        initialValue: initial,
        maxLength: maxLength,
        minLines: lines,
        maxLines: lines,
        decoration: websiteField(label, helper: helper).copyWith(errorText: error),
        onChanged: onChanged,
      ),
    );

/// The header's look, shared by every page: colours, the name and logo,
/// the links' position, its height, and an optional button. Keys:
/// `website-header-<setting>`.
class WebsiteHeaderStyleEditor extends StatelessWidget {
  const WebsiteHeaderStyleEditor({super.key, required this.style, required this.design, required this.onChanged});

  final SiteHeaderStyle style;
  final SiteDesign design;
  final ValueChanged<SiteHeaderStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget color(String key, String label, String? value, SiteHeaderStyle Function(String? v) apply) =>
        WebsiteColorField(fieldKey: 'website-header-$key', label: label, value: value, design: design, inheritedLabel: 'the site’s own header', onChanged: (v) => onChanged(apply(v)));
    final target = style.ctaTarget.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Top bar (language and login)', style: TextStyle(fontWeight: FontWeight.w600)),
        const Text('The slim bar above the header. On phones, login and logout move to the menu.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        color('utility-background', 'Top bar background', style.utilityBackground, (v) => style.copyWith(utilityBackground: () => v)),
        color('utility-text-color', 'Top bar text and icons', style.utilityTextColor, (v) => style.copyWith(utilityTextColor: () => v)),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _choice('website-header-utility-align', 'Top bar alignment', const {'start': 'Left', 'center': 'Centred', 'end': 'Right'}, style.utilityAlign,
                (v) => onChanged(style.copyWith(utilityAlign: v))),
            _choice('website-header-utility-vertical-align', 'Vertical alignment', const {'top': 'Top', 'center': 'Middle', 'bottom': 'Bottom'}, style.utilityVerticalAlign,
                (v) => onChanged(style.copyWith(utilityVerticalAlign: v))),
          ],
        ),
        const SizedBox(height: 8),
        for (final (key, label, range, value, apply) in <(String, String, FontSizeRange, double?, SiteHeaderStyle Function(double?))>[
          ('utility-font-size', 'Top bar text size', SiteHeaderStyle.utilityFontRange, style.utilityFontSize, (v) => style.copyWith(utilityFontSize: () => v)),
          ('utility-padding-y', 'Top bar padding (top and bottom)', SiteHeaderStyle.utilityPaddingYRange, style.utilityPaddingY, (v) => style.copyWith(utilityPaddingY: () => v)),
          ('utility-padding-x', 'Top bar padding (sides)', SiteHeaderStyle.utilityPaddingXRange, style.utilityPaddingX, (v) => style.copyWith(utilityPaddingX: () => v)),
          ('utility-spacing', 'Space between controls', SiteHeaderStyle.utilitySpacingRange, style.utilitySpacing, (v) => style.copyWith(utilitySpacing: () => v)),
        ])
          WebsiteSizeField(
            fieldKey: 'website-header-$key',
            label: label,
            range: range,
            value: value,
            inheritedValue: range.standard,
            inheritedFrom: 'the site’s own',
            onChanged: (v) => onChanged(apply(v)),
          ),
        const SizedBox(height: 4),
        const Text('Header bar (site name and links)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        color('background', 'Background', style.background, (v) => style.copyWith(background: () => v)),
        color('brand-color', 'Site name', style.brandColor, (v) => style.copyWith(brandColor: () => v)),
        color('link-color', 'Links', style.linkColor, (v) => style.copyWith(linkColor: () => v)),
        color('accent-color', 'Current page underline', style.accentColor, (v) => style.copyWith(accentColor: () => v)),
        SwitchListTile(
          key: const Key('website-header-show-logo'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show the logo next to the site name'),
          value: style.showLogo,
          onChanged: (v) => onChanged(style.copyWith(showLogo: v)),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _choice('website-header-nav-align', 'Links on wide screens', const {'end': 'After the site name', 'center': 'Centred'}, style.navAlign, (v) => onChanged(style.copyWith(navAlign: v))),
            _choice('website-header-height', 'Header height', const {'compact': 'Compact', 'normal': 'Standard', 'spacious': 'Spacious'}, style.height, (v) => onChanged(style.copyWith(height: v))),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Header button (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
        const Text('Shown at the end of the header on wide screens, and in the mobile menu.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        _text('website-header-cta-label-en', 'Button label (English)', style.ctaLabel.en, (v) => onChanged(style.copyWith(ctaLabel: style.ctaLabel.copyWith(en: v))), maxLength: SiteHeaderStyle.maxCtaLabelLength),
        if (multilingualEditing)
          _text('website-header-cta-label-ta', 'Button label (Tamil)', style.ctaLabel.ta, (v) => onChanged(style.copyWith(ctaLabel: style.ctaLabel.copyWith(ta: v))),
            maxLength: SiteHeaderStyle.maxCtaLabelLength, helper: 'If left blank, Tamil visitors see the English.'),
        _text(
          'website-header-cta-target',
          'Button link',
          style.ctaTarget,
          (v) => onChanged(style.copyWith(ctaTarget: v)),
          helper: 'A page of this website (/admissions, /pages/open-day), an https:// link, mailto: or tel:.',
          error: target.isEmpty ? null : SafeLinkTarget.validate(target),
        ),
        color('cta-background', 'Button colour', style.ctaBackground, (v) => style.copyWith(ctaBackground: () => v)),
        color('cta-text-color', 'Button text colour', style.ctaTextColor, (v) => style.copyWith(ctaTextColor: () => v)),
      ],
    );
  }
}

/// The footer's look, shared by every page, and the school's contact
/// details shown in it. Keys: `website-footer-<setting>`.
class WebsiteFooterStyleEditor extends StatelessWidget {
  const WebsiteFooterStyleEditor({super.key, required this.style, required this.design, required this.onChanged});

  final SiteFooterStyle style;
  final SiteDesign design;
  final ValueChanged<SiteFooterStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget color(String key, String label, String? value, SiteFooterStyle Function(String? v) apply) =>
        WebsiteColorField(fieldKey: 'website-footer-$key', label: label, value: value, design: design, inheritedLabel: 'the site’s own footer', onChanged: (v) => onChanged(apply(v)));
    final errors = style.validationErrors();
    String? errorFor(String word) {
      for (final e in errors) {
        if (e.toLowerCase().contains(word)) return e;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        color('background', 'Background', style.background, (v) => style.copyWith(background: () => v)),
        color('heading-color', 'Site name', style.headingColor, (v) => style.copyWith(headingColor: () => v)),
        color('text-color', 'Text', style.textColor, (v) => style.copyWith(textColor: () => v)),
        color('link-color', 'Links', style.linkColor, (v) => style.copyWith(linkColor: () => v)),
        _choice('website-footer-align', 'Alignment', const {'start': 'Left', 'center': 'Centred'}, style.align, (v) => onChanged(style.copyWith(align: v))),
        const SizedBox(height: 12),
        const Text('Contact details (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
        const Text('Shown in the footer of every page; the phone number and email can be tapped.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        _text('website-footer-address-en', 'Address (English)', style.address.en, (v) => onChanged(style.copyWith(address: style.address.copyWith(en: v))),
            maxLength: SiteFooterStyle.maxAddressLength, lines: 2),
        if (multilingualEditing)
          _text('website-footer-address-ta', 'Address (Tamil)', style.address.ta, (v) => onChanged(style.copyWith(address: style.address.copyWith(ta: v))),
            maxLength: SiteFooterStyle.maxAddressLength, lines: 2, helper: 'If left blank, Tamil visitors see the English.'),
        _text('website-footer-phone', 'Phone', style.phone, (v) => onChanged(style.copyWith(phone: v)), error: style.phone.trim().isEmpty ? null : errorFor('phone')),
        _text('website-footer-email', 'Email', style.email, (v) => onChanged(style.copyWith(email: v)), error: style.email.trim().isEmpty ? null : errorFor('email')),
      ],
    );
  }
}

/// A page's own background ([PageStyle.background]): the palette, a custom
/// `#RRGGBB` or the site's own, behind the page's content only (the
/// header, top bar, footer and sections keep theirs). Shown at once on the
/// canvas; saved and published with the page. Key:
/// `website-page-background` ([WebsiteColorField]).
class WebsitePageBackgroundField extends StatelessWidget {
  const WebsitePageBackgroundField({super.key, required this.style, required this.design, required this.onChanged});

  final PageStyle style;
  final SiteDesign design;
  final ValueChanged<PageStyle> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WebsiteColorField(
            fieldKey: 'website-page-background',
            label: 'Page background',
            value: style.background,
            design: design,
            inheritedLabel: 'the site’s own page background',
            onChanged: (v) => onChanged(style.copyWith(background: () => v)),
          ),
          const Text(
            'Behind this page’s content only. The header, top bar, footer and sections with their own background keep theirs.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      );
}
