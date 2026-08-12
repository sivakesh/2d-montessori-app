/**
 * Capability: auth
 *
 * User administration: createUser, setUserRole, setUserStatus,
 * resetUserPassword, completeFirstLogin, and the shared authorization
 * guards/validators they use.
 *
 * Traceability: SRS AUTH-01, AUTH-03, AUTH-05; PRD Section 2
 * (Authorization must be enforced via custom claims)
 *
 * Deployed/emulated as `authFns-<name>` per the grouped-export naming in
 * ../index.ts (`export * as authFns from './auth'`).
 */
export const capability = 'auth' as const;

export { completeFirstLogin } from './completeFirstLogin';
export { createUser } from './createUser';
export * from './guards';
export { resetUserPassword } from './resetUserPassword';
export { setUserRole } from './setUserRole';
export { setUserStatus } from './setUserStatus';
export * from './validators';
