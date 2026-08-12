import { capability as authCapability } from '../src/auth';
import { capability as enquiriesCapability } from '../src/enquiries';
import { capability as maintenanceCapability } from '../src/maintenance';
import { capability as mediaCapability } from '../src/media';
import { capability as publishingCapability } from '../src/publishing';
import { capability as redirectsCapability } from '../src/redirects';
import { capability as schedulingCapability } from '../src/scheduling';
import { capability as seoCapability } from '../src/seo';

// Smoke test: proves every capability module compiles and its barrel
// constant matches its folder name. This intentionally does NOT import
// src/index.ts, which calls admin.initializeApp() and needs a real (or
// emulated) Firebase environment — out of scope for a unit test.
//
// writeAuditEvent (src/lib/audit.ts) is no longer tested here: as of the
// Phase 1 Foundation milestone it writes to Firestore for real, so
// exercising it needs the emulator — see test/emulator/auth.functions.test.ts
// (authored but not executed in this environment; see README "Testing").
describe('Cloud Functions capability scaffold', () => {
  it.each([
    ['auth', authCapability],
    ['publishing', publishingCapability],
    ['media', mediaCapability],
    ['enquiries', enquiriesCapability],
    ['scheduling', schedulingCapability],
    ['redirects', redirectsCapability],
    ['seo', seoCapability],
    ['maintenance', maintenanceCapability],
  ])('%s capability exports its own name', (expected, actual) => {
    expect(actual).toBe(expected);
  });
});
