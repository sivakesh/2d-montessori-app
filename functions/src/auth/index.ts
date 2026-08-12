/**
 * Capability: auth
 *
 * User administration: createUser, resetAccess, suspend/reactivate, custom-claims (role) management.
 *
 * Traceability: SRS AUTH-01, AUTH-05; PRD Section 2 (Authorization must be enforced... via custom claims)
 *
 * Phase 0 scaffold only — no callable/trigger functions are exported yet.
 * Real implementations land per the milestone that owns this capability
 * (see /README.md "Implementation milestones"). Every exported function
 * added here must go through the shared audit helper in ../lib/audit.ts
 * and must never trust client-supplied role/permission claims without
 * re-verifying them server-side (SRS NFR-05).
 */

export const capability = 'auth' as const;
