import 'package:flutter/material.dart';

import '../../public_website_theme.dart';

/// Where the web shows the embedded map ([src]): a placeholder with its
/// [title], off the web (tests and other platforms).
class PublicMapFrame extends StatelessWidget {
  const PublicMapFrame({super.key, required this.src, required this.title, required this.interactive});

  final String src;
  final String title;

  /// Whether the map takes clicks (not in the editor).
  final bool interactive;

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const Key('public-map-frame'),
        color: PublicColors.sageLight,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, color: PublicColors.forest, size: 32),
                const SizedBox(height: 8),
                Text(title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: PublicText.body.copyWith(fontSize: 14)),
              ],
            ),
          ),
        ),
      );
}
