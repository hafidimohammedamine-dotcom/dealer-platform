import { describe, expect, it } from 'vitest';
import { denyAll, isAdmin, isStaff, roleOf, userIdOf } from './roles.js';

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

  it('gives a deactivated user no role at all', () => {
    expect(roleOf({ role: 'admin', active: false })).toBeNull();
    expect(roleOf({ role: 'admin', active: true })).toBe('admin');
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
  it('deny with no user, an unknown role or a deactivated user', () => {
    for (const fn of [isStaff, isAdmin]) {
      expect(fn(args(undefined))).toBe(false);
      expect(fn(args({ role: 'hacker' }))).toBe(false);
      expect(fn(args({ role: 'admin', active: false }))).toBe(false);
    }
    expect(denyAll()).toBe(false);
  });

  it('allow the right roles', () => {
    expect(isStaff(args({ role: 'sales_rep' }))).toBe(true);
    expect(isAdmin(args({ role: 'admin' }))).toBe(true);
    expect(isAdmin(args({ role: 'bdc' }))).toBe(false);
  });
});
