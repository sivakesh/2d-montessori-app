import 'package:flutter/widgets.dart';

import '../breakpoints.dart';

/// Resolves the current [ViewportToken] from [MediaQuery] and rebuilds only
/// when the token changes — the single place responsive layout decisions
/// should branch on width, per PRD §3.2 ("Responsive decisions live in the
/// design-system and template contracts, not as page-specific magic
/// numbers").
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ViewportToken viewport) builder;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final viewport = Breakpoints.tokenForWidth(width);
    return builder(context, viewport);
  }
}
