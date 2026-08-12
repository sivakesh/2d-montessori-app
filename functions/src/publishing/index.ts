/**
 * Capability: publishing
 *
 * Editorial workflow states, transitions, scheduling foundation and
 * audit trail — createDraft plus the single parameterized
 * transitionContent callable behind every named action.
 *
 * Traceability: SRS CMS-02, CMS-03, CMS-05, CMS-08; PRD Section 9
 * (Editorial Workflow and Versioning)
 *
 * Deployed/emulated as `publishingFns-<name>` per the grouped-export
 * naming in ../index.ts (`export * as publishingFns from './publishing'`).
 */
export const capability = 'publishing' as const;

export { createDraft } from './createDraft';
export * from './guards';
export * from './stateMachine';
export { transitionContent } from './transitionContent';
export * from './validators';
