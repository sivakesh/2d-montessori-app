import 'package:flutter/foundation.dart';

/// A block's own spacing, for every block type (it is part of a block's
/// `style`, not of its fields): **padding**, inside the block's surface
/// (between its edge, or its background and border, and its content), and
/// **margin**, outside it (between it and what is around it). Each has
/// top, right, bottom and left, on desktop, tablets and phones.
///
/// Stored under [padding] (`blockPadding`) and [margin] (`blockMargin`),
/// each only with what is set:
/// `{'desktop': {'top': 24, 'left': 0}, 'mobile': {'top': 8}}`. A side not
/// set is Automatic: on tablets it is desktop's, on phones the tablet's,
/// else desktop's; else the block's own layout, exactly as before these
/// settings existed. An optional `unit` is `px` (the only unit so far).
abstract final class BlockSpacing {
  static const padding = 'blockPadding';
  static const margin = 'blockMargin';
  static const kinds = [padding, margin];
  static const sides = ['top', 'right', 'bottom', 'left'];
  static const screens = ['desktop', 'tablet', 'mobile'];
  static const units = ['px'];
  static const min = 0;
  static const max = 200;

  static const kindNames = {padding: 'padding', margin: 'margin'};

  /// Why [value] can't be stored under a spacing key, or null when it can.
  static String? problem(Object? value) {
    final name = 'spacing';
    if (value is! Map) return 'its $name can’t be read';
    for (final entry in value.entries) {
      final key = entry.key;
      if (key == 'unit') {
        if (!units.contains(entry.value)) return '“${entry.value}” is not a $name unit';
        continue;
      }
      // Screens this version doesn't know are kept, unused.
      if (!screens.contains(key)) continue;
      final perSide = entry.value;
      if (perSide is! Map) return 'its $name on ${_screenName(key)} can’t be read';
      for (final side in perSide.entries) {
        if (!sides.contains(side.key)) continue;
        final n = side.value;
        if (n is! num || !n.isFinite || n != n.roundToDouble() || n < min || n > max) {
          return 'its $name (${_screenName(key)}, ${side.key}) must be a whole number from $min to $max px';
        }
      }
    }
    return null;
  }

  static String _screenName(Object? screen) => switch (screen) { 'tablet' => 'tablets', 'mobile' => 'phones', _ => 'desktop' };

  /// The value [stored] sets itself for [side] on [screen] (not inherited).
  static int? own(Object? stored, String screen, String side) {
    if (stored is! Map) return null;
    final perSide = stored[screen];
    final n = perSide is Map ? perSide[side] : null;
    return n is num && n.isFinite && n >= min && n <= max ? n.round() : null;
  }

  /// The screens [screen] takes a side from, nearest first.
  static List<String> chain(String screen) => switch (screen) {
        'mobile' => const ['mobile', 'tablet', 'desktop'],
        'tablet' => const ['tablet', 'desktop'],
        _ => const ['desktop'],
      };

  /// [side] on [screen]: its own value, else the nearest larger screen's,
  /// else null (Automatic: the block's own layout).
  static int? resolve(Object? stored, String screen, String side) {
    for (final s in chain(screen)) {
      if (own(stored, s, side) case final n?) return n;
    }
    return null;
  }

  /// Where [screen]'s [side] comes from when it has no value of its own:
  /// the larger screen that sets it, or null (Automatic).
  static String? inheritedFrom(Object? stored, String screen, String side) {
    for (final s in chain(screen).skip(1)) {
      if (own(stored, s, side) != null) return s;
    }
    return null;
  }

  /// The four sides on [screen] (null where Automatic).
  static SpacingSides sidesOn(Object? stored, String screen) => SpacingSides(
        top: resolve(stored, screen, 'top')?.toDouble(),
        right: resolve(stored, screen, 'right')?.toDouble(),
        bottom: resolve(stored, screen, 'bottom')?.toDouble(),
        left: resolve(stored, screen, 'left')?.toDouble(),
      );

  /// [stored] with [screen]'s [values] set (null removes a side), or null
  /// when nothing is left to store. Other screens, a unit and keys this
  /// version doesn't know are kept.
  static Map<String, dynamic>? withValues(Object? stored, String screen, Map<String, int?> values) {
    final out = <String, dynamic>{if (stored is Map) for (final e in stored.entries) e.key.toString(): e.value};
    final perSide = <String, dynamic>{if (out[screen] is Map) for (final e in (out[screen] as Map).entries) e.key.toString(): e.value};
    for (final e in values.entries) {
      e.value == null ? perSide.remove(e.key) : perSide[e.key] = e.value;
    }
    perSide.isEmpty ? out.remove(screen) : out[screen] = perSide;
    final meaningful = out.keys.where((k) => k != 'unit');
    return meaningful.isEmpty ? null : out;
  }
}

/// Up to four sides in px; null is Automatic.
@immutable
class SpacingSides {
  const SpacingSides({this.top, this.right, this.bottom, this.left});

  final double? top;
  final double? right;
  final double? bottom;
  final double? left;

  bool get isAutomatic => top == null && right == null && bottom == null && left == null;

  /// These sides over [automatic] (its values where these are Automatic).
  ({double top, double right, double bottom, double left}) over({double top = 0, double right = 0, double bottom = 0, double left = 0}) =>
      (top: this.top ?? top, right: this.right ?? right, bottom: this.bottom ?? bottom, left: this.left ?? left);

  @override
  bool operator ==(Object other) => other is SpacingSides && other.top == top && other.right == right && other.bottom == bottom && other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => 'SpacingSides($top, $right, $bottom, $left)';
}
