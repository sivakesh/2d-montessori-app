import 'package:flutter/widgets.dart';

/// PLACEHOLDER palette. PRD §3.6 requires a single `approvedPaletteKey`
/// sourced from brand assets the client supplies (SRS §2.3) — these values
/// are a neutral, WCAG 2.2 AA-passing stand-in only, so early screens can be
/// built and reviewed before final brand colors are approved. Replace via
/// `settings/{brand}` once real tokens are signed off; do not hand-pick
/// colors per screen (PRD §3.6 "no per-section numeric entry").
abstract final class ColorTokens {
  // Neutral / warm-white foundation (PRD §3.1 "Colour").
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceWarm = Color(0xFFFBF8F3);
  static const Color surfaceAlt = Color(0xFFF4F1EA);

  // Text.
  static const Color textPrimary = Color(0xFF1F2421);
  static const Color textSecondary = Color(0xFF52584F);
  static const Color textOnAccent = Color(0xFFFFFFFF);

  // Single approved accent — placeholder warm green, TODO replace with
  // final 2D Montessori brand accent.
  static const Color accent = Color(0xFF3D6B4C);
  static const Color accentMuted = Color(0xFFDCE9DF);

  static const Color border = Color(0xFFE3DED3);
  static const Color error = Color(0xFFB3261E);
}
