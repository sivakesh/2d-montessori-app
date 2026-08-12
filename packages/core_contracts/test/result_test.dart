import 'package:core_contracts/core_contracts.dart';
import 'package:test/test.dart';

class _TestFailure extends Failure {
  const _TestFailure(super.message);
}

void main() {
  group('Result', () {
    test('Ok folds to the success branch', () {
      const result = Result<int>.ok(42);
      final value = result.fold((v) => v, (f) => -1);
      expect(value, 42);
      expect(result.isOk, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('Err folds to the failure branch', () {
      const result = Result<int>.failure(_TestFailure('boom'));
      final value = result.fold((v) => v, (f) => -1);
      expect(value, -1);
      expect(result.isFailure, isTrue);
    });
  });

  group('Page', () {
    test('carries items and cursor state', () {
      const page = Page<int>(
        items: [1, 2, 3],
        nextCursor: 'abc',
        hasMore: true,
      );
      expect(page.items, hasLength(3));
      expect(page.hasMore, isTrue);
    });
  });

  group('FixedClock', () {
    test('returns the fixed instant', () {
      final fixed = DateTime.utc(2026, 8, 12);
      final clock = FixedClock(fixed);
      expect(clock.now(), fixed);
    });
  });
}
