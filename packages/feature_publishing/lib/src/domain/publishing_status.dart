/// The editorial workflow states shared by every publishable content type
/// (pages, programs, experiences, articles, ...). Deliberately six states,
/// not the five in PRD §9's Page model (`draft | inReview | scheduled |
/// published | archived`) — this milestone adds `approved` as a distinct
/// checkpoint between review and scheduling/publishing, per the approved
/// Phase 1 — CMS Core scope; see docs/architecture/decisions.md
/// "Publishing workflow: six states, not five" for the reconciliation.
enum PublishingStatus {
  draft('draft'),
  inReview('inReview'),
  approved('approved'),
  scheduled('scheduled'),
  published('published'),
  archived('archived');

  const PublishingStatus(this.storageValue);

  /// The exact string persisted in Firestore's `status` field — must
  /// match `functions/src/publishing/stateMachine.ts`'s `PublishingStatus`
  /// values exactly (not code-shared — Dart vs TypeScript).
  final String storageValue;

  static PublishingStatus? fromStorageValue(String? value) {
    for (final status in PublishingStatus.values) {
      if (status.storageValue == value) return status;
    }
    return null;
  }
}
