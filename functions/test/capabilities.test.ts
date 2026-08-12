import { capability as authCapability } from '../src/auth';
import { capability as enquiriesCapability } from '../src/enquiries';
import { capability as maintenanceCapability } from '../src/maintenance';
import { capability as mediaCapability } from '../src/media';
import { capability as publishingCapability } from '../src/publishing';
import { capability as redirectsCapability } from '../src/redirects';
import { capability as schedulingCapability } from '../src/scheduling';
import { capability as seoCapability } from '../src/seo';
import { writeAuditEvent } from '../src/lib/audit';

// Phase 0 smoke test: proves every capability module compiles and its
// barrel constant matches its folder name. This intentionally does NOT
// import src/index.ts, which calls admin.initializeApp() and needs a real
// (or emulated) Firebase environment — out of scope for a unit test.
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

  it('writeAuditEvent resolves without throwing (Phase 0 no-op)', async () => {
    await expect(
      writeAuditEvent({
        eventType: 'create',
        entityType: 'test',
        entityId: 'test-1',
        actorId: 'test-actor',
        actorRole: 'superAdmin',
        requestId: 'req-1',
        source: 'function',
      }),
    ).resolves.toBeUndefined();
  });
});
