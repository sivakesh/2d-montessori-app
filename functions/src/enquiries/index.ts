/**
 * Capability: enquiries
 *
 * submitEnquiry (public callable, App-Check + validated + rate-limited), assign, export (Super Admin), permanent delete (Super Admin, confirmed).
 *
 * Traceability: SRS ENQ-01..ENQ-07 (approved Phase 1 module)
 *
 * Phase 0 scaffold only — no callable/trigger functions are exported yet.
 * Real implementations land per the milestone that owns this capability
 * (see /README.md "Implementation milestones"). Every exported function
 * added here must go through the shared audit helper in ../lib/audit.ts
 * and must never trust client-supplied role/permission claims without
 * re-verifying them server-side (SRS NFR-05).
 */

export const capability = 'enquiries' as const;
