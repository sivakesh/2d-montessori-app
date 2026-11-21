import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../public_website/content/website_content_models.dart';
import 'website_content_screen.dart' show WebsiteStatusChip;
import 'website_media_library.dart' show WebsiteMediaPicture, mediaTitle;

/// The order visitors see the public gallery in, as [gallery] (every image
/// marked for the gallery, in its saved order) and [draft] (the images
/// visitors see, in the order being arranged; null: the saved order).
///
/// Only images visitors can see (published, with consent confirmed) are
/// arranged; the others marked for the gallery keep their places
/// ([orderToSave]).
class WebsiteGalleryOrder {
  WebsiteGalleryOrder._();

  /// The images visitors see, in the saved order.
  static List<WebsiteMedia> shown(List<WebsiteMedia> gallery) => [
    for (final m in gallery)
      if (m.visibleToVisitors) m,
  ];

  /// The images marked for the gallery that visitors don't see yet.
  static List<WebsiteMedia> notShown(List<WebsiteMedia> gallery) => [
    for (final m in gallery)
      if (!m.visibleToVisitors) m,
  ];

  /// The full gallery order to store for [arranged] (the shown images, in
  /// their new order): each image visitors don't see keeps its place, and
  /// the places of the shown ones are filled in the new order.
  static List<String> orderToSave(List<WebsiteMedia> gallery, List<String> arranged) {
    final next = arranged.iterator;
    final shownIds = {for (final m in shown(gallery)) m.id};
    final out = <String>[];
    for (final m in gallery) {
      if (shownIds.contains(m.id) && next.moveNext()) {
        out.add(next.current);
      } else if (!shownIds.contains(m.id)) {
        out.add(m.id);
      }
    }
    // Anything left (never: [arranged] holds the shown images) goes last.
    while (next.moveNext()) {
      if (!out.contains(next.current)) out.add(next.current);
    }
    return out;
  }

  /// [draft] brought up to date with [gallery]: images no longer shown
  /// leave it, newly shown ones are added at the end; null when it is the
  /// saved order again.
  static List<String>? reconcile(List<WebsiteMedia> gallery, List<String>? draft) {
    if (draft == null) return null;
    final saved = [for (final m in shown(gallery)) m.id];
    final kept = [
      for (final id in draft)
        if (saved.contains(id)) id,
    ];
    final next = [
      ...kept,
      for (final id in saved)
        if (!kept.contains(id)) id,
    ];
    return _same(next, saved) ? null : next;
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// [order] with [id] moved to [to] (a position in the list without it).
  static List<String> move(List<String> order, String id, int to) {
    final next = [...order]..remove(id);
    next.insert(to.clamp(0, next.length), id);
    return next;
  }
}

/// Gallery order: arrange the order visitors see published images in.
/// Drag a card by its handle onto another card's place (the drop place is
/// marked); or, from the keyboard, Alt+↑/↓ on a focused card, or its Move
/// menu (up, down, first, last). Changes are kept as unsaved until Save
/// order; Discard changes goes back to the saved order. Preview shows the
/// gallery in the order being arranged.
///
/// Keys: `website-gallery-<id>` (a card), `-handle-<id>`, `-move-<id>`
/// (its menu) with `website-gallery-up-/down-/first-/last-<id>`,
/// `website-gallery-position-<id>`, `website-gallery-save`,
/// `website-gallery-discard`, `website-gallery-unsaved`,
/// `website-gallery-preview`, `website-gallery-not-shown-<id>`.
class WebsiteGalleryOrderTab extends StatefulWidget {
  const WebsiteGalleryOrderTab({super.key, required this.gallery, required this.draft, required this.saving, required this.onChanged, required this.onSave, required this.onDiscard});

  /// Every image marked for the gallery, in its saved order.
  final List<WebsiteMedia> gallery;

  /// The shown images' ids in the order being arranged (null: unchanged).
  final List<String>? draft;
  final bool saving;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  State<WebsiteGalleryOrderTab> createState() => _WebsiteGalleryOrderTabState();
}

class _WebsiteGalleryOrderTabState extends State<WebsiteGalleryOrderTab> {
  /// The card being dragged, and the place it would drop at.
  String? _dragging;
  int? _dropAt;

