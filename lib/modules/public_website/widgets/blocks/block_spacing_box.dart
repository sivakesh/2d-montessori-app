import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Padding that never squeezes its child off the page: when the left and
/// right sides together would take more than a third of the width
/// available, both shrink in proportion to fit that third (top and bottom
/// are kept). With room to spare it is exactly [Padding].
///
/// A block's own spacing ([BlockSpacing]) is drawn with it, so a large
/// side set for desktop can't cause horizontal overflow on a phone or in a
/// narrow column.
class FitPadding extends SingleChildRenderObjectWidget {
  const FitPadding({super.key, required this.padding, super.child});

  final EdgeInsets padding;

  /// The share of the width the left and right sides may take together.
  static const maxShare = 1 / 3;

  /// [padding] as it is drawn within [maxWidth].
  static EdgeInsets fitted(EdgeInsets padding, double maxWidth) {
    final across = padding.left + padding.right;
    if (!maxWidth.isFinite || across <= maxWidth * maxShare || across <= 0) return padding;
    final k = math.max(0.0, maxWidth * maxShare) / across;
    return padding.copyWith(left: padding.left * k, right: padding.right * k);
  }

  @override
  RenderFitPadding createRenderObject(BuildContext context) => RenderFitPadding(padding);

  @override
  void updateRenderObject(BuildContext context, RenderFitPadding renderObject) => renderObject.padding = padding;
}

class RenderFitPadding extends RenderShiftedBox {
  RenderFitPadding(this._padding) : super(null);

  EdgeInsets _padding;
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  /// The padding used in the last layout.
  EdgeInsets applied = EdgeInsets.zero;

  @override
  double computeMinIntrinsicWidth(double height) => _padding.horizontal + (child?.getMinIntrinsicWidth(math.max(0, height - _padding.vertical)) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) => _padding.horizontal + (child?.getMaxIntrinsicWidth(math.max(0, height - _padding.vertical)) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) {
    final p = FitPadding.fitted(_padding, width);
    return p.vertical + (child?.getMinIntrinsicHeight(math.max(0, width - p.horizontal)) ?? 0);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final p = FitPadding.fitted(_padding, width);
    return p.vertical + (child?.getMaxIntrinsicHeight(math.max(0, width - p.horizontal)) ?? 0);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final p = FitPadding.fitted(_padding, constraints.maxWidth);
    final c = child;
    if (c == null) return constraints.constrain(Size(p.horizontal, p.vertical));
    final inner = c.getDryLayout(constraints.deflate(p));
    return constraints.constrain(Size(inner.width + p.horizontal, inner.height + p.vertical));
  }

  @override
  void performLayout() {
    final p = applied = FitPadding.fitted(_padding, constraints.maxWidth);
    final c = child;
    if (c == null) {
      size = constraints.constrain(Size(p.horizontal, p.vertical));
      return;
    }
    c.layout(constraints.deflate(p), parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = Offset(p.left, p.top);
    size = constraints.constrain(Size(c.size.width + p.horizontal, c.size.height + p.vertical));
  }
}
