import 'package:flutter/foundation.dart';

/// Size and count limits for a page's blocks, checked when saving and by
/// the editor's Add controls. The real constraint is the page document's
/// size (Firestore allows 1 MiB; [maxDocumentBytes] keeps well below it);
/// the block count is a page-wide limit set high enough for long pages
/// ([pageMaxBlocks]), which the size check still bounds.
///
/// Every block counts once: top-level blocks, sections and columns blocks
/// themselves, and each block inside their columns; hidden blocks too
/// (they are kept in the draft).
@immutable
class BlockLimits {
  const BlockLimits({
    this.maxBlocks = pageMaxBlocks,
    this.maxNestingDepth = 1,
    this.maxColumnBlocks = 6,
    this.maxDocumentBytes = 500 * 1024,
  });

  static const defaults = BlockLimits();

  /// The page-wide block limit: about 25 sections of five blocks. It was
  /// 40, an early cautious value, which a Home page made of sections
  /// reaches quickly (each section and each block in it counts).
  static const pageMaxBlocks = 150;

  /// Blocks on a page, counting blocks inside columns.
  final int maxBlocks;

  /// How deep blocks may nest: 1 = a columns block may hold blocks, but
  /// not another columns block.
  final int maxNestingDepth;

  /// Blocks inside one column.
  final int maxColumnBlocks;

  /// The page's blocks, encoded as JSON (UTF-8 bytes).
  final int maxDocumentBytes;
}
