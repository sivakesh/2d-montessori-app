import 'package:flutter/material.dart';

import '../../public_routes.dart';
import '../../public_website_theme.dart';

/// Abstract, Montessori-material-inspired shapes (circles and a bead bar)
/// in the site palette. Purely decorative.
class PublicHeroOrnament extends StatelessWidget {
  const PublicHeroOrnament({super.key});

  @override
  Widget build(BuildContext context) {
    Widget circle(double size, Color color) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(color: PublicColors.sageLight, borderRadius: BorderRadius.circular(32)),
              ),
            ),
            Positioned(top: 36, left: 36, child: circle(120, PublicColors.sage.withValues(alpha: 0.55))),
            Positioned(bottom: 44, right: 40, child: circle(84, PublicColors.goldLight)),
            Positioned(bottom: 64, right: 60, child: circle(44, PublicColors.gold.withValues(alpha: 0.7))),
            Positioned(
              left: 40,
              right: 40,
              top: 0,
              bottom: 0,
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: circle(16, i.isEven ? PublicColors.forest : PublicColors.gold),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A linked card with an icon, title, text and a call to action (the
/// homepage's pathways, and the Cards block).
class PublicPathwayCard extends StatelessWidget {
  const PublicPathwayCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.route,
    required this.accent,
    this.onTap,
    this.enabled = true,
    this.ctaColor,
    this.titleColor,
    this.bodyColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final String cta;

  /// Opened in place when tapped (unless [onTap] is given).
  final String route;
  final Color accent;
  final VoidCallback? onTap;

  /// False: shown but not tappable (editor previews).
  final bool enabled;

  /// Defaults: the accent (a darker gold for gold), the site's title and
  /// body colours.
  final Color? ctaColor;
  final Color? titleColor;
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    final link = ctaColor ?? (accent == PublicColors.gold ? const Color(0xFF8A6A33) : accent);
    return Material(
      color: PublicColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: PublicColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: !enabled ? null : onTap ?? (route.isEmpty ? null : () => PublicRoutes.open(context, route)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(height: 20),
              Text(title, style: PublicText.title.copyWith(fontSize: 22, color: titleColor)),
              const SizedBox(height: 8),
              if (body.isNotEmpty) Text(body, style: PublicText.body.copyWith(color: bodyColor)),
              if (cta.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(cta, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: link))),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 18, color: link),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

