import 'package:flutter/foundation.dart';

/// Size and count limits for a page's blocks, checked when saving and by
/// the editor's Add controls. The real constraint is the page document's
/// size (Firestore allows 1 MiB; [maxDocumentBytes] keeps well below it).
///
/// The page-wide block count ([maxBlocks]) is the school's own setting
/// (Website → Pages → Editor settings, `WebsiteEditorSettings`): it
/// defaults to [defaultPageMaxBlocks] and can be set from
/// [minPageMaxBlocks] to [safetyMaxBlocks]. Saving always checks the
/// safety ceiling ([safety]); the school's own limit stops a page from
/// growing past it (a page that already has more, after the limit was
/// lowered, can still be edited, rearranged, saved and published).
///
/// Every block counts once: top-level blocks, sections and columns blocks
/// themselves, and each block inside their columns; hidden blocks too
/// (they are kept in the draft).
///
/// There is no separate per-column limit by default: a column holds as
/// many blocks as the page has room for. [maxColumnBlocks] can still be
/// given (tests, or a future setting).
@immutable
class BlockLimits {
  const BlockLimits({
    this.maxBlocks = defaultPageMaxBlocks,
    this.maxNestingDepth = 2,
    int? maxColumnBlocks,
    this.maxDocumentBytes = 500 * 1024,
  }) : _maxColumnBlocks = maxColumnBlocks;

  /// The editor's limits when the school has set none.
  static const defaults = BlockLimits();

  /// What saving always checks, whatever the school's setting: the
  /// ceiling for the block count, nesting and the document size.
  static const safety = BlockLimits(maxBlocks: safetyMaxBlocks);

  /// The default page-wide limit: about 25 sections of five blocks. It
  /// was 40, an early cautious value, which a Home page made of sections
  /// reaches quickly (each section and each block in it counts).
  static const defaultPageMaxBlocks = 150;

  /// Kept for older callers: the default page-wide limit.
  static const pageMaxBlocks = defaultPageMaxBlocks;

  /// The lowest page limit a school can set: a page needs room for a few
  /// sections (each needs itself, a column block and a block inside).
  static const minPageMaxBlocks = 10;

  /// The highest page limit a school can set. A page's blocks are one
  /// Firestore document: with typical blocks 500 stays well within
  /// [maxDocumentBytes] (still checked on save), and the editor stays
  /// responsive.
  static const safetyMaxBlocks = 500;

  /// The page limit [maxBlocks] (the school's setting, or the default).
  factory BlockLimits.forPage(int maxBlocks) => BlockLimits(maxBlocks: maxBlocks);

  /// Blocks on a page, counting blocks inside columns.
  final int maxBlocks;

  /// How deep blocks may nest: 2 = a section's column may hold a Columns /
  /// Row block, whose columns hold content blocks. Which container may
  /// hold which is checked by the containers themselves; this is the
  /// backstop.
  final int maxNestingDepth;

  final int? _maxColumnBlocks;

  /// Blocks inside one column: the page limit unless a separate one is set.
  int get maxColumnBlocks => _maxColumnBlocks ?? maxBlocks;

  /// Whether columns have a limit of their own (below the page's).
  bool get hasColumnLimit => _maxColumnBlocks != null && _maxColumnBlocks < maxBlocks;

  /// The page's blocks, encoded as JSON (UTF-8 bytes).
  final int maxDocumentBytes;

  @override
  bool operator ==(Object other) =>
      other is BlockLimits &&
      other.maxBlocks == maxBlocks &&
      other.maxNestingDepth == maxNestingDepth &&
      other._maxColumnBlocks == _maxColumnBlocks &&
      other.maxDocumentBytes == maxDocumentBytes;

  @override
  int get hashCode => Object.hash(maxBlocks, maxNestingDepth, _maxColumnBlocks, maxDocumentBytes);
}
