import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

import { assertActiveCaller } from '../src/publishing/guards';

function fakeRequest(auth: { uid: string; token: Record<string, unknown> } | undefined): CallableRequest<unknown> {
  return { data: undefined, auth, rawRequest: {} } as unknown as CallableRequest<unknown>;
}

function fakeFirestoreForUserDoc(data: Record<string, unknown> | undefined): Firestore {
  return {
    collection: () => ({
      doc: () => ({
        get: async () => ({ exists: data !== undefined, data: () => data }),
      }),
    }),
  } as unknown as Firestore;
}

describe('assertActiveCaller', () => {
  it('rejects an unauthenticated request', async () => {
    await expect(assertActiveCaller(fakeRequest(undefined), fakeFirestoreForUserDoc(undefined))).rejects.toThrow(
      HttpsError,
    );
  });

  it('rejects a caller with no valid role claim', async () => {
    const request = fakeRequest({ uid: 'u1', token: { role: 'owner' } });
    await expect(assertActiveCaller(request, fakeFirestoreForUserDoc({ status: 'active' }))).rejects.toThrow(
      HttpsError,
    );
  });

  it('rejects a caller whose Firestore status is not active (stale-claim defense)', async () => {
    const request = fakeRequest({ uid: 'u1', token: { role: 'editor' } });
    await expect(assertActiveCaller(request, fakeFirestoreForUserDoc({ status: 'suspended' }))).rejects.toThrow(
      HttpsError,
    );
  });

  it('accepts an active caller and returns their uid + role', async () => {
    const request = fakeRequest({ uid: 'u1', token: { role: 'publisher' } });
    await expect(assertActiveCaller(request, fakeFirestoreForUserDoc({ status: 'active' }))).resolves.toEqual({
      uid: 'u1',
      role: 'publisher',
    });
  });
});
