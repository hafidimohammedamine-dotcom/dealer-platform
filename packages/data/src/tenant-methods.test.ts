import { describe, expect, it } from 'vitest';
import { NotFoundError, TenantAccessError, type DataWhere } from './tenant-data.js';
import { fresh, helper, tenantClause } from './test-helpers/fake-api.js';

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

  it('find and count refuse a filter through a linked record, before Payload is called', async () => {
    const { data, calls } = await helper();
    const deep: DataWhere = { or: [{ 'tenant.name': { like: 'Dealer B' } }] };
    await expect(data.find('leads', { where: deep })).rejects.toThrow(TenantAccessError);
    await expect(
      data.count('leads', JSON.parse('{"customer":{"name":{"equals":"x"}}}')),
    ).rejects.toThrow(TenantAccessError);
    expect(calls).toEqual([]);
  });

  it('find passes a sort on one top-level field and refuses odd sorts and linked-record paths', async () => {
    const { data, calls } = await helper();
    await data.find('leads', { sort: 'tenant' });
    await data.find('leads', { sort: '-createdAt' });
    expect(calls[0]?.args).toMatchObject({ sort: 'tenant' });
    expect(calls[1]?.args).toMatchObject({ sort: '-createdAt' });
    // A dotted path would sort through a linked record (it is refused until the leak suite proves it safe).
    for (const sort of ['', '-', 'a b', 'a,b', '$where', 'a;drop', '--a', 'customer.name']) {
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
