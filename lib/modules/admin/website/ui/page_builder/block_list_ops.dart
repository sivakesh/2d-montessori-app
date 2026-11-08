import 'package:flutter/foundation.dart';

import '../../../../public_website/content/blocks/block_ids.dart';
import '../../../../public_website/content/blocks/block_limits.dart';
import '../../../../public_website/content/blocks/block_registry.dart';
import '../../../../public_website/content/blocks/field_spec.dart';
import '../../../../public_website/content/blocks/website_block.dart';

/// Where a block is on a page: a top-level block ([position] in the
/// page), or block [position] of column [column] of the container at
/// [parent] (a section or columns block at the top level, or a Columns /
/// Row inside a section's column: at most two levels). Blocks are
/// addressed by position, not id: an unsupported block may have no id, or
/// share one.
@immutable
class BlockPath {
  const BlockPath(this.index) : _c1 = null, _p1 = null, _c2 = null, _p2 = null;

  /// Block [child] of column [column] of the top-level block [index].
  const BlockPath.nested(this.index, int column, int child) : _c1 = column, _p1 = child, _c2 = null, _p2 = null;

  /// Block [innerChild] of column [innerColumn] of the row that is block
  /// [child] of column [column] of the top-level section [index].
  const BlockPath.inRow(this.index, int column, int child, int innerColumn, int innerChild) : _c1 = column, _p1 = child, _c2 = innerColumn, _p2 = innerChild;

  /// Block [position] of column [column] of the container at [parent]
  /// (at most two levels deep).
  factory BlockPath.inside(BlockPath parent, int column, int position) => switch (parent.depth) {
        0 => BlockPath.nested(parent.index, column, position),
        1 => BlockPath.inRow(parent.index, parent._c1!, parent._p1!, column, position),
        _ => throw ArgumentError('Blocks nest at most two levels deep.'),
      };

  /// The top-level block this path is in (its index in the page).
  final int index;
  final int? _c1, _p1, _c2, _p2;

  /// How many containers it is inside (0 at the top level, 2 in a row).
  int get depth => _c2 != null ? 2 : (_c1 != null ? 1 : 0);

  bool get isNested => _c1 != null;

  /// The container this block is in (null at the top level).
  BlockPath? get parent => switch (depth) { 0 => null, 1 => BlockPath(index), _ => BlockPath.nested(index, _c1!, _p1!) };

  /// The column of [parent] it is in (null at the top level).
  int? get column => _c2 ?? _c1;

  /// Its position in its column (null at the top level).
  int? get child => isNested ? position : null;

  /// This position in its list.
  int get position => _p2 ?? _p1 ?? index;

  /// The top-level block this path is in (itself when not nested).
  BlockPath get topLevel => BlockPath(index);

  /// Whether this is [other] or inside it.
  bool isWithin(BlockPath other) => this == other || (parent?.isWithin(other) ?? false);

  BlockPath _at(int position) => isNested ? BlockPath.inside(parent!, column!, position) : BlockPath(position);

  @override
  bool operator ==(Object other) => other is BlockPath && other.index == index && other._c1 == _c1 && other._p1 == _p1 && other._c2 == _c2 && other._p2 == _p2;

  @override
  int get hashCode => Object.hash(index, _c1, _p1, _c2, _p2);

