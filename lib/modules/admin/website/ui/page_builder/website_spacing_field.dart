import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/blocks/block_spacing.dart';

/// A block's own padding or margin ([BlockSpacing]) as a box with its four
/// sides around it, for desktop, tablets or phones: each side blank for
/// Automatic (shown with what it inherits), or 0–200 px. *Same on all
/// sides* links the four; *Reset to Automatic* clears the screen size
/// shown. Every change is passed on at once ([onChanged] with the new
/// stored value, null when nothing is left).
///
/// Keys (`<fieldKey>` is e.g. `website-block-<id>-style-blockPadding`):
/// `-screen-<desktop|tablet|mobile>`, `-unit`, `-link`, `-<side>`,
/// `-<side>-status`, `-<side>-reset`, `-reset`, `-reset-all`, `-summary`.
///
/// With [sides] `top` and `bottom` it is a vertical control (a section's
/// padding): only those sides are shown, linked and reset; the others are
/// kept as they are.
class WebsiteSpacingField extends StatefulWidget {
  const WebsiteSpacingField({super.key, required this.fieldKey, required this.kind, required this.value, required this.onChanged, this.sides = BlockSpacing.sides, this.automaticOf, this.description});

  final String fieldKey;

  /// The sides offered.
  final List<String> sides;

  /// What a side is when Automatic on a screen size (the block's own
  /// spacing, in px), for the field's hint; null: not shown.
  final int? Function(String screen, String side)? automaticOf;

  /// In place of the usual explanation.
  final String? description;

  /// [BlockSpacing.padding] or [BlockSpacing.margin].
  final String kind;

  /// As stored (a map, or null).
  final Object? value;
  final ValueChanged<Map<String, dynamic>?> onChanged;

  static const screenLabels = {'desktop': 'Desktop', 'tablet': 'Tablet', 'mobile': 'Phone'};

  /// What [value] sets for [sides], in a line ("Desktop: all 16 px;
  /// Phone: top 8"), or "Automatic".
  static String summary(Object? value, {List<String> sides = BlockSpacing.sides}) {
    final parts = <String>[];
    for (final s in BlockSpacing.screens) {
      final own = {for (final side in sides) side: BlockSpacing.own(value, s, side)};
      if (own.values.every((v) => v == null)) continue;
      final text = own.values.every((v) => v != null) && own.length == 4
          ? (own.values.toSet().length == 1 ? 'all ${own.values.first} px' : '${own.values.join(' · ')} px')
          : [
              for (final e in own.entries)
                if (e.value != null) '${e.key} ${e.value}',
            ].join(', ');
      parts.add('${screenLabels[s]}: $text');
    }
    return parts.isEmpty ? 'Automatic' : parts.join('; ');
  }

  @override
  State<WebsiteSpacingField> createState() => _WebsiteSpacingFieldState();
}

class _WebsiteSpacingFieldState extends State<WebsiteSpacingField> {
  String _screen = 'desktop';
  late bool _linked = _allEqual(_screen);

  /// Whether [screen] sets every side offered to one value (then they start linked).
  bool _allEqual(String screen) {
    final values = {for (final side in widget.sides) BlockSpacing.own(widget.value, screen, side)};
    return values.length == 1 && values.first != null;
  }

