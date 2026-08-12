/**
 * Capability: maintenance
 *
 * Recycle-bin retention purge, backup verification hooks, scheduled housekeeping.
 *
 * Traceability: SRS CMS-11; PRD Section 17 (Release and Operations)
 *
 * Phase 0 scaffold only — no callable/trigger functions are exported yet.
 * Real implementations land per the milestone that owns this capability
 * (see /README.md "Implementation milestones"). Every exported function
 * added here must go through the shared audit helper in ../lib/audit.ts
 * and must never trust client-supplied role/permission claims without
 * re-verifying them server-side (SRS NFR-05).
 */

export const capability = 'maintenance' as const;
