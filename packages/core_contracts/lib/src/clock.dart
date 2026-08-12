/// Injectable clock so scheduling/versioning use cases (CMS-05, CMS-06) are
/// deterministically testable instead of calling `DateTime.now()` directly.
abstract class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Fixed-time clock for widget/use-case tests.
class FixedClock implements Clock {
  const FixedClock(this._fixed);

  final DateTime _fixed;

  @override
  DateTime now() => _fixed;
}
