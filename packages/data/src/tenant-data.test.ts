import { describe, expect, it } from 'vitest';
import type { Payload } from 'payload';
import {
  forTenant,
  NotFoundError,
  tenantIdsOf,
  TenantAccessError,
  type DataUser,
  type DataWhere,
  type TenantId,
  type LocalApi,
} from './tenant-data.js';

type Call = { method: string; args: object };

// The user as the database holds it (dealers 1 and "b"). The helper re-reads it by ID.
const stored = {
  id: 10,
  role: 'sales_rep',
  tenants: [{ tenant: 1 }, { tenant: { id: 'b' } }, { tenant: null }],
};

function fakeApi(docs: unknown[] = [], loaded: unknown = stored): { api: LocalApi; calls: Call[] } {
  const calls: Call[] = [];
  const api: LocalApi = {
    find: async (args) => {
      calls.push({ method: 'find', args });
      return { docs, totalDocs: docs.length };
    },
    findByID: async (args) => {
      calls.push({ method: 'findByID', args });
      return loaded;
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

// What the caller passes in: only the ID matters, the rest is read again from the database.
const user: DataUser = { id: 10 };
const ctx = { user, tenantId: 1 };
const tenantClause = { tenant: { equals: 1 } };
// Lets junk reach a typed parameter without a type assertion (the guard deliberately says yes to everything).
const anything = (value: unknown): value is TenantId => [value].length === 1;
function loose(value: unknown): TenantId {
  if (anything(value)) return value;
  throw new Error('unreachable');
}
const fresh = { ...stored, collection: 'users' };

async function helper(docs: unknown[] = []) {
  const fake = fakeApi(docs);
  const data = await forTenant(fake.api, ctx);
  fake.calls.length = 0; // forget the user lookup
  return { data, calls: fake.calls };
}

describe('tenantIdsOf', () => {
  it('reads strict IDs from ids and populated objects, and skips junk', () => {
    expect(
      tenantIdsOf({
        tenants: [
          { tenant: 'a' },
          { tenant: 2 },
          { tenant: { id: 'c' } },
          { tenant: { id: {} } },
          { tenant: '' },
          { tenant: '  ' },
          { tenant: 1.5 },
          { tenant: Number.NaN },
          { tenant: null },
          5,
          null,
        ],
      }),
    ).toEqual(['a', 2, 'c']);
    expect(tenantIdsOf({ tenants: 'x' })).toEqual([]);
    expect(tenantIdsOf({})).toEqual([]);
    expect(tenantIdsOf(undefined)).toEqual([]);
    expect(tenantIdsOf('x')).toEqual([]);
  });
});

describe('forTenant: the user is checked in the database', () => {
  it('loads the user by ID under its own access, and uses that record, not the caller object', async () => {
    const forged: DataUser = { id: 10, role: 'admin', tenants: [{ tenant: 99 }] };
    const fake = fakeApi();
    const data = await forTenant(fake.api, { user: forged, tenantId: 1 });
    expect(fake.calls[0]).toEqual({
      method: 'findByID',
      args: {
        collection: 'users',
        id: 10,
        user: forged,
        overrideAccess: false,
        depth: 0,
        draft: false,
        disableErrors: true,
      },
    });
    await data.count('leads');
    expect(fake.calls[1]?.args).toMatchObject({ user: fresh });
  });

  it('refuses a caller object that claims a dealer the database does not give the user', async () => {
    const { api } = fakeApi();
    const claim: DataUser = { id: 10, tenants: [{ tenant: 2 }] };
    await expect(forTenant(api, { user: claim, tenantId: 2 })).rejects.toThrow(TenantAccessError);
  });

  it('refuses a user who is not in the dealer', async () => {
    const { api } = fakeApi();
    await expect(forTenant(api, { user, tenantId: 2 })).rejects.toThrow(TenantAccessError);
  });

  it('refuses a user with no tenants, a missing user, another ID and a deactivated user', async () => {
    for (const loaded of [
      { id: 10 },
      { id: 10, tenants: null },
      null,
      'x',
      { id: 11, tenants: [{ tenant: 1 }] },
      { id: 10, active: false, tenants: [{ tenant: 1 }] },
    ]) {
      const { api } = fakeApi([], loaded);
      await expect(forTenant(api, ctx)).rejects.toThrow(TenantAccessError);
    }
  });

  it('refuses an empty or null dealer ID and an unusable user ID', async () => {
    const { api, calls } = fakeApi();
    for (const tenantId of ['', '  ', null, undefined, Number.NaN, 1.5, {}]) {
      await expect(forTenant(api, { user, tenantId: loose(tenantId) })).rejects.toThrow(
        TenantAccessError,
      );
    }
    await expect(forTenant(api, { user: { id: '' }, tenantId: 1 })).rejects.toThrow(
      TenantAccessError,
    );
    expect(calls).toEqual([]);
  });

  it('matches string and number IDs, and populated tenant objects', async () => {
    const { api } = fakeApi();
    await expect(forTenant(api, { user, tenantId: '1' })).resolves.toBeDefined();
    await expect(forTenant(api, { user, tenantId: 'b' })).resolves.toBeDefined();
  });
});

describe('forTenant: every call is locked to the user and the dealer', () => {
  it('find adds user, overrideAccess false, depth, draft, bounded limit, no page count and the tenant', async () => {
    const { data, calls } = await helper([{ id: 1 }]);
    const result = await data.find('leads');
    expect(result.docs).toHaveLength(1);
    expect(calls[0]?.args).toEqual({
      collection: 'leads',
      user: fresh,
      overrideAccess: false,
      depth: 0,
      draft: false,
      context: { tenantId: 1 },
      where: tenantClause,
      limit: 50,
      pagination: false,
    });
  });

  it('find can turn page counts on', async () => {
    const { data, calls } = await helper();
    await data.find('leads', { pagination: true });
    await data.find('leads', { pagination: false });
    expect(calls[0]?.args).toMatchObject({ pagination: true });
    expect(calls[1]?.args).toMatchObject({ pagination: false });
  });

  it('find keeps the caller filter but and-s the tenant, so another dealer gives nothing', async () => {
    const { data, calls } = await helper();
    const mine = { status: { equals: 'new' } };
    const theirs = { tenant: { equals: 2 } };
    const either: DataWhere = { or: [{ tenant: { equals: 2 } }, { status: { equals: 'new' } }] };
    await data.find('leads', { where: mine, sort: '-createdAt', page: 2, limit: 9999, depth: 2 });
    await data.find('leads', { where: theirs });
    await data.find('leads', { where: either });
    expect(calls[0]?.args).toMatchObject({
      where: { and: [mine, tenantClause] },
      sort: '-createdAt',
      page: 2,
      limit: 200,
      depth: 2,
      overrideAccess: false,
      draft: false,
    });
    expect(calls[1]?.args).toHaveProperty('where', { and: [theirs, tenantClause] });
    expect(calls[2]?.args).toHaveProperty('where', { and: [either, tenantClause] });
  });

  it('find passes a sort on any single field and refuses odd sorts', async () => {
    const { data, calls } = await helper();
    await data.find('leads', { sort: 'tenant' });
    await data.find('leads', { sort: 'customer.name' });
    expect(calls[0]?.args).toMatchObject({ sort: 'tenant' });
    expect(calls[1]?.args).toMatchObject({ sort: 'customer.name' });
    for (const sort of ['', '-', 'a b', 'a,b', '$where', 'a;drop', '-'.repeat(2) + 'a']) {
      await expect(data.find('leads', { sort })).rejects.toThrow(RangeError);
    }
  });

  it('findByID filters by id and tenant, and returns null when nothing matches', async () => {
    const { data, calls } = await helper();
    expect(await data.findByID('leads', 5)).toBeNull();
    expect(calls[0]?.args).toMatchObject({
      where: { and: [{ id: { equals: 5 } }, tenantClause] },
      limit: 1,
      pagination: false,
      overrideAccess: false,
      depth: 0,
      draft: false,
    });
    const found = await helper([{ id: 5 }]);
    expect(await found.data.findByID('leads', 5, { depth: 1 })).toEqual({ id: 5 });
  });

  it('count scopes to the tenant', async () => {
    const { data, calls } = await helper();
    expect(await data.count('leads')).toBe(7);
    await data.count('leads', { status: { equals: 'new' } });
    expect(calls[0]?.args).toEqual({
      collection: 'leads',
      where: tenantClause,
      user: fresh,
      overrideAccess: false,
      context: { tenantId: 1 },
    });
    expect(calls[1]?.args).toHaveProperty('where', {
      and: [{ status: { equals: 'new' } }, tenantClause],
    });
  });

  it('create forces the tenant and drops an id, even if the caller passes them', async () => {
    const { data, calls } = await helper();
    await data.create('leads', { name: 'A', tenant: 2, id: 77 });
    expect(calls[0]?.args).toMatchObject({
      data: { name: 'A', tenant: 1 },
      overrideAccess: false,
      user: fresh,
      depth: 0,
      draft: false,
    });
    expect(calls[0]?.args).toHaveProperty('data', { name: 'A', tenant: 1 });
  });

  it('update forces the tenant, drops an id and filters by id and tenant', async () => {
    const { data, calls } = await helper([{ id: 5 }]);
    expect(await data.update('leads', 5, { name: 'B', tenant: 2, id: 6 })).toEqual({ id: 5 });
    expect(calls[0]?.args).toMatchObject({
      where: { and: [{ id: { equals: 5 } }, tenantClause] },
      data: { name: 'B', tenant: 1 },
      overrideAccess: false,
      draft: false,
    });
    expect(calls[0]?.args).toHaveProperty('data', { name: 'B', tenant: 1 });
  });

  it('update and delete throw NotFoundError when nothing matches', async () => {
    const { data } = await helper();
    await expect(data.update('leads', 5, {})).rejects.toThrow(NotFoundError);
    await expect(data.delete('leads', 5)).rejects.toThrow(NotFoundError);
  });

  it('delete filters by id and tenant', async () => {
    const { data, calls } = await helper([{ id: 5 }]);
    expect(await data.delete('leads', 5)).toEqual({ id: 5 });
    expect(calls[0]?.args).toMatchObject({
      where: { and: [{ id: { equals: 5 } }, tenantClause] },
      overrideAccess: false,
      depth: 0,
      draft: false,
    });
  });
});

describe('forTenant: refusals', () => {
  it('refuses the dealers, users and payload-* collections on every method', async () => {
    const { data, calls } = await helper();
    for (const name of ['dealers', 'users', 'payload-locked-documents', 'payload-preferences']) {
      await expect(data.find(name)).rejects.toThrow(TenantAccessError);
      await expect(data.findByID(name, 1)).rejects.toThrow(TenantAccessError);
      await expect(data.count(name)).rejects.toThrow(TenantAccessError);
      await expect(data.create(name, {})).rejects.toThrow(TenantAccessError);
      await expect(data.update(name, 1, {})).rejects.toThrow(TenantAccessError);
      await expect(data.delete(name, 1)).rejects.toThrow(TenantAccessError);
    }
    expect(calls).toEqual([]);
  });

  it('every method returns a promise, so errors are always rejections', async () => {
    const { data } = await helper();
    const pending = data.find('leads', { depth: 3 });
    expect(pending).toBeInstanceOf(Promise);
    await expect(pending).rejects.toThrow(RangeError);
  });

  it('rejects a bad depth, limit or page (0, negative, NaN, Infinity, fractions)', async () => {
    const { data, calls } = await helper();
    const bad = [0, -1, Number.NaN, Number.POSITIVE_INFINITY, 0.5];
    for (const depth of [3, -1, 0.5, Number.NaN, Number.POSITIVE_INFINITY])
      await expect(data.find('leads', { depth })).rejects.toThrow(RangeError);
    for (const limit of [...bad, 1.5])
      await expect(data.find('leads', { limit })).rejects.toThrow(RangeError);
    for (const page of [...bad, 1_000_001])
      await expect(data.find('leads', { page })).rejects.toThrow(RangeError);
    await expect(data.findByID('leads', 1, { depth: 9 })).rejects.toThrow(RangeError);
    expect(calls).toEqual([]);
  });
});

describe('the real Payload instance fits the helper (type check only)', () => {
  it('compiles', () => {
    const compiles = (payload: Payload) => forTenant(payload, ctx);
    expect(typeof compiles).toBe('function');
  });
});