  void _set(String side, int? value) {
    final sides = _linked ? widget.sides : [side];
    widget.onChanged(BlockSpacing.withValues(widget.value, _screen, {for (final s in sides) s: value}));
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.fieldKey;
    final name = BlockSpacing.kindNames[widget.kind]!;
    final anySet = widget.sides.any((s) => BlockSpacing.own(widget.value, _screen, s) != null);
    final anySetAnywhere = BlockSpacing.screens.any((screen) => widget.sides.any((s) => BlockSpacing.own(widget.value, screen, s) != null));
    final vertical = !widget.sides.contains('left');
    Widget side(String s) => _SideField(
      key: Key('$k-$s-$_screen'),
      fieldKey: '$k-$s',
      side: s,
      value: BlockSpacing.own(widget.value, _screen, s),
      inherited: BlockSpacing.resolve(widget.value, _screen, s),
      inheritedFrom: BlockSpacing.inheritedFrom(widget.value, _screen, s),
      automatic: widget.automaticOf?.call(_screen, s),
      onChanged: (v) => _set(s, v),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.description ??
              (widget.kind == BlockSpacing.padding
                  ? 'Inside the block: between its edge (its background and border, if any) and its content.'
                  : 'Outside the block: between it and the blocks around it, added to the usual space above it.'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: [
                for (final s in BlockSpacing.screens)
                  ButtonSegment(
                    value: s,
                    label: Text(WebsiteSpacingField.screenLabels[s]!, key: Key('$k-screen-$s')),
                  ),
              ],
              selected: {_screen},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() {
                _screen = v.first;
                _linked = _allEqual(_screen);
              }),
            ),
            SizedBox(
              width: 92,
              child: DropdownButtonFormField<String>(
                key: Key('$k-unit'),
                initialValue: 'px',
                isDense: true,
                decoration: const InputDecoration(labelText: 'Unit', isDense: true, border: OutlineInputBorder()),
                items: [for (final u in BlockSpacing.units) DropdownMenuItem(value: u, child: Text(u))],
                onChanged: (_) {},
              ),
            ),
            FilterChip(
              key: Key('$k-link'),
              avatar: Icon(_linked ? Icons.link : Icons.link_off, size: 16),
              label: Text(vertical ? 'Same top and bottom' : 'Same on all sides'),
              selected: _linked,
              showCheckmark: false,
              onSelected: (on) => setState(() => _linked = on),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The box model: the sides around the content they space.
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.kind == BlockSpacing.padding ? const Color(0xFFF3EADB) : const Color(0xFFE6EDE2),
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: vertical
              ? Column(
                  children: [
                    side('top'),
                    Container(
                      width: double.infinity,
                      height: 32,
                      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Content', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ),
                    side('bottom'),
                  ],
                )
              : Column(
                  children: [
                    side('top'),
                    Row(
                      children: [
                        Expanded(child: side('left')),
                        Container(
                          width: 56,
                          height: 44,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(widget.kind == BlockSpacing.padding ? 'Content' : 'Block', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ),
                        Expanded(child: side('right')),
                      ],
                    ),
                    side('bottom'),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        Text(
          WebsiteSpacingField.summary(widget.value, sides: widget.sides),
          key: Key('$k-summary'),
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton.icon(
              key: Key('$k-reset'),
              onPressed: anySet ? () => widget.onChanged(BlockSpacing.withValues(widget.value, _screen, {for (final s in widget.sides) s: null})) : null,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: Text('Reset ${WebsiteSpacingField.screenLabels[_screen]!.toLowerCase()} $name'),
            ),
            TextButton(
              key: Key('$k-reset-all'),
              onPressed: anySetAnywhere
                  ? () {
                      Object? next = widget.value;
                      for (final screen in BlockSpacing.screens) {
                        next = BlockSpacing.withValues(next, screen, {for (final s in widget.sides) s: null});
                      }
                      widget.onChanged(next as Map<String, dynamic>?);
                    }
                  : null,
              child: const Text('Reset every screen size to Automatic'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One side: blank for Automatic (its hint says what it inherits), or a
/// number of px; out of range is explained and not passed on.
class _SideField extends StatefulWidget {
  const _SideField({super.key, required this.fieldKey, required this.side, required this.value, required this.inherited, required this.inheritedFrom, required this.onChanged, this.automatic});

  /// What Automatic is here (the block's own spacing), if known.
  final int? automatic;

  final String fieldKey;
  final String side;
  final int? value;

  /// What it is without its own value: the larger screen's ([inheritedFrom]), or null.
  final int? inherited;
  final String? inheritedFrom;
  final ValueChanged<int?> onChanged;

  @override
  State<_SideField> createState() => _SideFieldState();
}

class _SideFieldState extends State<_SideField> {
  late final _text = TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void didUpdateWidget(_SideField old) {
    super.didUpdateWidget(old);
    // Linked sides, Reset, or another screen size: show what is set.
    if (widget.value != int.tryParse(_text.text)) _text.text = widget.value?.toString() ?? '';
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = int.tryParse(_text.text);
    final invalid = _text.text.isNotEmpty && (n == null || n < BlockSpacing.min || n > BlockSpacing.max);
    final status = widget.value != null
        ? 'Set'
        : widget.inheritedFrom != null
        ? 'From ${WebsiteSpacingField.screenLabels[widget.inheritedFrom]!.toLowerCase()}: ${widget.inherited}'
        : widget.automatic != null
        ? 'Automatic: ${widget.automatic}'
        : 'Automatic';
    final label = '${widget.side[0].toUpperCase()}${widget.side.substring(1)}';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextField(
            key: Key(widget.fieldKey),
            controller: _text,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: '$label (px)',
              hintText: widget.inherited?.toString() ?? widget.automatic?.toString() ?? 'Auto',
              helper: Text(
                status,
                key: Key('${widget.fieldKey}-status'),
                style: TextStyle(fontSize: 11, fontWeight: widget.value != null ? FontWeight.w600 : FontWeight.w400),
              ),
              errorText: invalid ? '${BlockSpacing.min}–${BlockSpacing.max}' : null,
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
              suffixIcon: widget.value == null && _text.text.isEmpty
                  ? null
                  : IconButton(
                      key: Key('${widget.fieldKey}-reset'),
                      tooltip: 'Reset to Automatic',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        setState(_text.clear);
                        widget.onChanged(null);
                      },
                    ),
            ),
            onChanged: (t) {
              setState(() {});
              final v = int.tryParse(t);
              if (t.isEmpty) {
                widget.onChanged(null);
              } else if (v != null && v >= BlockSpacing.min && v <= BlockSpacing.max) {
                widget.onChanged(v);
              }
            },
          ),
        ),
      ),
    );
  }
}
