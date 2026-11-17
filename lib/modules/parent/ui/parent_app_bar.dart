import 'package:flutter/material.dart';

/// The Parent Dashboard's AppBar: the page title and the logout action.
///
/// Why it exists (Phase 0.2): the plain `AppBar(actions: [logout])` threw "A
/// RenderFlex overflowed … on the right" in the actions Row whenever the
/// browser viewport was narrower than about 60 px (for example Chrome with
/// DevTools docked at the side): AppBar lays its actions out in a Row that
/// can't shrink below the 48 px touch target. This bar measures the space it
/// gets and lays itself out accordingly:
/// - normally, the standard AppBar: title (one line, ellipsised) and a full
///   48 px logout button;
/// - when there isn't room for a back button, a title and the action
///   ([compactWidth]), the title and the action share the bar as flexible
///   children — the action keeps its full touch target whenever it fits and
///   is scaled down only when the bar is narrower than a single touch
///   target, so it is always visible and tappable and nothing overflows.
class ParentAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ParentAppBar({super.key, required this.title, required this.onLogout});

  final String title;
  final VoidCallback onLogout;

  static const logoutKey = Key('parent-appbar-logout');

  /// Below this width a leading button, a title and the logout action can't
  /// all keep their minimum size: two touch targets plus the toolbar's
  /// 16 px title spacing on each side.
  static const compactWidth = 2 * kMinInteractiveDimension + 32;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final logout = IconButton(key: logoutKey, tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: onLogout);
    final titleText = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= compactWidth) {
          return AppBar(centerTitle: false, title: titleText, actions: [logout]);
        }
        return AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              Expanded(child: Padding(padding: const EdgeInsets.only(left: 8), child: titleText)),
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: logout)),
            ],
          ),
        );
      },
    );
  }
}
