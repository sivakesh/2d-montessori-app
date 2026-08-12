/// Every workflow action the publishing state machine accepts. One
/// callable per action server-side (`functions/src/publishing/`) — see
/// that directory's `applyTransition.ts` for the shared logic they all
/// call through.
enum PublishingAction {
  submitForReview('submitForReview'),
  approve('approve'),
  reject('reject'),
  publish('publish'),
  unpublish('unpublish'),
  schedule('schedule'),
  unschedule('unschedule'),
  archive('archive'),
  restore('restore');

  const PublishingAction(this.storageValue);

  /// Persisted on each transition-history entry — must match
  /// `functions/src/publishing/stateMachine.ts`'s action strings exactly.
  final String storageValue;
}
