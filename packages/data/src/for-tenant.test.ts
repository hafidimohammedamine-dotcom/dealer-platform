import { describe, expect, it } from 'vitest';
import type { Payload } from 'payload';
import { forTenant } from './for-tenant.js';
import { TenantAccessError } from './tenant-data.js';
import { ctx, fakeApi, fresh, headers, loose } from './test-helpers/fake-api.js';

describe('forTenant: the user comes from Payload login, never from the caller', () => {
  it('asks Payload auth who the request headers belong to, and uses that user for every call', async () => {
    const fake = fakeApi();
    const data = await forTenant(fake.api, ctx);
    expect(fake.calls[0]).toEqual({ method: 'auth', args: { headers } });
    await data.count('leads');
    expect(fake.calls[1]?.args).toMatchObject({ user: fresh, overrideAccess: false });
  });

  it('cannot be handed a forged user: the context has no user, and extra fields are not read', async () => {
    // Security review round 3, finding 3: a caller object `{ id: <victim>, role: 'admin' }` used to be the identity
    // for the re-read. Now Payload's auth decides; with no valid login it returns no user, and the helper refuses.
    const forged = { ...ctx, user: { id: 99, role: 'admin', tenants: [{ tenant: 1 }] } };
    const fake = fakeApi([], null);
    await expect(forTenant(fake.api, forged)).rejects.toThrow(TenantAccessError);
    expect(fake.calls).toEqual([{ method: 'auth', args: { headers } }]);
  });

  it('refuses a user who is not in the dealer', async () => {
    const { api } = fakeApi();
    await expect(forTenant(api, { headers, tenantId: 2 })).rejects.toThrow(TenantAccessError);
  });

  it('refuses no login, a user with no dealers, another collection, a bad ID and a deactivated user', async () => {
    for (const found of [
      null,
      'x',
      { id: 10, collection: 'users' },
      { id: 10, collection: 'users', tenants: null },
      { id: 10, collection: 'customers', tenants: [{ tenant: 1 }] },
      { id: 10, tenants: [{ tenant: 1 }] },
      { id: '', collection: 'users', tenants: [{ tenant: 1 }] },
      { id: 10, collection: 'users', active: false, tenants: [{ tenant: 1 }] },
    ]) {
      const { api } = fakeApi([], found);
      await expect(forTenant(api, ctx), JSON.stringify(found)).rejects.toThrow(TenantAccessError);
    }
  });

  it('refuses an empty or null dealer ID before asking Payload anything', async () => {
    const { api, calls } = fakeApi();
    for (const tenantId of ['', '  ', null, undefined, Number.NaN, 1.5, {}]) {
      await expect(forTenant(api, { headers, tenantId: loose(tenantId) })).rejects.toThrow(
        TenantAccessError,
      );
    }
    expect(calls).toEqual([]);
  });

  it('matches string and number IDs, and populated tenant objects', async () => {
    const { api } = fakeApi();
    await expect(forTenant(api, { headers, tenantId: '1' })).resolves.toBeDefined();
    await expect(forTenant(api, { headers, tenantId: 'b' })).resolves.toBeDefined();
  });
});

describe('the real Payload instance fits the helper (type check only)', () => {
  it('compiles', () => {
    const compiles = (payload: Payload) => forTenant(payload, ctx);
    expect(typeof compiles).toBe('function');
  });
});
