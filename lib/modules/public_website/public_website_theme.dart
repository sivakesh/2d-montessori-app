import 'package:flutter/material.dart';

/// Palette and type scale for the public website only — the management
/// app keeps AppTheme/AppColors. Warm white grounds, forest-green and sage
/// accents, muted gold details.
class PublicColors {
  static const background = Color(0xFFFBF8F2); // warm white
  static const surface = Color(0xFFFFFFFF);
  static const forest = Color(0xFF1F4D3A);
  static const forestDark = Color(0xFF163829);
  static const sage = Color(0xFF8FA98B);
  static const sageLight = Color(0xFFE6EDE2);
  static const gold = Color(0xFFB8955A);
  static const goldLight = Color(0xFFF3EADB);
  static const ink = Color(0xFF26302B);
  static const muted = Color(0xFF5F6B64);
  static const line = Color(0xFFE4DED2);
}

/// Width breakpoints shared by the public pages.
enum PublicLayout {
  mobile,
  tablet,
  desktop;

  static PublicLayout of(double width) => width < 700
      ? PublicLayout.mobile
      : width < 1100
          ? PublicLayout.tablet
          : PublicLayout.desktop;

  bool get isMobile => this == PublicLayout.mobile;
  bool get isDesktop => this == PublicLayout.desktop;

  /// Horizontal page gutter.
  double get gutter => switch (this) {
        PublicLayout.mobile => 20,
        PublicLayout.tablet => 40,
        PublicLayout.desktop => 64,
      };
}

class PublicText {
  static const display = TextStyle(
    fontSize: 44,
    height: 1.15,
    fontWeight: FontWeight.w600,
    color: PublicColors.forestDark,
    letterSpacing: -0.5,
  );
  static const displayMobile = TextStyle(
    fontSize: 32,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: PublicColors.forestDark,
    letterSpacing: -0.3,
  );
  static const heading = TextStyle(fontSize: 26, height: 1.25, fontWeight: FontWeight.w600, color: PublicColors.forestDark);
  static const title = TextStyle(fontSize: 19, height: 1.3, fontWeight: FontWeight.w600, color: PublicColors.forestDark);
  static const body = TextStyle(fontSize: 16, height: 1.6, color: PublicColors.muted);
  static const eyebrow = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.6,
    color: PublicColors.gold,
  );
  static const nav = TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: PublicColors.ink);
}

/// Centers page content at a comfortable reading width with the layout's
/// gutter.
class PublicContentWidth extends StatelessWidget {
  const PublicContentWidth({super.key, required this.child, this.maxWidth = 1160});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final layout = PublicLayout.of(MediaQuery.sizeOf(context).width);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + layout.gutter * 2),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: child,
        ),
      ),
    );
  }
}
