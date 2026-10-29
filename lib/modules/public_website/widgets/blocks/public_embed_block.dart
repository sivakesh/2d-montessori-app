import 'package:flutter/material.dart';

import '../../content/blocks/embed_providers.dart';
import '../../public_strings.dart';
import 'public_embed_frame.dart';

/// The styles an embed is drawn in (the block's look).
@immutable
class EmbedStyle {
  const EmbedStyle({required this.body, required this.muted, required this.accent, required this.line, required this.panel});

  final TextStyle body;
  final TextStyle muted;
  final Color accent;
  final Color line;

  /// Behind the placeholder.
  final Color panel;
}

/// An Embed block: the provider's frame at its shape or height, then the
/// caption and a link to the provider's own page. Visitors first see a
/// placeholder and load the frame with a click ([loadOnClick]); until
/// then nothing is fetched from the provider. In the editor
/// ([interactive] false) only the placeholder is drawn: no frame is
/// created there. Keys: `public-embed-<id>`, `-placeholder`, `-load`,
/// `-frame-area`, `-open`.
class PublicEmbedBlock extends StatefulWidget {
  const PublicEmbedBlock({
    super.key,
    required this.id,
    required this.source,
    required this.title,
    required this.caption,
    required this.shape,
    required this.height,
    required this.loadOnClick,
    required this.allowFullscreen,
    required this.language,
    required this.style,
    required this.interactive,
    this.onOpen,
  });

  final String id;

  /// A valid source ([EmbedSource.isValid]).
  final EmbedSource source;
  final String title;
  final String caption;

  /// `auto`, `16:9`, `4:3`, `1:1` or `fixed`.
  final String shape;

  /// `auto` or px.
  final String height;
  final bool loadOnClick;
  final bool allowFullscreen;
  final PublicLanguage language;
  final EmbedStyle style;
  final bool interactive;
  final ValueChanged<String>? onOpen;

  /// The frame's shape (width / height), or null for a fixed [frameHeight].
  static double? aspectOf(EmbedProvider provider, String shape) => switch (shape) {
        '16:9' => 16 / 9,
        '4:3' => 4 / 3,
        '1:1' => 1.0,
        'fixed' => null,
        _ => provider.aspect,
      };

  static double frameHeight(EmbedProvider provider, String height) => double.tryParse(height) ?? provider.height;

  @override
  State<PublicEmbedBlock> createState() => _PublicEmbedBlockState();
}

class _PublicEmbedBlockState extends State<PublicEmbedBlock> {
  bool _loaded = false;

  @override
  void didUpdateWidget(PublicEmbedBlock old) {
    super.didUpdateWidget(old);
    if (old.source.embedUrl != widget.source.embedUrl) _loaded = false;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final provider = w.source.provider!;
    final strings = PublicStrings.of(w.language);
    final showFrame = w.interactive && (!w.loadOnClick || _loaded);
    final Widget inner = showFrame
        ? Semantics(
            container: true,
            label: w.title,
            child: PublicEmbedFrame(
              src: w.source.embedUrl!,
              title: w.title,
              sandbox: provider.sandbox,
              allow: provider.allow,
              allowFullscreen: provider.fullscreen && w.allowFullscreen,
            ),
          )
        : _placeholder(provider, strings);
    final aspect = PublicEmbedBlock.aspectOf(provider, w.shape);
    final area = ClipRRect(
      key: Key('public-embed-${w.id}-frame-area'),
      borderRadius: BorderRadius.circular(16),
      child: aspect != null ? AspectRatio(aspectRatio: aspect, child: inner) : SizedBox(height: PublicEmbedBlock.frameHeight(provider, w.height), width: double.infinity, child: inner),
    );
    final open = w.source.openUrl;
    return Column(
      key: Key('public-embed-${w.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        area,
        if (w.caption.isNotEmpty) ...[const SizedBox(height: 8), Text(w.caption, style: w.style.muted)],
        if (open != null)
          TextButton.icon(
            key: Key('public-embed-${w.id}-open'),
            onPressed: w.interactive && w.onOpen != null ? () => w.onOpen!(open.toString()) : null,
            icon: Icon(Icons.open_in_new, size: 16, color: w.style.accent),
            label: Text(strings.embedOpen(provider.label)),
            style: TextButton.styleFrom(foregroundColor: w.style.accent, disabledForegroundColor: w.style.accent, padding: EdgeInsets.zero),
          ),
      ],
    );
  }

  Widget _placeholder(EmbedProvider provider, PublicStrings strings) {
    final w = widget;
    final icon = switch (provider.id) { 'google_forms' => Icons.assignment_outlined, 'google_calendar' => Icons.calendar_month_outlined, _ => Icons.play_circle_outline };
    return Container(
      key: Key('public-embed-${w.id}-placeholder'),
      color: w.style.panel,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 40, color: w.style.accent)),
              const SizedBox(height: 8),
              Text(w.title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: w.style.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(strings.embedLoadsFrom(provider.frameHost), textAlign: TextAlign.center, style: w.style.muted),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: strings.embedLoadFor(provider.label, w.title),
                excludeSemantics: true,
                child: FilledButton.icon(
                  key: Key('public-embed-${w.id}-load'),
                  onPressed: w.interactive ? () => setState(() => _loaded = true) : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(strings.embedLoad(provider.label)),
                  style: FilledButton.styleFrom(backgroundColor: w.style.accent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
