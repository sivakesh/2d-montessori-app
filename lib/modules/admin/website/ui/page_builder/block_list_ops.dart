import 'package:flutter/foundation.dart';

import '../../../../public_website/content/blocks/block_limits.dart';
import '../../../../public_website/content/blocks/block_registry.dart';
import '../../../../public_website/content/blocks/field_spec.dart';
import '../../../../public_website/content/blocks/website_block.dart';

/// Where a block is on a page: a top-level block ([index]), or block
/// [child] of column [column] of the top-level block [index]. Blocks are
/// addressed by position, not id: an unsupported block may have no id, or
/// share one.
@immutable
class BlockPath {
  const BlockPath(this.index) : column = null, child = null;
  const BlockPath.nested(this.index, int this.column, int this.child);

  final int index;
  final int? column;
  final int? child;

  bool get isNested => column != null;

  /// The top-level block this path is in (itself when not nested).
  BlockPath get topLevel => BlockPath(index);

  /// This position in its list.
  int get position => child ?? index;

  BlockPath _at(int position) => isNested ? BlockPath.nested(index, column!, position) : BlockPath(position);

  @override
  bool operator ==(Object other) => other is BlockPath && other.index == index && other.column == column && other.child == child;

  @override
  int get hashCode => Object.hash(index, column, child);

  @override
  String toString() => isNested ? 'BlockPath($index, $column, $child)' : 'BlockPath($index)';
}

/// Edits of a page's block list, as pure functions: each returns a new
/// list (blocks are immutable; untouched blocks are kept as they are, so
/// unknown fields and other languages are never lost) and, when the edit
/// moves or creates a block, where it now is. Blocks inside columns are
/// reached through the columns block's [ColumnsFieldSpec].
class BlockListOps {
  BlockListOps._();

  static String? _columnsKey(WebsiteBlock block) =>
      block is StructuredBlock ? block.definition.fields.whereType<ColumnsFieldSpec>().map((f) => f.key).firstOrNull : null;

  /// The columns of [block] (none for a block without columns).
  static List<BlockColumn> columnsOf(WebsiteBlock block) {
    final key = _columnsKey(block);
    return key == null ? const [] : (block as StructuredBlock).columns(key);
  }

  /// The block at [path], or null when there is none.
  static WebsiteBlock? at(List<WebsiteBlock> blocks, BlockPath path) {
    final list = _siblingsOrNull(blocks, path);
    return list == null || path.position < 0 || path.position >= list.length ? null : list[path.position];
  }

  /// The list [path] is in, or null when it doesn't exist.
  static List<WebsiteBlock>? _siblingsOrNull(List<WebsiteBlock> blocks, BlockPath path) {
    if (!path.isNested) return blocks;
    if (path.index < 0 || path.index >= blocks.length) return null;
    final cols = columnsOf(blocks[path.index]);
    return path.column! < 0 || path.column! >= cols.length ? null : cols[path.column!].blocks;
  }

  /// The list [path] is in.
  static List<WebsiteBlock> siblings(List<WebsiteBlock> blocks, BlockPath path) => _siblingsOrNull(blocks, path) ?? const [];

  /// [blocks] with the list [path] is in replaced by [list].
  static List<WebsiteBlock> _withSiblings(List<WebsiteBlock> blocks, BlockPath path, List<WebsiteBlock> list) {
    if (!path.isNested) return list;
    final parent = blocks[path.index] as StructuredBlock;
    final key = _columnsKey(parent)!;
    final cols = parent.columns(key);
    final next = [...cols]..[path.column!] = cols[path.column!].copyWith(blocks: list);
    return [...blocks]..[path.index] = parent.withValue(key, next);
  }

  static List<WebsiteBlock> replace(List<WebsiteBlock> blocks, BlockPath path, WebsiteBlock block) =>
      _withSiblings(blocks, path, [...siblings(blocks, path)]..[path.position] = block);

  /// [block] inserted at [path] (its position may be the list's length).
  static List<WebsiteBlock> insert(List<WebsiteBlock> blocks, BlockPath path, WebsiteBlock block) =>
      _withSiblings(blocks, path, [...siblings(blocks, path)]..insert(path.position, block));

  static List<WebsiteBlock> remove(List<WebsiteBlock> blocks, BlockPath path) =>
      _withSiblings(blocks, path, [...siblings(blocks, path)]..removeAt(path.position));

  /// The block at [path] moved [delta] places within its list, and its new
  /// path; unchanged when it can't move that far.
  static (List<WebsiteBlock>, BlockPath) move(List<WebsiteBlock> blocks, BlockPath path, int delta) {
    final list = [...siblings(blocks, path)];
    final to = path.position + delta;
    if (to < 0 || to >= list.length) return (blocks, path);
    final item = list.removeAt(path.position);
    list.insert(to, item);
    return (_withSiblings(blocks, path, list), path._at(to));
  }

  /// A copy of the block at [path] (fresh ids, nested blocks too) right
  /// after it, and the copy's path.
  static (List<WebsiteBlock>, BlockPath) duplicate(List<WebsiteBlock> blocks, BlockPath path) {
    final copy = BlockRegistry.duplicate(at(blocks, path)!);
    final to = path._at(path.position + 1);
    return (insert(blocks, to, copy), to);
  }

  /// The block at [path] shown or hidden (unsupported blocks unchanged).
  static List<WebsiteBlock> toggleHidden(List<WebsiteBlock> blocks, BlockPath path) {
    final block = at(blocks, path);
    return block is StructuredBlock ? replace(blocks, path, block.copyWith(hidden: !block.hidden)) : blocks;
  }

  /// Every block with its path, top-level blocks each followed by the
  /// blocks in their columns.
  static Iterable<(BlockPath, WebsiteBlock)> walk(List<WebsiteBlock> blocks) sync* {
    for (final (i, block) in blocks.indexed) {
      yield (BlockPath(i), block);
      for (final (c, column) in columnsOf(block).indexed) {
        for (final (j, child) in column.blocks.indexed) {
          yield (BlockPath.nested(i, c, j), child);
        }
      }
    }
  }

  /// Whether one more block fits on the page.
  static bool pageHasRoom(List<WebsiteBlock> blocks, {BlockLimits limits = BlockLimits.defaults}) =>
      BlockRegistry.flatten(blocks).length < limits.maxBlocks;

  /// Whether a block of [definition] can be added to column [column] of
  /// the top-level block [index]: never columns in columns, and only
  /// while the column and the page have room.
  static bool columnHasRoom(List<WebsiteBlock> blocks, int index, int column, {BlockLimits limits = BlockLimits.defaults}) {
    final cols = columnsOf(blocks[index]);
    return pageHasRoom(blocks, limits: limits) && column < cols.length && cols[column].blocks.length < limits.maxColumnBlocks;
  }

  /// Whether duplicating the block at [path] keeps the page within its
  /// limits (a copy counts its nested blocks too).
  static bool canDuplicate(List<WebsiteBlock> blocks, BlockPath path, {BlockLimits limits = BlockLimits.defaults}) {
    final block = at(blocks, path);
    if (block is! StructuredBlock) return false;
    final added = BlockRegistry.flatten([block]).length;
    if (BlockRegistry.flatten(blocks).length + added > limits.maxBlocks) return false;
    return !path.isNested || siblings(blocks, path).length < limits.maxColumnBlocks;
  }
}
