import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

import {
  assertCallerIsActiveSuperAdmin,
  assertRoleChangeAllowed,
  assertStatusChangeAllowed,
  countActiveSuperAdmins,
  requireAuthenticatedCaller,
} from '../src/auth/guards';

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

function fakeFirestoreWithActiveSuperAdminCount(count: number): Firestore {
  return {
    collection: () => ({
      where: () => ({
        where: () => ({ get: async () => ({ size: count }) }),
      }),
    }),
  } as unknown as Firestore;
}

describe('requireAuthenticatedCaller', () => {
  it('rejects unauthenticated requests', () => {
    expect(() => requireAuthenticatedCaller(fakeRequest(undefined))).toThrow(HttpsError);
  });

  it('extracts uid and role from the token claims', () => {
    const result = requireAuthenticatedCaller(fakeRequest({ uid: 'u1', token: { role: 'editor' } }));
    expect(result).toEqual({ uid: 'u1', role: 'editor' });
  });

  it('leaves role undefined when the claim is missing or not a string', () => {
    expect(requireAuthenticatedCaller(fakeRequest({ uid: 'u1', token: {} })).role).toBeUndefined();
    expect(requireAuthenticatedCaller(fakeRequest({ uid: 'u1', token: { role: 42 } })).role).toBeUndefined();
  });
});

describe('assertCallerIsActiveSuperAdmin', () => {
  it('rejects unauthenticated requests', async () => {
    await expect(assertCallerIsActiveSuperAdmin(fakeRequest(undefined), fakeFirestoreForUserDoc(undefined))).rejects.toThrow(
      HttpsError,
    );
  });

  it('rejects a caller without the superAdmin claim', async () => {
    const request = fakeRequest({ uid: 'u1', token: { role: 'publisher' } });
    await expect(assertCallerIsActiveSuperAdmin(request, fakeFirestoreForUserDoc({ status: 'active' }))).rejects.toThrow(
      HttpsError,
    );
  });

  it('rejects a superAdmin claim whose Firestore status is not active (stale-claim defense)', async () => {
    const request = fakeRequest({ uid: 'u1', token: { role: 'superAdmin' } });
    await expect(
      assertCallerIsActiveSuperAdmin(request, fakeFirestoreForUserDoc({ status: 'suspended' })),
    ).rejects.toThrow(HttpsError);
  });

  it('accepts an active superAdmin and returns their uid', async () => {
    const request = fakeRequest({ uid: 'u1', token: { role: 'superAdmin' } });
    await expect(assertCallerIsActiveSuperAdmin(request, fakeFirestoreForUserDoc({ status: 'active' }))).resolves.toBe(
      'u1',
    );
  });
});

describe('countActiveSuperAdmins', () => {
  it('returns the query size', async () => {
    await expect(countActiveSuperAdmins(fakeFirestoreWithActiveSuperAdminCount(3))).resolves.toBe(3);
  });
});

describe('assertRoleChangeAllowed — last active Super Admin guard', () => {
  it('blocks demoting the only active Super Admin', async () => {
    await expect(
      assertRoleChangeAllowed(
        fakeFirestoreWithActiveSuperAdminCount(1),
        { role: 'superAdmin', status: 'active' },
        'editor',
      ),
    ).rejects.toThrow(HttpsError);
  });

  it('allows demoting a Super Admin when another active one exists', async () => {
    await expect(
      assertRoleChangeAllowed(
        fakeFirestoreWithActiveSuperAdminCount(2),
        { role: 'superAdmin', status: 'active' },
        'editor',
      ),
    ).resolves.toBeUndefined();
  });

  it('does not query Firestore when the target is not an active Super Admin', async () => {
    let queried = false;
    const db = {
      collection: () => {
        queried = true;
        throw new Error('should not be called');
      },
    } as unknown as Firestore;
    await expect(assertRoleChangeAllowed(db, { role: 'editor', status: 'active' }, 'publisher')).resolves.toBeUndefined();
    expect(queried).toBe(false);
  });

  it('allows promoting a role (never blocked)', async () => {
    await expect(
      assertRoleChangeAllowed(
        fakeFirestoreWithActiveSuperAdminCount(0),
        { role: 'editor', status: 'active' },
        'superAdmin',
      ),
    ).resolves.toBeUndefined();
  });
});

describe('assertStatusChangeAllowed — last active Super Admin guard', () => {
  it('blocks suspending the only active Super Admin', async () => {
    await expect(
      assertStatusChangeAllowed(
        fakeFirestoreWithActiveSuperAdminCount(1),
        { role: 'superAdmin', status: 'active' },
        'suspended',
      ),
    ).rejects.toThrow(HttpsError);
  });

  it('allows suspending a Super Admin when another active one exists', async () => {
    await expect(
      assertStatusChangeAllowed(
        fakeFirestoreWithActiveSuperAdminCount(2),
        { role: 'superAdmin', status: 'active' },
        'suspended',
      ),
    ).resolves.toBeUndefined();
  });

  it('allows reactivating (never blocked)', async () => {
    await expect(
      assertStatusChangeAllowed(
        fakeFirestoreWithActiveSuperAdminCount(0),
        { role: 'superAdmin', status: 'suspended' },
        'active',
      ),
    ).resolves.toBeUndefined();
  });
});
