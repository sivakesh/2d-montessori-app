import 'dart:math';

/// Stable ids for page-builder blocks and the items inside them. An id is
/// fixed for the life of its block or item — reordering never changes it —
/// so translations can address text by id instead of by list position.
class BlockIds {
  BlockIds._();

  /// Allowed in any id (new or legacy), so an id is always safe inside a
  /// translation path (which uses `/` as its separator).
  static final _valid = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Ids this app generates: a prefix (`b_` block, `i_` item, `c_`
  /// column, `r_` row) and 10 random base-36 characters.
  static final _generated = RegExp(r'^[bicr]_[a-z0-9]{10}$');

  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _random = Random.secure();

  static String _make(String prefix, Random random) =>
      '${prefix}_${String.fromCharCodes([for (var i = 0; i < 10; i++) _alphabet.codeUnitAt(random.nextInt(_alphabet.length))])}';

  /// A new block id. [random] replaces the secure generator (tests).
  static String block({Random? random}) => _make('b', random ?? _random);
  static String item({Random? random}) => _make('i', random ?? _random);
  static String column({Random? random}) => _make('c', random ?? _random);
  static String row({Random? random}) => _make('r', random ?? _random);

  /// A usable id: generated, legacy (e.g. a base-36 timestamp from the
  /// first custom-page sections) or derived (`<legacyId>__img`).
  static bool isValid(String id) => _valid.hasMatch(id);

  /// An id in the format this app generates.
  static bool isGenerated(String id) => _generated.hasMatch(id);
}
