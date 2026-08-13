/**
 * Capability: scheduling
 *
 * Idempotent scheduled-publish execution and retry/failure-state
 * handling for `content` docs in status `scheduled` (SRS CMS-05).
 * `publishJobs`-style per-job records are not needed for this: idempotency
 * and retry both fall directly out of re-checking each content
 * document's own status inside its own transaction — see
 * `publishScheduledContent.ts`'s doc comment for the full reasoning.
 *
 * Traceability: SRS CMS-05; PRD Section 9 ("trusted scheduled function
 * with idempotency and retry")
 *
 * `publishScheduledContent` (Phase 1 — CMS Core / feature_pages) is the
 * only real export so far. It targets `content` generically (any
 * `status == 'scheduled'` document, not Pages specifically), so it
 * benefits every future content type without changes. Every write here
 * goes through the same audit helper (`../lib/audit.ts`) as every other
 * module, using a fixed `system` actor identity rather than any
 * client-supplied claim, consistent with SRS NFR-05/NFR-07.
 */

export const capability = 'scheduling' as const;

export { publishScheduledContent, runScheduledPublish } from './publishScheduledContent';
export type { ScheduledPublishResult } from './publishScheduledContent';
