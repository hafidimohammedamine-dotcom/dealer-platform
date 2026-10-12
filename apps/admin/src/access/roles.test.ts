import { describe, expect, it } from 'vitest';
import {
  adminFieldAccess,
  denyAll,
  denyFieldAccess,
  hasRole,
  isAdmin,
  isStaff,
  roleOf,
  tenantIdsOf,
  userIdOf,
} from './roles.js';

// The access functions only read `req.user`, so the tests hand them just that.
function args(user: unknown): { req: { user: unknown } } {
  return { req: { user } };
}

describe('roleOf', () => {
  it('returns known roles only', () => {
    expect(roleOf({ role: 'bdc' })).toBe('bdc');
    expect(roleOf({ role: 'root' })).toBeNull();
    expect(roleOf({})).toBeNull();
    expect(roleOf(null)).toBeNull();
    expect(roleOf('admin')).toBeNull();
  });
});

describe('tenantIdsOf', () => {
  it('reads IDs from ids and populated objects, and ignores junk', () => {
    expect(
      tenantIdsOf({
        tenants: [
          { tenant: 'a' },
          { tenant: 2 },
          { tenant: { id: 'c' } },
          { tenant: { id: {} } },
          { tenant: null },
          5,
          null,
        ],
      }),
    ).toEqual(['a', 2, 'c']);
    expect(tenantIdsOf({ tenants: 'x' })).toEqual([]);
    expect(tenantIdsOf(undefined)).toEqual([]);
  });
});

describe('userIdOf', () => {
  it('reads string and number IDs only', () => {
    expect(userIdOf({ id: 'u' })).toBe('u');
    expect(userIdOf({ id: 3 })).toBe(3);
    expect(userIdOf({ id: {} })).toBeNull();
    expect(userIdOf(null)).toBeNull();
  });
});

describe('access functions', () => {
  it('deny with no user or an unknown role', () => {
    for (const fn of [isStaff, isAdmin, hasRole('admin', 'bdc')]) {
      expect(fn(args(undefined))).toBe(false);
      expect(fn(args({ role: 'hacker' }))).toBe(false);
    }
    expect(denyAll()).toBe(false);
  });

  it('allow the right roles', () => {
    expect(isStaff(args({ role: 'sales_rep' }))).toBe(true);
    expect(isAdmin(args({ role: 'admin' }))).toBe(true);
    expect(isAdmin(args({ role: 'bdc' }))).toBe(false);
    expect(hasRole('desking_manager')(args({ role: 'desking_manager' }))).toBe(true);
    expect(hasRole('desking_manager')(args({ role: 'bdc' }))).toBe(false);
  });

  it('field access follows the same rules', () => {
    expect(adminFieldAccess(args({ role: 'admin' }))).toBe(true);
    expect(adminFieldAccess(args({ role: 'bdc' }))).toBe(false);
    expect(denyFieldAccess()).toBe(false);
  });
});
