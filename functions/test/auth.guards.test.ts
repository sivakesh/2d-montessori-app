import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { HttpsError, type CallableRequest } from 'firebase-functions/v2/https';

import { assertCallerIsActiveSuperAdmin, assertRoleChangeAllowed, assertStatusChangeAllowed, requireAuthenticatedCaller } from '../src/auth/guards';

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

// A minimal fake `db` good enough to build a query object — the fake
// Transaction below never inspects it, since `Transaction.get(query)` is
// what actually returns data in these tests.
function fakeFirestoreForQuery(): Firestore {
  return {
    collection: () => ({
      where: () => ({
        where: () => 'fake-active-super-admin-query',
      }),
    }),
  } as unknown as Firestore;
}

function fakeTransactionWithActiveSuperAdminCount(count: number): Transaction {
  return {
    get: async () => ({ size: count }),
  } as unknown as Transaction;
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

describe('assertRoleChangeAllowed — last active Super Admin guard', () => {
  it('blocks demoting the only active Super Admin', async () => {
    await expect(
      assertRoleChangeAllowed(
        fakeTransactionWithActiveSuperAdminCount(1),
        fakeFirestoreForQuery(),
        { role: 'superAdmin', status: 'active' },
        'editor',
      ),
    ).rejects.toThrow(HttpsError);
  });

  it('allows demoting a Super Admin when another active one exists', async () => {
    await expect(
      assertRoleChangeAllowed(
        fakeTransactionWithActiveSuperAdminCount(2),
        fakeFirestoreForQuery(),
        { role: 'superAdmin', status: 'active' },
        'editor',
      ),
    ).resolves.toBeUndefined();
  });

  it('does not read Firestore at all when the target is not an active Super Admin', async () => {
    let read = false;
    const transaction = {
      get: async () => {
        read = true;
        throw new Error('should not be called');
      },
    } as unknown as Transaction;
    await expect(
      assertRoleChangeAllowed(transaction, fakeFirestoreForQuery(), { role: 'editor', status: 'active' }, 'publisher'),
    ).resolves.toBeUndefined();
    expect(read).toBe(false);
  });

  it('allows promoting a role (never blocked)', async () => {
    await expect(
      assertRoleChangeAllowed(
        fakeTransactionWithActiveSuperAdminCount(0),
        fakeFirestoreForQuery(),
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
        fakeTransactionWithActiveSuperAdminCount(1),
        fakeFirestoreForQuery(),
        { role: 'superAdmin', status: 'active' },
        'suspended',
      ),
    ).rejects.toThrow(HttpsError);
  });

  it('allows suspending a Super Admin when another active one exists', async () => {
    await expect(
      assertStatusChangeAllowed(
        fakeTransactionWithActiveSuperAdminCount(2),
        fakeFirestoreForQuery(),
        { role: 'superAdmin', status: 'active' },
        'suspended',
      ),
    ).resolves.toBeUndefined();
  });

  it('allows reactivating (never blocked)', async () => {
    await expect(
      assertStatusChangeAllowed(
        fakeTransactionWithActiveSuperAdminCount(0),
        fakeFirestoreForQuery(),
        { role: 'superAdmin', status: 'suspended' },
        'active',
      ),
    ).resolves.toBeUndefined();
  });
});