  List<WebsiteMedia> get _shown => WebsiteGalleryOrder.shown(widget.gallery);

  List<String> get _order => widget.draft ?? [for (final m in _shown) m.id];

  void _move(String id, int to) {
    final next = WebsiteGalleryOrder.move(_order, id, to);
    widget.onChanged(next);
  }

  Future<void> _preview(List<WebsiteMedia> ordered) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      key: const Key('website-gallery-preview-dialog'),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('Gallery preview', style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(key: const Key('website-gallery-preview-close'), tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.draft == null ? 'The gallery as visitors see it now.' : 'The gallery in the new order (not saved yet: visitors still see the saved order).',
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, c) {
                        final columns = c.maxWidth < 600 ? 2 : (c.maxWidth < 900 ? 3 : 4);
                        final w = (c.maxWidth - 8 * (columns - 1)) / columns;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, m) in ordered.indexed)
                              SizedBox(
                                key: Key('website-gallery-preview-$i'),
                                width: w,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: AspectRatio(aspectRatio: 1, child: WebsiteMediaPicture(media: m)),
                                    ),
                                    if (m.caption.en.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(m.caption.en.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final byId = {for (final m in widget.gallery) m.id: m};
    final ordered = [for (final id in _order) ?byId[id]];
    final notShown = WebsiteGalleryOrder.notShown(widget.gallery);
    final unsaved = widget.draft != null;
    return ListView(
      key: const Key('website-gallery-order'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Arrange the order visitors see published images.',
          key: Key('website-gallery-purpose'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Only published images appear in the public gallery. Drag a card by its handle to a new place, or use its Move menu (or Alt+↑/↓). '
          'Then Save order. This order is the public gallery’s only; it doesn’t change the Media library, albums or pages.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (unsaved) const WebsiteStatusChip(key: Key('website-gallery-unsaved'), label: 'Unsaved order', color: Color(0xFFB3261E)),
            FilledButton.icon(
              key: const Key('website-gallery-save'),
              onPressed: unsaved && !widget.saving ? widget.onSave : null,
              icon: widget.saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
              label: Text(widget.saving ? 'Saving…' : 'Save order'),
            ),
            OutlinedButton.icon(
              key: const Key('website-gallery-discard'),
              onPressed: unsaved && !widget.saving ? widget.onDiscard : null,
              icon: const Icon(Icons.undo),
              label: const Text('Discard changes'),
            ),
            TextButton.icon(
              key: const Key('website-gallery-preview'),
              onPressed: ordered.isEmpty ? null : () => _preview(ordered),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview gallery'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (ordered.isEmpty)
          const Padding(
            key: Key('website-gallery-empty'),
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No published gallery images yet. Images marked “In gallery” appear here once they are published (Media library).', textAlign: TextAlign.center),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 960 ? 3 : (constraints.maxWidth / 230).floor().clamp(4, 6));
              const gap = 12.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (i, m) in ordered.indexed)
                    SizedBox(
                      width: width,
                      child: _GalleryCard(
                        media: m,
                        position: i,
                        count: ordered.length,
                        dragging: _dragging == m.id,
                        dropHere: _dragging != null && _dragging != m.id && _dropAt == i,
                        onDragStart: () => setState(() => _dragging = m.id),
                        onDragEnd: () => setState(() {
                          _dragging = null;
                          _dropAt = null;
                        }),
                        onHover: (on) => setState(() => _dropAt = on ? i : (_dropAt == i ? null : _dropAt)),
                        onDrop: (id) {
                          final from = _order.indexOf(id);
                          // Dropped on a card: it takes that card's place.
                          if (from >= 0 && from != i) _move(id, i);
                          setState(() {
                            _dragging = null;
                            _dropAt = null;
                          });
                        },
                        onMove: (to) => _move(m.id, to),
                      ),
                    ),
                ],
              );
            },
          ),
        if (notShown.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('In the gallery, not shown to visitors yet (${notShown.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'These are marked for the gallery but aren’t published (or need consent confirmed). They keep their places; publish them in the Media library to arrange them here.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in notShown)
                SizedBox(
                  key: Key('website-gallery-not-shown-${m.id}'),
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: 0.6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: WebsiteMediaPicture(media: m),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      WebsiteStatusChip.forMedia(m.status),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One gallery image to arrange: its position, picture, title and status;
/// a drag handle, a drop target (marked while a card is over it), a Move
/// menu, and Alt+↑/↓ when focused.
class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.media,
    required this.position,
    required this.count,
    required this.dragging,
    required this.dropHere,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onHover,
    required this.onDrop,
    required this.onMove,
  });

  final WebsiteMedia media;
  final int position;
  final int count;
  final bool dragging;
  final bool dropHere;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<bool> onHover;
  final ValueChanged<String> onDrop;
  final ValueChanged<int> onMove;

  Widget _face(BuildContext context, {bool feedback = false}) {
    final title = mediaTitle(media);
    return Card(
      key: feedback ? null : Key('website-gallery-${media.id}'),
      margin: EdgeInsets.zero,
      color: AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: dropHere ? AppColors.primary : Colors.grey.shade300, width: dropHere ? 3 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: WebsiteMediaPicture(media: media),
              ),
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  key: feedback ? null : Key('website-gallery-position-${media.id}'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    '${position + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 0, 6),
            child: Row(
              children: [
                if (!feedback)
                  Draggable<String>(
                    key: Key('website-gallery-handle-${media.id}'),
                    data: media.id,
                    onDragStarted: onDragStart,
                    onDragEnd: (_) => onDragEnd(),
                    onDraggableCanceled: (_, _) => onDragEnd(),
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(width: 180, child: Opacity(opacity: 0.9, child: _face(context, feedback: true))),
                    ),
                    child: const Tooltip(
                      message: 'Drag to a new place',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.drag_indicator, color: Colors.grey),
                        ),
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.drag_indicator, color: Colors.grey),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      WebsiteStatusChip.forMedia(media.status),
                    ],
                  ),
                ),
                if (!feedback)
                  PopupMenuButton<int>(
                    key: Key('website-gallery-move-${media.id}'),
                    tooltip: 'Move',
                    icon: const Icon(Icons.more_vert),
                    onSelected: onMove,
                    itemBuilder: (context) => [
                      PopupMenuItem(key: Key('website-gallery-first-${media.id}'), value: 0, enabled: position > 0, child: const Text('Move to first')),
                      PopupMenuItem(key: Key('website-gallery-up-${media.id}'), value: position - 1, enabled: position > 0, child: const Text('Move up (earlier)')),
                      PopupMenuItem(key: Key('website-gallery-down-${media.id}'), value: position + 1, enabled: position < count - 1, child: const Text('Move down (later)')),
                      PopupMenuItem(key: Key('website-gallery-last-${media.id}'), value: count - 1, enabled: position < count - 1, child: const Text('Move to last')),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = mediaTitle(media);
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) {
        final ok = d.data != media.id;
        if (ok) onHover(true);
        return ok;
      },
      onLeave: (_) => onHover(false),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, _, _) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): _MoveIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): _MoveIntent(1),
          SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _MoveIntent(-1),
          SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): _MoveIntent(1),
        },
        child: Actions(
          actions: {
            _MoveIntent: CallbackAction<_MoveIntent>(
              onInvoke: (intent) {
                final to = position + intent.delta;
                if (to >= 0 && to < count) onMove(to);
                return null;
              },
            ),
          },
          child: Focus(
            key: Key('website-gallery-focus-${media.id}'),
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return Semantics(
                  label: 'Gallery position ${position + 1} of $count: $title. Alt and arrow keys move it.',
                  child: Opacity(
                    opacity: dragging ? 0.4 : 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: focused ? Border.all(color: AppColors.primary, width: 2) : null,
                      ),
                      child: GestureDetector(onTap: () => Focus.of(context).requestFocus(), child: _face(context)),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);
  final int delta;
}
