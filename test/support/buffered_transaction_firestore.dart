// Test-only Firestore double whose transactions behave like real Firestore
// transactions, which fake_cloud_firestore's own runTransaction does not
// (it writes each txn.set immediately and never rolls back):
// - Writes are buffered and applied only when the handler completes.
// - Reads must happen before writes.
// - At commit, every document read in the transaction is re-read; if any
//   changed in the meantime the handler is re-run (optimistic concurrency,
//   up to maxAttempts), as Firestore does on contention.
// - Commits are serialised and all-or-nothing: an injected commit failure
//   applies none of the buffered writes.
// Failures can be injected on a read ([failReadWhen]) or at commit
// ([failCommitWhen]) by document path.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

class BufferedTransactionFirestore extends FakeFirebaseFirestore {
  bool Function(String path)? failReadWhen;
  bool Function(String path)? failCommitWhen;

  /// Number of transaction attempts made (including retries).
  int attempts = 0;

  // Created lazily in the caller's zone: a future created in setUp (the
  // real zone) would never deliver callbacks inside a testWidgets
  // fake-async zone, hanging the test.
  Future<void>? _commitLock;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    for (var attempt = 1; ; attempt++) {
      attempts++;
      final txn = _BufferedTransaction(this);
      final result = await transactionHandler(txn);
      final committed = await _commit(txn);
      if (committed) return result;
      if (attempt >= maxAttempts) {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'aborted', message: 'Transaction contention');
      }
    }
  }

  /// Returns false (nothing written) if a document read in [txn] changed
  /// since it was read, so the caller retries.
  Future<bool> _commit(_BufferedTransaction txn) {
    final completer = Completer<bool>();
    final previous = _commitLock ?? Future<void>.value();
    _commitLock = completer.future.then((_) {}, onError: (_) {});
    previous.whenComplete(() async {
      try {
        for (final entry in txn.reads.entries) {
          final now = (await doc(entry.key).get()).data();
          if (!_deepEquals(now, entry.value)) {
            completer.complete(false);
            return;
          }
        }
        for (final write in txn.writes) {
          if (failCommitWhen?.call(write.path) == true) {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Injected commit failure');
          }
        }
        for (final write in txn.writes) {
          await write.apply();
        }
        completer.complete(true);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}

class _Write {
  _Write(this.path, this.apply);
  final String path;
  final Future<void> Function() apply;
}

class _BufferedTransaction implements Transaction {
  _BufferedTransaction(this._db);

  final BufferedTransactionFirestore _db;
  final Map<String, Map<String, dynamic>?> reads = {};
  final List<_Write> writes = [];

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> documentReference) async {
    if (writes.isNotEmpty) {
      throw StateError('Firestore transactions require all reads to be executed before all writes');
    }
    if (_db.failReadWhen?.call(documentReference.path) == true) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'Injected read failure');
    }
    final snap = await documentReference.get();
    final raw = await _db.doc(documentReference.path).get();
    reads[documentReference.path] = raw.data() == null ? null : Map<String, dynamic>.from(raw.data()!);
    return snap;
  }

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    writes.add(_Write(documentReference.path, () => documentReference.set(data, options)));
    return this;
  }

  @override
  Transaction update(DocumentReference documentReference, Map<Object, Object?> data) {
    writes.add(_Write(documentReference.path, () => documentReference.update(data)));
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    writes.add(_Write(documentReference.path, () => documentReference.delete()));
    return this;
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
