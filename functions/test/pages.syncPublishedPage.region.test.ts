/**
 * Locks in the intentional Cloud Functions region split documented in
 * docs/architecture/environments.md ("Cloud Functions region policy"):
 * `pagesFns-syncPublishedPage` is the one Firestore trigger in this
 * codebase and must stay pinned to `asia-south1` (the real Dev
 * Firestore database's region — Eventarc requires a Firestore trigger
 * to be co-located with the database it watches), while `onCall`/
 * `onSchedule` Functions are left on the Firebase SDK's implicit
 * `us-central1` default rather than pinned in code.
 *
 * `firebase-functions`' v2 builders (`onDocumentWritten`, `onCall`, ...)
 * attach the resolved deploy configuration to the exported function as
 * `__endpoint` at module-evaluation time — no Firestore/Admin SDK call
 * or emulator is involved, so this is a plain, fast unit test, not an
 * integration test. If this test ever fails because `region` moved back
 * to `undefined`, that reproduces the exact packaging/region drift that
 * caused the original real-project deployment's asia-south1/us-central1
 * split to happen implicitly instead of intentionally.
 */
import { createPage } from '../src/pages/createPage';
import { syncPublishedPage } from '../src/pages/syncPublishedPage';

function endpointOf(fn: unknown): { region?: string[]; eventTrigger?: { eventType?: string } } {
  return (fn as { __endpoint: { region?: string[]; eventTrigger?: { eventType?: string } } }).__endpoint;
}

describe('Cloud Functions region policy', () => {
  it('pins the Firestore trigger (syncPublishedPage) to asia-south1, matching the real Dev Firestore database region', () => {
    const endpoint = endpointOf(syncPublishedPage);
    expect(endpoint.region).toEqual(['asia-south1']);
    expect(endpoint.eventTrigger?.eventType).toBe('google.cloud.firestore.document.v1.written');
  });

  it('leaves onCall Functions (e.g. createPage) on the implicit us-central1 default, not pinned in code', () => {
    const endpoint = endpointOf(createPage);
    expect(endpoint.region).toBeUndefined();
  });
});
