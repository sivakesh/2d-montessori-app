import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// One series of a [MonthlyBarChart]: a value per month, in month order.
class MonthlyChartSeries {
  const MonthlyChartSeries({required this.label, required this.color, required this.values, required this.keyPrefix});
  final String label;
  final Color color;
  final List<double> values;

  /// Each bar's key: `$keyPrefix-YYYY-MM`.
  final String keyPrefix;
}

/// A compact grouped bar chart of monthly amounts (the Fees and Finance
/// dashboards), drawn with plain widgets: one group per month, one bar per
/// series, each bar its own tappable, focusable, labelled button.
///
/// Each bar sits in its own fixed-width slot, so the compact value above it
/// can never run into its neighbour's. Month groups keep a minimum width:
/// when they don't all fit (phones), the chart scrolls sideways instead of
/// shrinking; when there is room (desktop), the groups spread across it.
/// Zero months keep a visible baseline and a "₹0" label. Hovering or
/// focusing a bar shows its exact amount above the chart; the tooltip and
/// the accessible label carry it too.
class MonthlyBarChart extends StatefulWidget {
  const MonthlyBarChart({
    super.key,
    required this.months,
    required this.monthLabels,
    required this.series,
    required this.onBarTap,
    this.height = 230,
    this.semanticsPrefix = '',
  });

  /// `YYYY-MM`, in order.
  final List<String> months;

  /// Shown under each group ("Jun", "Jan\n2027").
  final List<String> monthLabels;
  final List<MonthlyChartSeries> series;
  final void Function(int series, String month) onBarTap;

  /// The plot's height: bars, the values above them and the month labels.
  final double height;
  final String semanticsPrefix;

  /// The dashboards' shared colours: money in (fee collections, income) and
  /// money out (expenses).
  static const moneyInColor = Color(0xFF2E7D32);
  static const moneyOutColor = Color(0xFFC62828);

  /// Layout (logical pixels). A slot is one bar's column, as wide as its
  /// value label may be; the bar is centred in it.
  static const slotWidth = 46.0;
  static const barWidth = 26.0;
  static const barGap = 8.0;
  static const groupPadding = 24.0;
  static const valueHeight = 20.0;
  static const labelHeight = 40.0;

  /// A month group's minimum width for [seriesCount] bars.
  static double groupWidthFor(int seriesCount) => seriesCount * slotWidth + (seriesCount - 1) * barGap + groupPadding;

  static String money(double v) => '₹${NumberFormat.decimalPatternDigits(locale: 'en_IN', decimalDigits: 0).format(v.round())}';

  /// "₹950", "₹12.5k", "₹46k", "₹3.2L", "₹1.2Cr": short enough for a slot.
  static String compact(double v) {
    final a = v.abs();
    String fixed(double x, bool whole) => x.toStringAsFixed(whole ? 0 : 1).replaceFirst(RegExp(r'\.0$'), '');
    if (a >= 10000000) return '₹${fixed(v / 10000000, a >= 100000000)}Cr';
    if (a >= 100000) return '₹${fixed(v / 100000, a >= 1000000)}L';
    if (a >= 1000) return '₹${fixed(v / 1000, a >= 10000)}k';
    return '₹${v.round()}';
  }

  @override
  State<MonthlyBarChart> createState() => _MonthlyBarChartState();
}

class _MonthlyBarChartState extends State<MonthlyBarChart> {
  /// The bar being hovered or focused: (series, month index).
  (int, int)? _active;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setActive((int, int) bar, bool on) {
    if (on) {
      if (_active != bar) setState(() => _active = bar);
    } else if (_active == bar) {
      setState(() => _active = null);
    }
  }

  String _fullMonth(int mi) => DateFormat('MMMM yyyy').format(DateTime(
        int.parse(widget.months[mi].substring(0, 4)),
        int.parse(widget.months[mi].substring(5)),
      ));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = widget.series;
    final months = widget.months;
    final maxValue = [for (final s in series) ...s.values].fold<double>(0, (m, v) => v > m ? v : m);
    const slotWidth = MonthlyBarChart.slotWidth, valueHeight = MonthlyBarChart.valueHeight, labelHeight = MonthlyBarChart.labelHeight;
    final groupWidth = MonthlyBarChart.groupWidthFor(series.length);
    final barArea = widget.height - labelHeight - valueHeight;

    final valueStyle = theme.textTheme.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface);
    final zeroStyle = valueStyle?.copyWith(fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant);
    final monthStyle = theme.textTheme.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25, color: theme.colorScheme.onSurface);

    Widget bar(int si, int mi) {
      final s = series[si];
      final v = s.values[mi];
      final h = maxValue <= 0 || v <= 0 ? 2.0 : (v / maxValue * barArea).clamp(4.0, barArea);
      final active = _active == (si, mi);
      return Semantics(
        button: true,
        label: '${widget.semanticsPrefix}${s.label}, ${_fullMonth(mi)}: ${MonthlyBarChart.money(v)}',
        excludeSemantics: true,
        child: Tooltip(
          message: '${s.label} · ${_fullMonth(mi)}: ${MonthlyBarChart.money(v)}',
          child: InkWell(
            key: Key('${s.keyPrefix}-${months[mi]}'),
            onTap: () => widget.onBarTap(si, months[mi]),
            onHover: (on) => _setActive((si, mi), on),
            onFocusChange: (on) => _setActive((si, mi), on),
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: slotWidth,
              height: barArea + valueHeight,
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                SizedBox(
                  height: valueHeight,
                  width: slotWidth,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(MonthlyBarChart.compact(v), maxLines: 1, style: v > 0 ? valueStyle : zeroStyle),
                    ),
                  ),
                ),
                Container(
                  width: MonthlyBarChart.barWidth,
                  height: h,
                  decoration: BoxDecoration(
                    color: v > 0 ? s.color : s.color.withValues(alpha: 0.35),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    border: active ? Border.all(color: theme.colorScheme.onSurface, width: 1.5) : null,
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    Widget group(int mi, double width) => SizedBox(
          width: width,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var si = 0; si < series.length; si++) ...[if (si > 0) const SizedBox(width: MonthlyBarChart.barGap), bar(si, mi)],
            ]),
            Container(height: 1, color: theme.dividerColor),
            SizedBox(
              height: labelHeight - 1,
              child: Center(child: Text(widget.monthLabels[mi], textAlign: TextAlign.center, style: monthStyle, maxLines: 2)),
            ),
          ]),
        );

    final a = _active;
    final readout = a == null
        ? ''
        : '${series[a.$1].label} · ${_fullMonth(a.$2)}: ${MonthlyBarChart.money(series[a.$1].values[a.$2])}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 20, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 14, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Text(s.label, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
          ]),
      ]),
      SizedBox(
        height: 24,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(readout, key: const Key('monthly-chart-readout'), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ),
      ),
      LayoutBuilder(builder: (context, c) {
        final needed = groupWidth * months.length;
        // Room to spare: widen every group equally (bars stay the same size).
        final width = c.maxWidth.isFinite && needed < c.maxWidth ? c.maxWidth / months.length : groupWidth;
        return SizedBox(
          height: widget.height + 10,
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [for (var mi = 0; mi < months.length; mi++) group(mi, width)],
              ),
            ),
          ),
        );
      }),
    ]);
  }
}