  @override
  String toString() => switch (depth) { 0 => 'BlockPath($index)', 1 => 'BlockPath($index, $_c1, $_p1)', _ => 'BlockPath($index, $_c1, $_p1, $_c2, $_p2)' };
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
    final parent = at(blocks, path.parent!);
    if (parent == null) return null;
    final cols = columnsOf(parent);
    return path.column! < 0 || path.column! >= cols.length ? null : cols[path.column!].blocks;
  }

  /// The container [path] is in (null at the top level).
  static StructuredBlock? parentOf(List<WebsiteBlock> blocks, BlockPath path) {
    final parent = path.parent == null ? null : at(blocks, path.parent!);
    return parent is StructuredBlock ? parent : null;
  }

  /// The list [path] is in.
  static List<WebsiteBlock> siblings(List<WebsiteBlock> blocks, BlockPath path) => _siblingsOrNull(blocks, path) ?? const [];

  /// [blocks] with the list [path] is in replaced by [list].
  static List<WebsiteBlock> _withSiblings(List<WebsiteBlock> blocks, BlockPath path, List<WebsiteBlock> list) {
    if (!path.isNested) return list;
    final parent = at(blocks, path.parent!) as StructuredBlock;
    final key = _columnsKey(parent)!;
    final cols = parent.columns(key);
    final next = [...cols]..[path.column!] = cols[path.column!].copyWith(blocks: list);
    return replace(blocks, path.parent!, parent.withValue(key, next));
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

  /// Whether the block at [path] (inside a column) can move to column
  /// [column] of the same section or columns block: another column, with
  /// room for it.
  static bool canMoveToColumn(List<WebsiteBlock> blocks, BlockPath path, int column, {BlockLimits limits = BlockLimits.defaults}) {
    if (!path.isNested || column == path.column) return false;
    final cols = columnsOf(at(blocks, path.parent!)!);
    return column >= 0 && column < cols.length && cols[column].blocks.length < limits.maxColumnBlocks;
  }

  /// The block at [path] (inside a column) moved to the end of column
  /// [column] of the same section or columns block, unchanged (same id
  /// and content), and its new path; unchanged when [canMoveToColumn]
  /// says no.
  static (List<WebsiteBlock>, BlockPath) moveToColumn(List<WebsiteBlock> blocks, BlockPath path, int column, {BlockLimits limits = BlockLimits.defaults}) {
    if (!canMoveToColumn(blocks, path, column, limits: limits)) return (blocks, path);
    final item = at(blocks, path)!;
    final without = remove(blocks, path);
    final to = BlockPath.inside(path.parent!, column, columnsOf(at(without, path.parent!)!)[column].blocks.length);
    return (insert(without, to, item), to);
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

  /// Every block with its path, each container followed by the blocks in
  /// its columns (a row's by its own), depth first.
  static Iterable<(BlockPath, WebsiteBlock)> walk(List<WebsiteBlock> blocks) sync* {
    Iterable<(BlockPath, WebsiteBlock)> inside(BlockPath path, WebsiteBlock block) sync* {
      yield (path, block);
      for (final (c, column) in columnsOf(block).indexed) {
        for (final (j, child) in column.blocks.indexed) {
          yield* inside(BlockPath.inside(path, c, j), child);
        }
      }
    }

    for (final (i, block) in blocks.indexed) {
      yield* inside(BlockPath(i), block);
    }
  }

  /// Whether one more block fits on the page.
  static bool pageHasRoom(List<WebsiteBlock> blocks, {BlockLimits limits = BlockLimits.defaults}) =>
      BlockRegistry.flatten(blocks).length < limits.maxBlocks;

  /// Whether [block] (new: a section or block with everything inside it)
  /// fits on the page. A section or columns block with an empty column
  /// also needs room for one block in it, so it is never added when it
  /// couldn't be filled.
  static bool canInsert(List<WebsiteBlock> blocks, WebsiteBlock block, {BlockLimits limits = BlockLimits.defaults}) {
    final added = BlockRegistry.flatten([block]).length;
    final fill = columnsOf(block).any((c) => c.blocks.isEmpty) ? 1 : 0;
    return BlockRegistry.flatten(blocks).length + added + fill <= limits.maxBlocks;
  }

  /// Whether a new block of [definition] fits on the page ([canInsert]).
  static bool canAdd(List<WebsiteBlock> blocks, BlockDefinition definition, {BlockLimits limits = BlockLimits.defaults}) =>
      canInsert(blocks, BlockRegistry.create(definition), limits: limits);

  /// Whether a block of [definition] can be added to column [column] of
  /// the top-level block [index]: never columns in columns, and only
  /// while the column and the page have room.
  static bool columnHasRoom(List<WebsiteBlock> blocks, int index, int column, {BlockLimits limits = BlockLimits.defaults}) =>
      columnAtHasRoom(blocks, BlockPath(index), column, limits: limits);

  /// Whether one more block can be added to column [column] of the
  /// container at [container] (a section, columns block or row).
  static bool columnAtHasRoom(List<WebsiteBlock> blocks, BlockPath container, int column, {BlockLimits limits = BlockLimits.defaults}) {
    final parent = at(blocks, container);
    final cols = parent == null ? const <BlockColumn>[] : columnsOf(parent);
    return pageHasRoom(blocks, limits: limits) && column >= 0 && column < cols.length && cols[column].blocks.length < limits.maxColumnBlocks;
  }

  /// Whether [block] (new) can go at the end of column [column] of the
  /// container at [container]: a type that container may hold
  /// ([containerMayHold]: a Columns / Row only in a section), with room in
  /// the column and on the page ([canInsert]).
  static bool canInsertInColumn(List<WebsiteBlock> blocks, BlockPath container, int column, WebsiteBlock block, {BlockLimits limits = BlockLimits.defaults}) {
    final parent = at(blocks, container);
    return parent is StructuredBlock &&
        containerMayHold(parent.type, block) &&
        columnAtHasRoom(blocks, container, column, limits: limits) &&
        canInsert(blocks, block, limits: limits);
  }

  /// [block] added at the end of column [column] of the container at
  /// [container], and its path ([canInsertInColumn] must allow it).
  static (List<WebsiteBlock>, BlockPath) insertInColumn(List<WebsiteBlock> blocks, BlockPath container, int column, WebsiteBlock block) {
    final to = BlockPath.inside(container, column, columnsOf(at(blocks, container)!)[column].blocks.length);
    return (insert(blocks, to, block), to);
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

/// Column edits of a section or columns block, as pure functions. The
/// number of columns is the block's layout ([columnLayouts]), so adding,
/// removing or reordering columns also sets the layout; every column
/// that stays keeps its id and blocks. Blocks are never dropped unless
/// the caller asks: those of a removed column move into another column,
/// or go only with `deleteBlocks`.
class ColumnOps {
  ColumnOps._();

  static List<String> _layouts(StructuredBlock block) => (block.definition.field('layout') as ChoiceFieldSpec).options;

  /// The layout of [count] equal columns, if [block] offers it.
  static String? equalLayout(StructuredBlock block, int count) {
    final layout = List.filled(count, '1').join(':');
    return _layouts(block).contains(layout) ? layout : null;
  }

  /// The fewest and most columns [block] can have (a section 1 to 4, a
  /// columns block 2 to 4).
  static (int, int) range(StructuredBlock block) {
    final counts = [for (final l in _layouts(block)) columnLayouts[l]!.length];
    return (counts.reduce((a, b) => a < b ? a : b), counts.reduce((a, b) => a > b ? a : b));
  }

  static List<BlockColumn> _cols(StructuredBlock block) => block.columns('columns');

  /// A new, empty Columns / Row with [count] (1 to 4) equal columns.
  static StructuredBlock newRow(int count) {
    final row = BlockRegistry.create(BlockRegistry.row);
    return withLayout(row, equalLayout(row, count)!);
  }

  /// Whether column [from]'s blocks fit into column [into] (one column
  /// holds at most [BlockLimits.maxColumnBlocks]).
  static bool canMerge(StructuredBlock block, int from, int into, {BlockLimits limits = BlockLimits.defaults}) {
    final cols = _cols(block);
    return from != into && cols[from].blocks.length + cols[into].blocks.length <= limits.maxColumnBlocks;
  }

  /// The blocks in the columns layout [layout] would remove.
  static int blocksRemovedBy(StructuredBlock block, String layout) =>
      _cols(block).skip(columnLayouts[layout]!.length).fold(0, (n, c) => n + c.blocks.length);

  /// [block] with layout [layout]: the first columns kept, new empty ones
  /// added. The blocks of columns it removes are added, in order, to the
  /// end of column [moveInto] (one that is kept; default the last) when
  /// [moveBlocks]; otherwise there must be none.
  static StructuredBlock withLayout(StructuredBlock block, String layout, {bool moveBlocks = false, int? moveInto, BlockLimits limits = BlockLimits.defaults}) {
    final count = columnLayouts[layout]!.length;
    final cols = _cols(block);
    final removed = [for (final c in cols.skip(count)) ...c.blocks];
    if (removed.isNotEmpty && !moveBlocks) throw StateError('The columns removed hold blocks.');
    final kept = [...cols.take(count), for (var i = cols.length; i < count; i++) BlockColumn(id: BlockIds.column())];
    if (removed.isNotEmpty) {
      final into = moveInto ?? count - 1;
      if (into < 0 || into >= count) throw StateError('Column ${into + 1} isn’t kept.');
      final target = kept[into];
      if (target.blocks.length + removed.length > limits.maxColumnBlocks) throw StateError('The blocks don’t fit in that column.');
      kept[into] = target.copyWith(blocks: [...target.blocks, ...removed]);
    }
    return ColumnsPerRow.clampedTo(block.withValue('layout', layout).withValue('columns', kept), count);
  }

  /// The columns that would be kept by [layout] with room for the blocks
  /// it removes (indexes), when it removes any.
  static List<int> movableInto(StructuredBlock block, String layout, {BlockLimits limits = BlockLimits.defaults}) {
    final count = columnLayouts[layout]!.length;
    final moved = blocksRemovedBy(block, layout);
    final cols = _cols(block);
    return [for (var i = 0; i < count && i < cols.length; i++) if (cols[i].blocks.length + moved <= limits.maxColumnBlocks) i];
  }

  /// The equal layout of [count] columns, or [block]'s own when it already
  /// has that many (so a choice of count keeps its widths).
  static String layoutFor(StructuredBlock block, int count) =>
      _cols(block).length == count && columnLayouts[block.string('layout')]?.length == count ? block.string('layout') : equalLayout(block, count)!;

  /// [block] with an empty column added at the end; the columns become
  /// equal widths. Null when it has as many columns as it can.
  static StructuredBlock? withColumnAdded(StructuredBlock block) {
    final layout = equalLayout(block, _cols(block).length + 1);
    return layout == null ? null : withLayout(block, layout);
  }

  /// [block] without column [index]. Its blocks are added to the end of
  /// column [moveInto] (an index before the removal) or, when
  /// [deleteBlocks], removed with it; an empty column needs neither. The
  /// remaining columns keep their widths when a layout has them, else
  /// become equal. Null when [block] can't have fewer columns.
  static StructuredBlock? withColumnRemoved(StructuredBlock block, int index, {int? moveInto, bool deleteBlocks = false, BlockLimits limits = BlockLimits.defaults}) {
    final cols = [..._cols(block)];
    if (cols.length <= range(block).$1) return null;
    final removed = cols[index];
    if (removed.blocks.isNotEmpty && !deleteBlocks) {
      if (moveInto == null) throw StateError('The column holds blocks.');
      if (!canMerge(block, index, moveInto, limits: limits)) throw StateError('The blocks don’t fit in that column.');
      cols[moveInto] = cols[moveInto].copyWith(blocks: [...cols[moveInto].blocks, ...removed.blocks]);
    }
    cols.removeAt(index);
    final widths = [...?columnLayouts[block.string('layout')]];
    if (widths.length > index) widths.removeAt(index);
    final kept = widths.join(':');
    final layout = widths.length == cols.length && _layouts(block).contains(kept) ? kept : equalLayout(block, cols.length)!;
    return ColumnsPerRow.clampedTo(block.withValue('layout', layout).withValue('columns', cols), cols.length);
  }

  /// [block] with column [index] moved [delta] places (each column keeps
  /// its width: "wider right" becomes "wider left"); unchanged when it
  /// can't move that far.
  static StructuredBlock withColumnMoved(StructuredBlock block, int index, int delta) {
    final cols = [..._cols(block)];
    final to = index + delta;
    if (to < 0 || to >= cols.length) return block;
    cols.insert(to, cols.removeAt(index));
    final widths = [...?columnLayouts[block.string('layout')]];
    var layout = block.string('layout');
    if (widths.length == cols.length) {
      widths.insert(to, widths.removeAt(index));
      if (_layouts(block).contains(widths.join(':'))) layout = widths.join(':');
    }
    return block.withValue('layout', layout).withValue('columns', cols);
  }
}
