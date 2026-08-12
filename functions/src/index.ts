/**
 * Cloud Functions entrypoint. Re-exports each capability namespace so
 * `firebase deploy --only functions` and the emulator can discover them.
 * No functions are exported yet — see /README.md "Implementation
 * milestones" for when each capability's real callables/triggers land.
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
