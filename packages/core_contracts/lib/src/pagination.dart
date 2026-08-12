import 'package:meta/meta.dart';

/// Cursor-based pagination only — the PRD (§12.1) explicitly forbids large
/// offset scans against Firestore, so no `page`/`offset` field exists here
/// by design.
@immutable
class Page<T> {
  const Page({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
}

@immutable
class PageRequest {
  const PageRequest({this.cursor, this.limit = 20})
    : assert(limit > 0 && limit <= 100, 'limit must be within 1..100');

  final String? cursor;
  final int limit;
}
