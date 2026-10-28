// ignore_for_file: avoid_web_libraries_in_flutter
// ignore_for_file: deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';

const _viewType = 'website-map-frame';
var _registered = false;

/// The embedded Google map ([src]) in an iframe titled [title] for screen
/// readers. In the editor ([interactive] false) it doesn't take clicks,
/// so the block can be selected and the page scrolled over it.
class PublicMapFrame extends StatelessWidget {
  const PublicMapFrame({super.key, required this.src, required this.title, required this.interactive});

  final String src;
  final String title;
  final bool interactive;

  static void _register() {
    if (_registered) return;
    _registered = true;
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId, {Object? params}) {
      final p = params is Map ? params : const {};
      return html.IFrameElement()
        ..src = '${p['src'] ?? ''}'
        ..title = '${p['title'] ?? ''}'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = p['interactive'] == true ? 'auto' : 'none'
        ..setAttribute('loading', 'lazy')
        ..setAttribute('referrerpolicy', 'no-referrer-when-downgrade')
        ..allowFullscreen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    _register();
    // A new frame whenever what it shows changes (the editor edits live).
    return HtmlElementView(
      key: ValueKey('$src|$interactive'),
      viewType: _viewType,
      creationParams: {'src': src, 'title': title, 'interactive': interactive},
    );
  }
}
