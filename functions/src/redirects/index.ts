/**
 * Capability: redirects
 *
 * 301/302 redirect resolution, loop/conflict prevention, broken-link detection, hit counting.
 *
 * Traceability: SRS SEO-04
 *
 * Phase 0 scaffold only — no callable/trigger functions are exported yet.
 * Real implementations land per the milestone that owns this capability
 * (see /README.md "Implementation milestones"). Every exported function
 * added here must go through the shared audit helper in ../lib/audit.ts
 * and must never trust client-supplied role/permission claims without
 * re-verifying them server-side (SRS NFR-05).
 */

export const capability = 'redirects' as const;
