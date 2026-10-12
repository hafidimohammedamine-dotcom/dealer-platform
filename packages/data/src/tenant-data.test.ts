import { describe, expect, it } from 'vitest';
import type { Payload } from 'payload';
import {
  forTenant,
  NotFoundError,
  TenantAccessError,
  type DataUser,
  type LocalApi,
} from './tenant-data.js';

type Call = { method: string; args: object };

function fakeApi(docs: unknown[] = []): { api: LocalApi; calls: Call[] } {
  const calls: Call[] = [];
  const api: LocalApi = {
    find: async (args) => {
      calls.push({ method: 'find', args });
      return { docs, totalDocs: docs.length };
    },
    count: async (args) => {
      calls.push({ method: 'count', args });
      return { totalDocs: 7 };
    },
    create: async (args) => {
      calls.push({ method: 'create', args });
      return { id: 1 };
    },
    update: async (args) => {
      calls.push({ method: 'update', args });
      return { docs };
    },
    delete: async (args) => {
      calls.push({ method: 'delete', args });
      return { docs };
    },
  };
  return { api, calls };
}

const user: DataUser = {
  id: 10,
  collection: 'users',
  tenants: [{ tenant: 1 }, { tenant: { id: 'b' } }, { tenant: null }],
};
const ctx = { user, tenantId: 1 };
const tenantClause = { tenant: { equals: 1 } };

describe('forTenant: membership', () => {
  it('refuses a user who is not in the dealer', () => {
    const { api } = fakeApi();
    expect(() => forTenant(api, { user, tenantId: 2 })).toThrow(TenantAccessError);
  });

  it('refuses a user with no tenants at all', () => {
    const { api } = fakeApi();
    expect(() => forTenant(api, { user: { id: 1 }, tenantId: 1 })).toThrow(TenantAccessError);
    expect(() => forTenant(api, { user: { id: 1, tenants: null }, tenantId: 1 })).toThrow(
      TenantAccessError,
    );
  });

  it('matches string and number IDs, and populated tenant objects', () => {
    const { api } = fakeApi();
    expect(() => forTenant(api, { user, tenantId: '1' })).not.toThrow();
    expect(() => forTenant(api, { user, tenantId: 'b' })).not.toThrow();
  });
});

