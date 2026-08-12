/**
 * Cloud Functions entrypoint. Re-exports each capability namespace so
 * `firebase deploy --only functions` and the emulator can discover them.
 * `authFns` (Phase 1 Foundation) and `publishingFns` (Phase 1 — CMS Core)
 * have real callables; the rest are still Phase 0 stubs — see
 * /README.md "Implementation milestones".
 */
import * as admin from 'firebase-admin';

admin.initializeApp();

export * as authFns from './auth';
export * as publishingFns from './publishing';
export * as mediaFns from './media';
export * as enquiriesFns from './enquiries';
export * as schedulingFns from './scheduling';
export * as redirectsFns from './redirects';
export * as seoFns from './seo';
export * as maintenanceFns from './maintenance';
