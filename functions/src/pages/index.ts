/**
 * Pages & Sections — Cloud Functions.
 *
 * Traceability: SRS WEB-01..WEB-03, CMS-01..CMS-15; PRD Section 4 (CMS
 * Page Builder), Section 5.1/5.2 (Page/SEO models)
 *
 * Reuses `../publishing`'s workflow engine (`applyTransition`,
 * `assertActiveCaller`) unmodified — see `transitionPage.ts`'s doc
 * comment. Every mutation here runs through Firestore Rules'
 * `content/{contentId}` deny-all-client-writes rule as the second layer
 * of defense behind these callables' own authorization checks, and every
 * privileged action writes an `auditLogs` entry via
 * `functions/src/lib/audit.ts`, matching every other module in this
 * codebase.
 */
export const capability = 'pages' as const;

export { createPage } from './createPage';
export { restorePageRevision } from './restorePageRevision';
export { syncPublishedPage } from './syncPublishedPage';
export { transitionPage } from './transitionPage';
export { updatePageContent } from './updatePageContent';