describe('forTenant: every call is locked to the user and the dealer', () => {
  it('find adds user, overrideAccess false, depth, bounded limit and the tenant', async () => {
    const { api, calls } = fakeApi([{ id: 1 }]);
    const result = await forTenant(api, ctx).find('leads');
    expect(result.docs).toHaveLength(1);
    expect(calls[0]?.args).toEqual({
      collection: 'leads',
      user,
      overrideAccess: false,
      depth: 0,
      context: { tenantId: 1 },
      where: tenantClause,
      limit: 50,
      pagination: true,
    });
  });

  it('find keeps the caller filter but and-s the tenant, so another dealer gives nothing', async () => {
    const { api, calls } = fakeApi();
    const mine = { status: { equals: 'new' } };
    const theirs = { tenant: { equals: 2 } };
    await forTenant(api, ctx).find('leads', {
      where: mine,
      sort: '-createdAt',
      page: 2,
      limit: 9999,
      depth: 2,
    });
    await forTenant(api, ctx).find('leads', { where: theirs });
    expect(calls[0]?.args).toMatchObject({
      where: { and: [mine, tenantClause] },
      sort: '-createdAt',
      page: 2,
      limit: 200,
      depth: 2,
      overrideAccess: false,
    });
    expect(calls[1]?.args).toHaveProperty('where', { and: [theirs, tenantClause] });
  });

  it('findByID filters by id and tenant, and returns null when nothing matches', async () => {
    const { api, calls } = fakeApi();
    expect(await forTenant(api, ctx).findByID('leads', 5)).toBeNull();
    expect(calls[0]?.args).toMatchObject({
      where: { and: [{ id: { equals: 5 } }, tenantClause] },
      limit: 1,
      pagination: false,
      overrideAccess: false,
      depth: 0,
    });
    const found = fakeApi([{ id: 5 }]);
    expect(await forTenant(found.api, ctx).findByID('leads', 5, { depth: 1 })).toEqual({ id: 5 });
  });

  it('count scopes to the tenant', async () => {
    const { api, calls } = fakeApi();
    expect(await forTenant(api, ctx).count('leads')).toBe(7);
    await forTenant(api, ctx).count('leads', { status: { equals: 'new' } });
    expect(calls[0]?.args).toEqual({
      collection: 'leads',
      where: tenantClause,
      user,
      overrideAccess: false,
      context: { tenantId: 1 },
    });
    expect(calls[1]?.args).toHaveProperty('where', {
      and: [{ status: { equals: 'new' } }, tenantClause],
    });
  });

  it('create forces the tenant, even if the caller passes another one', async () => {
    const { api, calls } = fakeApi();
    await forTenant(api, ctx).create('leads', { name: 'A', tenant: 2 });
    expect(calls[0]?.args).toMatchObject({
      data: { name: 'A', tenant: 1 },
      overrideAccess: false,
      user,
      depth: 0,
    });
  });

  it('update forces the tenant and filters by id and tenant', async () => {
    const { api, calls } = fakeApi([{ id: 5 }]);
    expect(await forTenant(api, ctx).update('leads', 5, { name: 'B', tenant: 2 })).toEqual({
      id: 5,
    });
    expect(calls[0]?.args).toMatchObject({
      where: { and: [{ id: { equals: 5 } }, tenantClause] },
      data: { name: 'B', tenant: 1 },
      overrideAccess: false,
    });
  });

  it('update and delete throw NotFoundError when nothing matches', async () => {
    const { api } = fakeApi();
    await expect(forTenant(api, ctx).update('leads', 5, {})).rejects.toThrow(NotFoundError);
    await expect(forTenant(api, ctx).delete('leads', 5)).rejects.toThrow(NotFoundError);
  });

  it('delete filters by id and tenant', async () => {
    const { api, calls } = fakeApi([{ id: 5 }]);
    expect(await forTenant(api, ctx).delete('leads', 5)).toEqual({ id: 5 });
    expect(calls[0]?.args).toMatchObject({
      where: { and: [{ id: { equals: 5 } }, tenantClause] },
      overrideAccess: false,
      depth: 0,
    });
  });
});

describe('forTenant: refusals', () => {
  it('refuses the dealers, users and payload-* collections on every method', async () => {
    const { api, calls } = fakeApi();
    const data = forTenant(api, ctx);
    for (const name of ['dealers', 'users', 'payload-locked-documents', 'payload-preferences']) {
      await expect(async () => data.find(name)).rejects.toThrow(TenantAccessError);
      await expect(data.findByID(name, 1)).rejects.toThrow(TenantAccessError);
      await expect(data.count(name)).rejects.toThrow(TenantAccessError);
      await expect(async () => data.create(name, {})).rejects.toThrow(TenantAccessError);
      await expect(data.update(name, 1, {})).rejects.toThrow(TenantAccessError);
      await expect(data.delete(name, 1)).rejects.toThrow(TenantAccessError);
    }
    expect(calls).toEqual([]);
  });

  it('rejects a bad depth or limit', () => {
    const { api } = fakeApi();
    const data = forTenant(api, ctx);
    expect(() => data.find('leads', { depth: 3 })).toThrow(RangeError);
    expect(() => data.find('leads', { depth: -1 })).toThrow(RangeError);
    expect(() => data.find('leads', { depth: 0.5 })).toThrow(RangeError);
    expect(() => data.find('leads', { limit: 0 })).toThrow(RangeError);
    expect(() => data.find('leads', { limit: 1.5 })).toThrow(RangeError);
  });
});

describe('the real Payload instance fits the helper (type check only)', () => {
  it('compiles', () => {
    const compiles = (payload: Payload) => forTenant(payload, ctx);
    expect(typeof compiles).toBe('function');
  });
});
