import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Section navigation on a public page: the page's sections register here
/// by anchor id ([PublicSectionAnchor]), and links scroll to them
/// ([scrollTo]) — `#enquire` on the same page, or the `#enquire` of the
/// address a page was opened at ([initialAnchor]), once that section has
/// been drawn (pages load their sections asynchronously).
///
/// The page's header scrolls with the page today; [headerOffset] is kept
/// clear above the section when scrolling (for a header that stays on
/// screen).
class PublicAnchorScope extends StatefulWidget {
  const PublicAnchorScope({super.key, this.initialAnchor, this.headerOffset = 0, required this.child});

  /// The section to show once it is drawn (from the page's address).
  final String? initialAnchor;
  final double headerOffset;
  final Widget child;

  /// The nearest scope, or null (e.g. the editor's canvas).
  static PublicAnchorScopeState? maybeOf(BuildContext context) => context.findAncestorStateOfType<PublicAnchorScopeState>();

  @override
  State<PublicAnchorScope> createState() => PublicAnchorScopeState();
}

class PublicAnchorScopeState extends State<PublicAnchorScope> {
  final _sections = <String, BuildContext>{};

  /// The anchor to scroll to as soon as its section is drawn.
  String? _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.initialAnchor;
  }

  /// The anchors of the sections drawn now.
  Set<String> get anchors => _sections.keys.toSet();

  /// Called by a section once drawn. The first section with an anchor
  /// keeps it (an anchor is never used twice on a page).
  void register(String anchor, BuildContext context) {
    _sections.putIfAbsent(anchor, () => context);
    if (_pending == anchor && identical(_sections[anchor], context)) {
      _pending = null;
      _scrollWhenLaidOut(anchor);
    }
  }

  void unregister(String anchor, BuildContext context) {
    if (identical(_sections[anchor], context)) _sections.remove(anchor);
  }

  /// Scrolls the page to the section with [anchor]; false when it isn't
  /// on the page (yet: it is shown once it is drawn).
  Future<bool> scrollTo(String anchor, {bool animate = true}) async {
    final section = _sections[anchor];
    if (section == null || !section.mounted) {
      _pending = anchor;
      return false;
    }
    _pending = null;
    final target = _offsetOf(section);
    if (target == null) return false;
    final (position, offset) = target;
    if (animate) {
      await position.animateTo(offset, duration: const Duration(milliseconds: 450), curve: Curves.easeInOutCubic);
    } else {
      position.jumpTo(offset);
    }
    return true;
  }

  /// Where the page scrolls to show [section] at its top, below
  /// [PublicAnchorScope.headerOffset].
  (ScrollPosition, double)? _offsetOf(BuildContext section) {
    final box = section.findRenderObject();
    final scrollable = Scrollable.maybeOf(section);
    if (box == null || !box.attached || scrollable == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    final position = scrollable.position;
    final reveal = viewport.getOffsetToReveal(box, 0).offset - widget.headerOffset;
    return (position, reveal.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble());
  }

  /// After this frame (the section is laid out), and once more after the
  /// next one (content above it, such as images, may still have settled).
  void _scrollWhenLaidOut(String anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollTo(anchor, animate: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _sections.containsKey(anchor)) scrollTo(anchor, animate: false);
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A page section with its anchor id: registered with the page's
/// [PublicAnchorScope] while drawn, so links can scroll to it. Keyed
/// `public-section-anchor-<anchor>`; the anchor is also the section's
/// semantics identifier.
class PublicSectionAnchor extends StatefulWidget {
  const PublicSectionAnchor({super.key, required this.anchor, required this.child});

  final String anchor;
  final Widget child;

  @override
  State<PublicSectionAnchor> createState() => _PublicSectionAnchorState();
}

class _PublicSectionAnchorState extends State<PublicSectionAnchor> {
  PublicAnchorScopeState? _scope;
  final _target = GlobalKey();

  /// The context registered with [_scope] (under [_registeredAnchor]).
  BuildContext? _registered;
  String? _registeredAnchor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  void _register() {
    if (!mounted) return;
    _unregister();
    _scope = PublicAnchorScope.maybeOf(context);
    final section = _target.currentContext;
    if (_scope == null || section == null) return;
    _registered = section;
    _registeredAnchor = widget.anchor;
    _scope!.register(widget.anchor, section);
  }

  void _unregister() {
    if (_registered case final section?) _scope?.unregister(_registeredAnchor!, section);
    _registered = null;
    _registeredAnchor = null;
  }

  @override
  void didUpdateWidget(PublicSectionAnchor old) {
    super.didUpdateWidget(old);
    if (old.anchor != widget.anchor) WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        key: _target,
        container: true,
        identifier: widget.anchor,
        child: KeyedSubtree(key: Key('public-section-anchor-${widget.anchor}'), child: widget.child),
      );
}
