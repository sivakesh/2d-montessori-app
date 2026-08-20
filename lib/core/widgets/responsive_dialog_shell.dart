import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';

/// Renders [child] as a full-screen `Scaffold` below
/// [AppSizes.mobileBreakpoint] and as today's fixed-size `Dialog` at or
/// above it. Generalizes the pattern already used by
/// AdminStudentViewDialog so a dialog doesn't have to hand-roll its own
/// mobile breakpoint check. [child] keeps its own title/scrolling/action
/// buttons exactly as before — only the outer chrome switches.
class ResponsiveDialogShell extends StatelessWidget {
  const ResponsiveDialogShell({
    super.key,
    required this.desktopWidth,
    this.desktopHeight,
    this.desktopInsetPadding = const EdgeInsets.all(24),
    required this.child,
  });

  /// Convenience form: builds the title-row + scrollable content +
  /// bottom-right action row wrapper (the shape most `AlertDialog(title:,
  /// content:, actions:)` dialogs already have) so callers only need to
  /// hand over their existing fields/buttons, not restructure them.
  factory ResponsiveDialogShell.form({
    Key? key,
    required double desktopWidth,
    double? desktopHeight,
    required String title,
    required Widget content,
    List<Widget> actions = const [],
    EdgeInsets contentPadding = const EdgeInsets.fromLTRB(20, 8, 20, 8),
  }) {
    return ResponsiveDialogShell(
      key: key,
      desktopWidth: desktopWidth,
      desktopHeight: desktopHeight,
      child: _FormDialogBody(
        title: title,
        content: content,
        actions: actions,
        contentPadding: contentPadding,
      ),
    );
  }

  final double desktopWidth;
  final double? desktopHeight;
  final EdgeInsets desktopInsetPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < AppSizes.mobileBreakpoint;

    if (isMobile) {
      return Scaffold(body: SafeArea(child: child));
    }

    return Dialog(
      insetPadding: desktopInsetPadding,
      child: SizedBox(
        width: desktopWidth,
        height: desktopHeight,
        child: child,
      ),
    );
  }
}

class _FormDialogBody extends StatelessWidget {
  const _FormDialogBody({
    required this.title,
    required this.content,
    required this.actions,
    required this.contentPadding,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: contentPadding,
            child: content,
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ),
      ],
    );
  }
}
