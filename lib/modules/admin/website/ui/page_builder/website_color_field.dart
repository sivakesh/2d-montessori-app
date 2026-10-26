import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/website_design.dart';
import '../website_content_editors.dart';

/// A colour setting: shows the colour in force — inherited (unset) or set
/// here — and opens a picker with the palette, any extra [legacy] values
/// (a block background's first options), a custom `#RRGGBB` and "Reset to
/// default". [onChanged] gets the new value, or null for "inherit".
///
/// Keys: `<fieldKey>` (the row), `-choose`, `-reset`; in the picker
/// `-token-<id>`, `-legacy-<value>`, `-hex`, `-hex-apply`, `-default`.
class WebsiteColorField extends StatelessWidget {
  const WebsiteColorField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.design,
    required this.onChanged,
    this.inheritedLabel = 'the site design',
    this.legacy = const {},
  });

  final String fieldKey;
  final String label;
  final String? value;
  final SiteDesign design;
  final ValueChanged<String?> onChanged;

  /// Where the colour comes from when unset (for the "Inherited" note).
  final String inheritedLabel;

  /// Extra stored values offered, by value, with their label and colour
  /// (null colour: "none").
  final Map<String, (String, Color?)> legacy;

  String get _description {
    final v = value;
    if (v == null) return 'Inherited from $inheritedLabel';
    if (legacy[v] case (final name, _)) return name;
    return design.describe(v) ?? v;
  }

  Color? get _swatch {
    final v = value;
    if (v == null) return null;
    if (legacy[v] case (_, final color)) return color;
    return design.resolve(v);
  }

  Future<void> _pick(BuildContext context) async {
    final result = await showDialog<_ColorChoice>(
      context: context,
      builder: (context) => _ColorPickerDialog(fieldKey: fieldKey, label: label, value: value, design: design, legacy: legacy),
    );
    if (result != null) onChanged(result.value);
  }

  @override
  Widget build(BuildContext context) {
    final swatch = _swatch;
    return Padding(
      key: Key(fieldKey),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Semantics(
            label: '$label: $_description',
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: swatch ?? Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: value == null ? Colors.grey.shade400 : Colors.black26, width: value == null ? 1.5 : 1),
              ),
              child: value == null ? Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey.shade500) : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  _description,
                  key: Key('$fieldKey-value'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: value == null ? AppColors.textSecondary : AppColors.primary),
                ),
              ],
            ),
          ),
          TextButton(key: Key('$fieldKey-choose'), onPressed: () => _pick(context), child: const Text('Change')),
          if (value != null)
            IconButton(key: Key('$fieldKey-reset'), tooltip: 'Reset to default', onPressed: () => onChanged(null), icon: const Icon(Icons.restart_alt, size: 20)),
        ],
      ),
    );
  }
}

class _ColorChoice {
  const _ColorChoice(this.value);

  /// Null: inherit.
  final String? value;
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.fieldKey, required this.label, required this.value, required this.design, required this.legacy});

  final String fieldKey;
  final String label;
  final String? value;
  final SiteDesign design;
  final Map<String, (String, Color?)> legacy;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late final TextEditingController _hex = TextEditingController(
    text: widget.value != null && SiteDesign.isHex(widget.value!) ? widget.value!.toUpperCase() : '#',
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  String get _hexValue {
    final raw = _hex.text.trim().toUpperCase();
    return raw.startsWith('#') ? raw : '#$raw';
  }

  Widget _swatch({required Key key, required String name, required Color? color, required bool selected, required VoidCallback onTap}) => Tooltip(
        message: name,
        child: Semantics(
          button: true,
          selected: selected,
          label: name,
          child: InkWell(
            key: key,
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color ?? Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.primary : Colors.black26, width: selected ? 3 : 1),
              ),
              child: color == null ? const Icon(Icons.block, size: 18, color: Colors.black38) : null,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final k = widget.fieldKey;
    final hexValid = SiteDesign.isHex(_hexValue);
    return AlertDialog(
      title: Text(widget.label),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Site palette', style: TextStyle(fontWeight: FontWeight.w600)),
              const Text(
                'Palette colours follow the site design: change a colour there and everything using it changes.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in widget.design.palette)
                    _swatch(
                      key: Key('$k-token-${c.id}'),
                      name: c.name,
                      color: c.color,
                      selected: widget.value == SiteDesign.token(c.id),
                      onTap: () => Navigator.pop(context, _ColorChoice(SiteDesign.token(c.id))),
                    ),
                ],
              ),
              if (widget.legacy.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Classic options', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in widget.legacy.entries)
                      _swatch(
                        key: Key('$k-legacy-${e.key}'),
                        name: e.value.$1,
                        color: e.value.$2,
                        selected: widget.value == e.key,
                        onTap: () => Navigator.pop(context, _ColorChoice(e.key)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text('Custom colour', style: TextStyle(fontWeight: FontWeight.w600)),
              const Text('A fixed colour for this element only: it doesn’t follow the palette.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: SiteDesign.parseHex(_hexValue) ?? Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.black26)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: Key('$k-hex'),
                      controller: _hex,
                      maxLength: 7,
                      decoration: websiteField('HEX', helper: 'For example #1F4D3A').copyWith(
                        errorText: _hex.text.trim().length <= 1 || hexValid ? null : 'Enter # and six digits 0–9 or A–F.',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: Key('$k-hex-apply'),
                    onPressed: hexValid ? () => Navigator.pop(context, _ColorChoice(_hexValue)) : null,
                    child: const Text('Use'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(key: Key('$k-default'), onPressed: () => Navigator.pop(context, const _ColorChoice(null)), child: const Text('Reset to default')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
