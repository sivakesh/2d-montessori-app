/**
 * Capability: scheduling
 *
 * Idempotent scheduled-publish execution and retry/failure-state handling for publishJobs.
 *
 * Traceability: SRS CMS-05; PRD Section 9 ("trusted scheduled function with idempotency and retry")
 *
 * Phase 0 scaffold only — no callable/trigger functions are exported yet.
 * Real implementations land per the milestone that owns this capability
 * (see /README.md "Implementation milestones"). Every exported function
 * added here must go through the shared audit helper in ../lib/audit.ts
 * and must never trust client-supplied role/permission claims without
 * re-verifying them server-side (SRS NFR-05).
 */

export const capability = 'scheduling' as const;
