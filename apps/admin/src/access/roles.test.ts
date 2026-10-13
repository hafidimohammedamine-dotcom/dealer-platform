import { describe, expect, it } from 'vitest';
import { denyAll, idOf, isAdmin, roleOf } from './roles.js';

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

describe('idOf', () => {
  it('reads string and number IDs only', () => {
    expect(idOf({ id: 'u' })).toBe('u');
    expect(idOf({ id: 3 })).toBe(3);
    expect(idOf({ id: {} })).toBeNull();
    expect(idOf(null)).toBeNull();
  });
});

describe('access functions', () => {
  it('deny with no user, an unknown role or a deactivated user', () => {
    expect(isAdmin(args(undefined))).toBe(false);
    expect(isAdmin(args({ role: 'hacker' }))).toBe(false);
    expect(isAdmin(args({ role: 'admin', active: false }))).toBe(false);
    expect(denyAll()).toBe(false);
  });

  it('allow the right roles', () => {
    expect(isAdmin(args({ role: 'admin' }))).toBe(true);
    expect(isAdmin(args({ role: 'bdc' }))).toBe(false);
  });
});
