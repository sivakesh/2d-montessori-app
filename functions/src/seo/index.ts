/**
 * Capability: seo
 *
 * sitemap.xml / robots.txt generation from published content.
 *
 * Traceability: SRS SEO-02; PRD FR-09
 *
 * Phase 0 scaffold only — no callable/trigger functions are exported yet.
 * Real implementations land per the milestone that owns this capability
 * (see /README.md "Implementation milestones"). Every exported function
 * added here must go through the shared audit helper in ../lib/audit.ts
 * and must never trust client-supplied role/permission claims without
 * re-verifying them server-side (SRS NFR-05).
 */

export const capability = 'seo' as const;
