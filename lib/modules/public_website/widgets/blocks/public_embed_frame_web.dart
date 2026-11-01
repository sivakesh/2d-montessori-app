// ignore_for_file: avoid_web_libraries_in_flutter
// ignore_for_file: deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';

const _viewType = 'website-embed-frame';
var _registered = false;

/// A provider's frame: an iframe at [src] (an address rebuilt by
/// EmbedSource, never one pasted), titled [title] for screen readers,
/// limited to [sandbox] and [allow], lazily loaded, sending only the
/// site's origin as referrer. Only the visitors' page creates one (the
/// editor shows a placeholder instead).
class PublicEmbedFrame extends StatelessWidget {
  const PublicEmbedFrame({super.key, required this.src, required this.title, required this.sandbox, required this.allow, required this.allowFullscreen});

  final Uri src;
  final String title;
  final List<String> sandbox;
  final List<String> allow;
  final bool allowFullscreen;

  static void _register() {
    if (_registered) return;
    _registered = true;
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId, {Object? params}) {
      final p = params is Map ? params : const {};
      final features = [...(p['allow'] as List? ?? const []).map((e) => '$e'), if (p['fullscreen'] == true) 'fullscreen'];
      final frame = html.IFrameElement()
        ..title = '${p['title'] ?? ''}'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..setAttribute('sandbox', (p['sandbox'] as List? ?? const []).map((e) => '$e').join(' '))
        ..setAttribute('allow', features.join('; '))
        ..setAttribute('loading', 'lazy')
        ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
      if (p['fullscreen'] == true) frame.allowFullscreen = true;
      // The address last, once every restriction is in place.
      frame.src = '${p['src'] ?? 'about:blank'}';
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    _register();
    return HtmlElementView(
      key: ValueKey('$src|${sandbox.join(' ')}|${allow.join(' ')}|$allowFullscreen'),
      viewType: _viewType,
      creationParams: {'src': src.toString(), 'title': title, 'sandbox': sandbox, 'allow': allow, 'fullscreen': allowFullscreen},
    );
  }
}
