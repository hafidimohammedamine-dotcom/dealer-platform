import type { LocalApi, TenantId } from '../tenant-data.js';
import { forTenant } from '../for-tenant.js';

export type Call = { method: string; args: object };

// The user Payload's `auth` finds for a valid login (dealers 1 and "b").
export const stored = {
  id: 10,
  collection: 'users',
  role: 'sales_rep',
  tenants: [{ tenant: 1 }, { tenant: { id: 'b' } }, { tenant: null }],
};

/** `found` is what Payload's `auth` returns as the user for the request headers. */
export function fakeApi(
  docs: unknown[] = [],
  found: unknown = stored,
): { api: LocalApi; calls: Call[] } {
  const calls: Call[] = [];
  const api: LocalApi = {
    auth: async (args) => {
      calls.push({ method: 'auth', args });
      return { user: found };
    },
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

// The request headers: the helper never reads them itself, it hands them to Payload's `auth`.
export const headers = new Headers({ cookie: 'payload-token=fake-session-cookie' });
export const ctx = { headers, tenantId: 1 };
export const tenantClause = { tenant: { equals: 1 } };
// Lets junk reach a typed parameter without a type assertion: the guard deliberately says yes to everything.
const anything = (value: unknown): value is TenantId => [value].length === 1;
export function loose(value: unknown): TenantId {
  return [value].filter(anything).reduce<TenantId>((_, only) => only, 0);
}
export const fresh = { ...stored, collection: 'users' };

export async function helper(docs: unknown[] = []) {
  const fake = fakeApi(docs);
  const data = await forTenant(fake.api, ctx);
  fake.calls.length = 0; // forget the auth call
  return { data, calls: fake.calls };
}
