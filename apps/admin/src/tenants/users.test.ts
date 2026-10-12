import { describe, expect, it } from 'vitest';
import { canUpdateUser } from './users.js';

describe('canUpdateUser', () => {
  it('lets an admin update users of the dealer', () => {
    expect(canUpdateUser({ req: { user: { id: 1, role: 'admin' } } })).toBe(true);
  });

  it('limits everyone else to their own record', () => {
    expect(canUpdateUser({ req: { user: { id: 'r', role: 'sales_rep' } } })).toEqual({
      id: { equals: 'r' },
    });
    expect(canUpdateUser({ req: { user: { id: 2, role: 'bdc' } } })).toEqual({ id: { equals: 2 } });
  });

  it('denies a missing user, an unknown role and a user without an ID', () => {
    expect(canUpdateUser({ req: {} })).toBe(false);
    expect(canUpdateUser({ req: { user: { id: 1, role: 'root' } } })).toBe(false);
    expect(canUpdateUser({ req: { user: { role: 'bdc' } } })).toBe(false);
  });
});
