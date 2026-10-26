import 'package:flutter/foundation.dart';

/// Size and count limits for a page's blocks, checked when saving. The
/// defaults keep a page document well below Firestore's 1 MiB limit.
@immutable
class BlockLimits {
  const BlockLimits({
    this.maxBlocks = 40,
    this.maxNestingDepth = 1,
    this.maxColumnBlocks = 6,
    this.maxDocumentBytes = 500 * 1024,
  });

  static const defaults = BlockLimits();

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
