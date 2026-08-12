/**
 * Capability: publishing
 *
 * Transactional publish/unpublish/schedule/rollback: validates references, writes published* snapshot, version record, redirects and audit event atomically.
 *
 * Traceability: SRS CMS-02, CMS-05, CMS-06; PRD Section 9 (Editorial Workflow and Versioning)
 *
 * Phase 0 scaffold only — no callable/trigger functions are exported yet.
 * Real implementations land per the milestone that owns this capability
 * (see /README.md "Implementation milestones"). Every exported function
 * added here must go through the shared audit helper in ../lib/audit.ts
 * and must never trust client-supplied role/permission claims without
 * re-verifying them server-side (SRS NFR-05).
 */

export const capability = 'publishing' as const;
