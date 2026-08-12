import 'package:flutter/widgets.dart';

/// Fluid type scale (PRD §3.1 "Typography"). Body text stays at or above
/// 16 logical pixels on public pages per the same section. Font family is
/// a placeholder platform-safe stack until `approvedFontKey` is set in
/// brand settings (PRD §3.6).
abstract final class TypographyTokens {
  static const String fontFamilyFallback =
      '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';

  static const TextStyle displayLarge = TextStyle(
    fontSize: 40,
    height: 1.15,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle headingLarge = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle headingMedium = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 18,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );
  static const TextStyle label = TextStyle(
    fontSize: 14,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );
}
