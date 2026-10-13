import { describe, expect, it } from 'vitest';
import { createAuditLog } from '@dealer/platform';
import type { AuditEntry } from '@dealer/platform';
import { auditDealerChange, Dealers, readOwnDealers, updateOwnDealers } from './dealers.js';

// Hooks and access functions take big argument objects; the tests hand them only what they read.
interface Loose {
  run(args: unknown): unknown;
}
const call = (fn: Loose['run'] | undefined, args: unknown): unknown => fn?.(args);
const adminA = { id: 'adminA', role: 'admin', tenants: [{ tenant: 'A' }] };
const repA = { id: 'repA', role: 'sales_rep', tenants: [{ tenant: 'A' }] };

describe('dealers access', () => {
  it('read and update are limited to the dealers on the user', () => {
    expect(call(readOwnDealers, { req: { user: adminA } })).toEqual({ id: { in: ['A'] } });
    expect(call(readOwnDealers, { req: { user: repA } })).toEqual({ id: { in: ['A'] } });
    expect(call(updateOwnDealers, { req: { user: adminA } })).toEqual({ id: { in: ['A'] } });
  });

  it('a rep cannot update, and nobody without a dealer, a role or a login reads anything', () => {
    expect(call(updateOwnDealers, { req: { user: repA } })).toBe(false);
    expect(call(readOwnDealers, { req: { user: { id: 1, role: 'bdc', tenants: [] } } })).toBe(
      false,
    );
    expect(call(readOwnDealers, { req: { user: { id: 1, tenants: [{ tenant: 'A' }] } } })).toBe(
      false,
    );
    expect(call(readOwnDealers, { req: {} })).toBe(false);
    expect(call(updateOwnDealers, { req: {} })).toBe(false);
  });

  it('create, delete and versions are closed to everyone', () => {
    for (const key of ['create', 'delete', 'readVersions'] as const) {
      expect(call(Dealers.access?.[key], { req: { user: adminA } })).toBe(false);
    }
  });

  it('the slug cannot be changed after it is set', () => {
    const slug = Dealers.fields.find((f) => 'name' in f && f.name === 'slug');
    if (!slug || !('access' in slug) || !('unique' in slug)) throw new Error('slug field missing');
    expect(call(slug.access?.update, { req: {} })).toBe(false);
    expect(slug.unique).toBe(true);
  });
});

describe('dealer audit', () => {
  const entries: AuditEntry[] = [];
  const audit = createAuditLog({ append: (e) => void entries.push(e) });

  it('records who renamed which dealer, with the old and new name', async () => {
    entries.length = 0;
    await call(auditDealerChange(audit), {
      doc: { id: 'A', name: 'New' },
      previousDoc: { id: 'A', name: 'Old' },
      operation: 'update',
      req: { user: adminA },
    });
    expect(entries[0]).toMatchObject({
      action: 'dealer.update',
      actorId: 'adminA',
      target: { collection: 'dealers', id: 'A' },
      dealerIds: ['A'],
      before: { name: 'Old' },
      after: { name: 'New' },
    });
  });

  it('records a create by a system job and copes with odd documents', async () => {
    entries.length = 0;
    await call(auditDealerChange(audit), {
      doc: null,
      previousDoc: null,
      operation: 'create',
      req: {},
    });
    expect(entries[0]).toMatchObject({ actorId: null, after: { name: null }, dealerIds: [''] });
    expect(entries[0]?.before).toBeUndefined();
  });
});
