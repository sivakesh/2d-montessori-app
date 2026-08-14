/**
 * Locks in the three-way Cloud Functions region split documented in
 * docs/architecture/environments.md ("Cloud Functions region policy"):
 * Firestore trigger (asia-south1, matching the real Firestore
 * database's location), Storage trigger (us-east1, matching the real
 * `twod-montessori-dev.firebasestorage.app` bucket's confirmed
 * location), and every callable/scheduled Function (us-central1,
 * implicit SDK default). `firebase-functions` v2 attaches the resolved
 * deploy configuration to each export as `__endpoint` at module-
 * evaluation time — no Firestore/Storage/emulator call is involved, so
 * this is a plain, fast unit test, not an integration test. If this
 * test ever fails because a region moved, that reproduces exactly the
 * class of drift (an inferred/implicit region silently changing) the
 * explicit pins in `syncPublishedPage.ts` and `onMediaUploaded.ts`
 * exist to prevent.
 */
import { createPage } from '../src/pages/createPage';
import { onMediaUploaded } from '../src/media/onMediaUploaded';
import { syncPublishedPage } from '../src/pages/syncPublishedPage';
import { publishScheduledContent } from '../src/scheduling/publishScheduledContent';

function endpointOf(fn: unknown): {
  region?: string[];
  eventTrigger?: { eventType?: string; eventFilters?: { bucket?: string } };
} {
  return (fn as { __endpoint: { region?: string[]; eventTrigger?: { eventType?: string; eventFilters?: { bucket?: string } } } }).__endpoint;
}

describe('Cloud Functions region policy — the full three-way split', () => {
  it('pins the Storage trigger (onMediaUploaded) to us-east1, matching the real Storage bucket region', () => {
    const endpoint = endpointOf(onMediaUploaded);
    expect(endpoint.region).toEqual(['us-east1']);
    expect(endpoint.eventTrigger?.eventType).toBe('google.cloud.storage.object.v1.finalized');
  });

  it('leaves the Storage trigger targeting the project default bucket (no bucket hardcoded in source)', () => {
    // No explicit `bucket` option was passed to onObjectFinalized, so
    // this resolves from FIREBASE_CONFIG at module-load time (set by
    // firebase-tools/the real deploy to the project's actual default
    // bucket — see test/jest.setup.js for what this environment sets
    // it to, and onMediaUploaded.ts's own doc comment for why hardcoding
    // it here would be a regression, not a fix).
    const endpoint = endpointOf(onMediaUploaded);
    expect(endpoint.eventTrigger?.eventFilters?.bucket).toBeTruthy();
  });

  it('pins the Firestore trigger (syncPublishedPage) to asia-south1, matching the real Firestore database region', () => {
    const endpoint = endpointOf(syncPublishedPage);
    expect(endpoint.region).toEqual(['asia-south1']);
  });

  it('leaves callable and scheduled Functions on the implicit us-central1 SDK default', () => {
    expect(endpointOf(createPage).region).toBeUndefined();
    expect(endpointOf(publishScheduledContent).region).toBeUndefined();
  });
});
