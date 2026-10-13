import { buildConfig } from 'payload';
import { beforeAll, describe, expect, it } from 'vitest';
import { buildAppConfig } from './config.js';
import type { AppEnv } from './env.js';

// Dealer A against dealer B at the access level (the leak suite on real Postgres is issue #60; row-level security #58).
// Payload's `where` filters are applied here to in-memory records, so a filter that lets dealer B through fails a test.
const env: AppEnv = {
  stage: 'dev',
  production: false,
  secret: 'x'.repeat(40),
  databaseUrl: 'postgres://app_user:fake@localhost:5432/dealer',
  serverURL: 'http://localhost:3000',
};

type Doc = Record<string, unknown>;

const isDoc = (value: unknown): value is Doc => typeof value === 'object' && value !== null;
const list = (value: unknown): unknown[] => (Array.isArray(value) ? value : []);

function field(doc: Doc, path: string): unknown[] {
  const [head, ...rest] = path.split('.');
  const value = doc[head ?? ''];
  if (rest.length === 0) return [value];
  const rows = Array.isArray(value) ? value : [value];
  return rows.flatMap((row) => (isDoc(row) ? field(row, rest.join('.')) : []));
}

function matches(doc: Doc, where: unknown): boolean {
  if (where === true) return true;
  if (!isDoc(where)) return false;
  return Object.entries(where).every(([key, rule]) => {
    if (key === 'and') return list(rule).every((w) => matches(doc, w));
    if (key === 'or') return list(rule).some((w) => matches(doc, w));
    const values = field(doc, key);
    if (!isDoc(rule)) return false;
    if (rule['equals'] !== undefined) return values.some((v) => v === rule['equals']);
    return values.some((v) => list(rule['in']).includes(v));
  });
}

const dealerDocs: Doc[] = [{ id: 'A' }, { id: 'B' }, { id: 'C' }];
const userDocs: Doc[] = [
  { id: 'adminA', role: 'admin', tenants: [{ tenant: 'A' }] },
  { id: 'repA', role: 'sales_rep', tenants: [{ tenant: 'A' }] },
  { id: 'adminB', role: 'admin', tenants: [{ tenant: 'B' }] },
  { id: 'repB', role: 'sales_rep', tenants: [{ tenant: 'B' }] },
  { id: 'sharedAB', role: 'sales_rep', tenants: [{ tenant: 'A' }, { tenant: 'B' }] },
  { id: 'loneC', role: 'bdc', tenants: [{ tenant: 'C' }] },
];
const byId = (id: string): Doc => userDocs.find((u) => u['id'] === id) ?? {};

interface Loose {
  run(args: unknown): unknown;
}
type Access = Record<string, Loose['run'] | undefined>;
let access: Record<'users' | 'dealers', Access>;
beforeAll(async () => {
  const config = await buildConfig(buildAppConfig({ env }));
  const pick = (slug: 'users' | 'dealers'): Access => ({
    ...config.collections.find((c) => c.slug === slug)?.access,
  });
  access = { users: pick('users'), dealers: pick('dealers') };
});

const visible = async (slug: 'users' | 'dealers', op: string, actor: Doc, docs: Doc[]) => {
  const result = await access[slug][op]?.({ req: { user: actor } });
  return docs.filter((d) => matches(d, result)).map((d) => d['id']);
};

describe('dealer A cannot reach dealer B', () => {
  it('users: an admin or a rep of A reads A people only, never B-only or C-only people', async () => {
    for (const actor of ['adminA', 'repA']) {
      expect(await visible('users', 'read', byId(actor), userDocs)).toEqual([
        'adminA',
        'repA',
        'sharedAB',
      ]);
    }
    expect(await visible('users', 'read', byId('repB'), userDocs)).toEqual([
      'adminB',
      'repB',
      'sharedAB',
    ]);
  });

  it('users: the update filter of an admin of A never matches a B-only user; a rep matches only themself', async () => {
    expect(await visible('users', 'update', byId('adminA'), userDocs)).toEqual([
      'adminA',
      'repA',
      'sharedAB',
    ]);
    expect(await visible('users', 'update', byId('repA'), userDocs)).toEqual(['repA']);
    expect(await visible('users', 'update', byId('loneC'), userDocs)).toEqual(['loneC']);
  });

  it('users: unlock, delete and versions are closed to every role', async () => {
    for (const op of ['unlock', 'delete', 'readVersions']) {
      for (const actor of ['adminA', 'repA', 'sharedAB']) {
        expect(await visible('users', op, byId(actor), userDocs)).toEqual([]);
      }
    }
  });

  it('dealers: read gives only the own dealers; update the same for an admin, nothing for a rep', async () => {
    expect(await visible('dealers', 'read', byId('adminA'), dealerDocs)).toEqual(['A']);
    expect(await visible('dealers', 'read', byId('repB'), dealerDocs)).toEqual(['B']);
    expect(await visible('dealers', 'read', byId('sharedAB'), dealerDocs)).toEqual(['A', 'B']);
    expect(await visible('dealers', 'update', byId('adminA'), dealerDocs)).toEqual(['A']);
    expect(await visible('dealers', 'update', byId('repA'), dealerDocs)).toEqual([]);
  });

  it('dealers: create and delete are closed to every role', async () => {
    for (const op of ['create', 'delete']) {
      expect(await visible('dealers', op, byId('adminA'), dealerDocs)).toEqual([]);
    }
  });

  it('a user with no dealers, a deactivated admin and an anonymous caller get nothing', async () => {
    const nobody = { id: 'n', role: 'admin', tenants: [] };
    const off = { ...byId('adminA'), active: false };
    for (const actor of [nobody, off]) {
      expect(await visible('dealers', 'read', actor, dealerDocs)).toEqual([]);
      expect(await visible('dealers', 'update', actor, dealerDocs)).toEqual([]);
    }
    expect(await visible('users', 'read', off, userDocs)).toEqual([]);
    expect(await visible('users', 'read', nobody, userDocs)).toEqual([]);
    expect(await visible('users', 'read', {}, userDocs)).toEqual([]);
  });
});

describe('the in-memory filter used above is itself correct', () => {
  it('handles equals, in, and, or, nested array paths, and refuses odd input', () => {
    const doc = { id: 1, tenants: [{ tenant: 'A' }, { tenant: 'B' }] };
    expect(matches(doc, { id: { equals: 1 } })).toBe(true);
    expect(matches(doc, { id: { equals: 2 } })).toBe(false);
    expect(matches(doc, { 'tenants.tenant': { in: ['B'] } })).toBe(true);
    expect(matches(doc, { 'tenants.tenant': { in: ['C'] } })).toBe(false);
    expect(
      matches(doc, { and: [{ id: { equals: 1 } }, { 'tenants.tenant': { in: ['C'] } }] }),
    ).toBe(false);
    expect(matches(doc, { or: [{ id: { equals: 2 } }, { id: { equals: 1 } }] })).toBe(true);
    expect(matches(doc, true)).toBe(true);
    expect(matches(doc, false)).toBe(false);
    expect(matches(doc, null)).toBe(false);
    expect(matches({ id: 1, tenants: 'x' }, { 'tenants.tenant': { in: ['A'] } })).toBe(false);
  });
});
