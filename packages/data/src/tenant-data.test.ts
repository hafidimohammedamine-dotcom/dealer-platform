import { describe, expect, it } from 'vitest';
import type { DataWhere } from './tenant-data.js';
import {
  flatWhere,
  isRecord,
  sortOf,
  TenantAccessError,
  tenantIdsOf,
  wherePaths,
} from './tenant-data.js';

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

describe('isRecord', () => {
  it('is true for objects and arrays only', () => {
    expect([{}, [], new Headers()].every(isRecord)).toBe(true);
    expect([null, undefined, 'x', 1].some(isRecord)).toBe(false);
  });
});

describe('wherePaths and flatWhere: no filtering through a linked record', () => {
  it('lists every path, inside and/or at any depth and in both spellings', () => {
    expect(
      wherePaths({
        status: { equals: 'new' },
        or: [{ 'customer.name': { like: 'a' } }, { and: [{ rep: { name: { equals: 'b' } } }] }],
        AND: [{ x: { exists: true, y: { equals: 1 } } }],
      }),
    ).toEqual(['status', 'customer.name', 'rep.name', 'x', 'x.y']);
    expect(wherePaths({ or: { a: { equals: 1 } } })).toEqual(['a']);
    expect(wherePaths({ a: 1 })).toEqual(['a']);
    expect(wherePaths(null)).toEqual([]);
  });

  it('passes own-field filters and refuses dotted paths with a clear error', () => {
    const own: DataWhere = { and: [{ status: { in: ['new'] } }, { or: [{ rep: { equals: 5 } }] }] };
    expect(flatWhere(own)).toBe(own);
    const deeps: DataWhere[] = [
      { 'customer.name': { like: 'a' } },
      // The nested spelling Payload also reads (not expressible in its `Where` type, so it comes in as JSON).
      JSON.parse('{"customer":{"name":{"equals":"a"}}}'),
      { or: [{ and: [{ 'tenant.name': { equals: 'Dealer B' } }] }] },
      // Payload also reads a double underscore as a nested path.
      { tenants__tenant: { equals: 'B' } },
      { tenants__tenant__name: { like: 'Dealer B' } },
      { a__b: { equals: 1 } },
      JSON.parse('{"tenants":{"tenant__name":{"equals":"a"}}}'),
    ];
    for (const deep of deeps) {
      expect(() => flatWhere(deep), JSON.stringify(deep)).toThrow(TenantAccessError);
    }
  });
});

describe('double underscore paths', () => {
  it('wherePaths reads a__b as a.b', () => {
    expect(wherePaths({ tenants__tenant: { equals: 'B' }, a__b__c: { equals: 1 } })).toEqual([
      'tenants.tenant',
      'a.b.c',
    ]);
  });

  it('sortOf refuses a sort through a linked record in any spelling', () => {
    for (const sort of ['tenants__tenant', '-tenants__tenant', 'a__b', 'a.b']) {
      expect(() => sortOf(sort), sort).toThrow(RangeError);
    }
    expect(sortOf('-createdAt')).toBe('-createdAt');
    expect(sortOf('first_name')).toBe('first_name');
  });
});
