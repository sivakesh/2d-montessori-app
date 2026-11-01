import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../public_website/content/website_design.dart';

/// A size in whole pixels within [range]: a slider and a number box, with
/// whether it is set here ("Custom") or follows [inheritedFrom], and a
/// reset that clears it. [value] null means not set: the slider and box
/// show [inheritedValue]. Moving the slider or entering a number in range
/// sets it; a number out of range is explained and not applied.
///
/// Keys: [fieldKey] (the number box), `-slider`, `-status`, `-reset`.
class WebsiteSizeField extends StatefulWidget {
  const WebsiteSizeField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.range,
    required this.value,
    required this.inheritedValue,
    required this.inheritedFrom,
    required this.onChanged,
    this.unit = 'px',
  });

  final String fieldKey;
  final String label;
  final FontSizeRange range;
  final double? value;
  final double inheritedValue;

  /// What an unset value follows ("the site typography").
  final String inheritedFrom;
  final ValueChanged<double?> onChanged;
  final String unit;

  @override
  State<WebsiteSizeField> createState() => _WebsiteSizeFieldState();
}

class _WebsiteSizeFieldState extends State<WebsiteSizeField> {
  late final _text = TextEditingController(text: _shown);
  final _focus = FocusNode();
  String? _error;

  String get _shown => (widget.value ?? widget.inheritedValue).round().toString();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_left);
  }

  /// Leaving the box with a number that wasn't applied shows the size in
  /// use again (typing may have applied a number on the way, e.g. 23 while
  /// deleting 236), so the box never disagrees with the page.
  void _left() {
    if (!_focus.hasFocus && _error != null) {
      setState(() {
        _text.text = _shown;
        _error = null;
      });
    }
  }

  @override
  void didUpdateWidget(WebsiteSizeField old) {
    super.didUpdateWidget(old);
    // Follows changes from elsewhere (the slider, a reset, a reload), not
    // while the number is being typed.
    if (!_focus.hasFocus && _text.text != _shown) {
      _text.text = _shown;
      _error = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String raw) {
    final n = int.tryParse(raw.trim());
    final range = widget.range;
    if (n == null || !range.allows(n)) {
      setState(() => _error = 'Enter ${range.min.round()} to ${range.max.round()}.');
      return;
    }
    setState(() => _error = null);
    if (n.toDouble() != widget.value) widget.onChanged(n.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final range = widget.range;
    final shown = (widget.value ?? widget.inheritedValue).clamp(range.min, range.max).toDouble();
    final custom = widget.value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              if (custom)
                TextButton(
                  key: Key('${widget.fieldKey}-reset'),
                  onPressed: () {
                    setState(() => _error = null);
                    widget.onChanged(null);
                  },
                  child: const Text('Reset'),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: Key('${widget.fieldKey}-slider'),
                  value: shown,
                  min: range.min,
                  max: range.max,
                  divisions: (range.max - range.min).round(),
                  // The theme's inactive track is the card colour, invisible
                  // on the panel: the range would show no end.
                  inactiveColor: AppColors.textSecondary.withValues(alpha: 0.3),
                  label: '${shown.round()} ${widget.unit}',
                  semanticFormatterCallback: (v) => '${widget.label}: ${v.round()} ${widget.unit}',
                  onChanged: (v) {
                    final px = v.roundToDouble();
                    setState(() => _error = null);
                    _text.text = px.round().toString();
                    if (px != widget.value) widget.onChanged(px);
                  },
                ),
              ),
              SizedBox(
                width: 84,
                child: TextField(
                  key: Key(widget.fieldKey),
                  controller: _text,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), suffixText: widget.unit, semanticCounterText: widget.label),
                  onChanged: _typed,
                  onSubmitted: _typed,
                ),
              ),
            ],
          ),
          Text(
            _error ?? (custom ? 'Custom: ${widget.value!.round()} ${widget.unit}' : 'Inherits ${widget.inheritedFrom}: ${widget.inheritedValue.round()} ${widget.unit}'),
            key: Key('${widget.fieldKey}-status'),
            style: TextStyle(fontSize: 12, color: _error != null ? const Color(0xFFB3261E) : (custom ? AppColors.primary : AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
