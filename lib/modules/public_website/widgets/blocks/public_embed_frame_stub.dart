import 'package:flutter/material.dart';

import '../../public_website_theme.dart';

/// Where the web shows a provider's frame (see the web version for what
/// each setting does): a placeholder with its [title] off the web (tests
/// and other platforms).
class PublicEmbedFrame extends StatelessWidget {
  const PublicEmbedFrame({super.key, required this.src, required this.title, required this.sandbox, required this.allow, required this.allowFullscreen});

  final Uri src;
  final String title;
  final List<String> sandbox;
  final List<String> allow;
  final bool allowFullscreen;

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const Key('public-embed-frame'),
        color: PublicColors.sageLight,
        child: Center(child: Text(title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: PublicText.body.copyWith(fontSize: 14))),
      );
}
