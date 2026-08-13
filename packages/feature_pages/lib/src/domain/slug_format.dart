/// PRD §5: "Slugs are lowercase ASCII with hyphens." Shared by the client
/// completeness/edit validators and mirrored server-side in
/// `functions/src/pages/validators.ts` (hand-synced, not code-shared,
/// same convention `feature_publishing`'s state machine already uses
/// between Dart and TypeScript).
final RegExp slugFormatPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

bool isValidSlugFormat(String slug) => slugFormatPattern.hasMatch(slug);
