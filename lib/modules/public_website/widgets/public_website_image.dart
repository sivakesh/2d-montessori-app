import 'package:flutter/material.dart';

import '../content/website_content_models.dart';
import '../public_website_theme.dart';

/// A managed website image cropped to [aspectRatio] around its focal
/// point. It downloads the smallest stored size that covers the space it
/// is drawn in (the thumbnail in grids) and decodes at that size, fades in
/// once loaded, and shows [placeholder] while there is no image, while it
/// loads, and (with a quiet "image unavailable" mark) if it fails to load.
class PublicWebsiteImage extends StatelessWidget {
  const PublicWebsiteImage({
    super.key,
    required this.media,
    required this.aspectRatio,
    required this.semanticLabel,
    this.placeholder,
    this.borderRadius = 20,
    this.fit = BoxFit.cover,
    this.errorLabel,
    this.alignment,
  });

  /// Where the image sits when it doesn't fill (or is cropped): null for
  /// the library's focal point under [BoxFit.cover], else centred.
  final Alignment? alignment;

  /// The image, or null for the placeholder.
  final WebsiteMedia? media;
  final double aspectRatio;

  /// Alt text read by screen readers.
  final String semanticLabel;
  final Widget? placeholder;
  final double borderRadius;

  /// [BoxFit.cover] crops around the focal point; [BoxFit.contain] shows
  /// the whole image (the lightbox).
  final BoxFit fit;

  /// Accessible label for the failed-load state.
  final String? errorLabel;

  @override
  Widget build(BuildContext context) {
    final fallback = placeholder ?? const PublicImagePlaceholder();
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: media == null
            ? fallback
            : LayoutBuilder(
                builder: (context, constraints) {
                  final media = this.media!;
                  final pixelRatio = MediaQuery.devicePixelRatioOf(context);
                  final physicalWidth = constraints.maxWidth * pixelRatio;
                  // Decode no larger than drawn (cover may need the height to
                  // fill, so size by whichever side is the tighter fit).
                  final coverWidth = fit == BoxFit.cover && media.aspectRatio > 0
                      ? (constraints.maxHeight * pixelRatio * media.aspectRatio).clamp(physicalWidth, double.infinity)
                      : physicalWidth;
                  final decodeWidth = coverWidth.isFinite && coverWidth > 0 ? coverWidth.ceil() : null;
                  return Image.network(
                    media.urlForWidth(coverWidth.isFinite ? coverWidth : physicalWidth),
                    key: ValueKey('public-image-${media.id}'),
                    fit: fit,
                    alignment: alignment ?? (fit == BoxFit.cover ? media.alignment : Alignment.center),
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: decodeWidth,
                    semanticLabel: semanticLabel,
                    // Storage serves images cross-origin; if the bucket's CORS
                    // ever blocks canvas decoding, fall back to an <img> element.
                    webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded) return child;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          fallback,
                          AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOut,
                            child: child,
                          ),
                        ],
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Stack(
                      key: ValueKey('public-image-error-${media.id}'),
                      fit: StackFit.expand,
                      children: [
                        fallback,
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Tooltip(
                              message: errorLabel ?? semanticLabel,
                              child: Icon(Icons.image_not_supported_outlined, size: 18, color: PublicColors.forest.withValues(alpha: 0.45), semanticLabel: errorLabel),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// The built-in stand-in for an unpublished or unavailable image: soft
/// sage ground with Montessori-material-inspired circles. Decorative only
/// (it never pretends to be a photograph).
class PublicImagePlaceholder extends StatelessWidget {
  const PublicImagePlaceholder({super.key, this.compact = false});

  /// Fewer, smaller shapes for grid tiles.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Widget circle(double size, Color color) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        );
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final unit = (constraints.biggest.shortestSide.isFinite ? constraints.biggest.shortestSide : 200) / (compact ? 6 : 5);
          return DecoratedBox(
            key: const Key('public-image-placeholder'),
            decoration: const BoxDecoration(color: PublicColors.sageLight),
            child: Stack(
              children: [
                Positioned(top: unit * 0.4, left: unit * 0.4, child: circle(unit * 1.6, PublicColors.sage.withValues(alpha: 0.45))),
                Positioned(bottom: unit * 0.5, right: unit * 0.5, child: circle(unit * 1.1, PublicColors.goldLight)),
                Positioned(bottom: unit * 0.75, right: unit * 0.75, child: circle(unit * 0.55, PublicColors.gold.withValues(alpha: 0.6))),
              ],
            ),
          );
        },
      ),
    );
  }
}
