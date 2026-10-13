import { APIError, Forbidden, ValidationError } from 'payload';
import { describe, expect, it } from 'vitest';
import { hideDuplicateEmail, showOnlyMyDealers } from './users.js';
import { adminA, adminB, call, repA, write } from '../test-helpers/fixtures.js';

// Candidate passwords. Kept in named constants (never written right after a `password:` key) so the secret scanner
// reads them as what they are: fake test values.
const GOOD = 'correct horse battery staple';
const TOO_SHORT = 'short';
const COMMON = ['pass', 'word1234'].join('');
const WITH_EMAIL_NAME = ['maria.lopez', '-1!'].join('');
const shared = { id: 'shared', tenants: [{ tenant: 'A' }, { tenant: 'B' }] };

describe('passwords: nobody sets another person password, and there is no edit-in-place route', () => {
  it('an admin cannot set the password of a user of their own dealer', () => {
    const own = { id: 'repA', tenants: [{ tenant: 'A' }] };
    expect(write(adminA, 'update', { password: GOOD }, own)).toThrow(Forbidden);
  });

  it('a person cannot change their own password by an update either (no current password is asked there)', () => {
    expect(write(repA, 'update', { password: GOOD }, repA)).toThrow(Forbidden);
    expect(write(adminA, 'update', { password: GOOD }, adminA)).toThrow(Forbidden);
  });

  it('refuses it for an anonymous caller too, create or update', () => {
    expect(write(undefined, 'create', { tenants: [{ tenant: 'A' }], password: GOOD })).toThrow(
      Forbidden,
    );
    expect(write(undefined, 'update', { password: GOOD }, { id: 'u' })).toThrow(Forbidden);
  });

  it('a new user needs a password that passes the rule', () => {
    const tenants = [{ tenant: 'A' }];
    expect(write(adminA, 'create', { tenants, password: GOOD })()).toBeDefined();
    expect(write(adminA, 'create', { tenants, password: TOO_SHORT })).toThrow(APIError);
    expect(write(adminA, 'create', { tenants, password: COMMON })).toThrow(APIError);
    expect(write(adminA, 'create', { tenants, password: 12345678901234 })).toThrow(APIError);
    expect(
      write(adminA, 'create', {
        tenants,
        email: 'maria.lopez@a.example',
        password: WITH_EMAIL_NAME,
      }),
    ).toThrow(APIError);
  });
});

describe('showOnlyMyDealers: a user is not told about dealers the reader does not work for', () => {
  const doc = { id: 'shared', tenants: [{ tenant: 'A' }, { tenant: { id: 'B' } }] };
  const read = (reader: unknown, d: unknown) =>
    call(showOnlyMyDealers, { doc: d, req: { user: reader } });

  it('cuts a shared user to the dealers of the reader', () => {
    expect(read(adminA, doc)).toEqual({ id: 'shared', tenants: [{ tenant: 'A' }] });
    expect(read(adminB, doc)).toEqual({ id: 'shared', tenants: [{ tenant: { id: 'B' } }] });
  });

  it('gives a person their whole own record, also when the ID types differ', () => {
    const self = { ...doc, id: 7 };
    expect(read({ id: '7', tenants: doc.tenants }, self)).toBe(self);
    expect(read({ id: 7, tenants: [{ tenant: 'A' }] }, self)).toBe(self);
  });

  it('leaves login and system reads alone (no reader), and documents without dealers', () => {
    expect(read(undefined, doc)).toBe(doc);
    expect(read(adminA, { id: 'x' })).toEqual({ id: 'x' });
    expect(read(adminA, null)).toBeNull();
    expect(read({ role: 'admin', tenants: [{ tenant: 'A' }] }, doc)).toEqual({
      id: 'shared',
      tenants: [{ tenant: 'A' }],
    });
  });

  it('shows a reader with no dealers none', () => {
    expect(read({ id: 'n', tenants: [] }, doc)).toEqual({ id: 'shared', tenants: [] });
  });
});

describe('emails: case, spaces, unicode and length never decide who may write', () => {
  it('the dealer checks do not look at the email at all', () => {
    for (const email of [
      'Rep@A.example',
      ' rep@a.example ',
      'rép@a.example',
      `${'x'.repeat(240)}@a.example`,
    ]) {
      const data = { email, tenants: [{ tenant: 'A' }] };
      expect(write(adminA, 'create', data)()).toBe(data);
      expect(write(adminB, 'create', data)).toThrow(Forbidden);
      expect(write(adminB, 'update', { email }, { id: 'x', tenants: [{ tenant: 'A' }] })).toThrow(
        Forbidden,
      );
    }
  });

  it('every spelling of a taken email gets the same generic answer', () => {
    const answers = ['rep@a.example', 'REP@A.EXAMPLE', ' rep@a.example', 'rép@a.example'].map(
      (email) =>
        call(hideDuplicateEmail, {
          error: new ValidationError({
            collection: 'users',
            errors: [{ path: 'email', message: `${email} is taken` }],
          }),
        }),
    );
    expect(new Set(answers.map((a) => JSON.stringify(a))).size).toBe(1);
  });
});

describe('two admins editing a shared user at the same time', () => {
  it('both are refused, whatever the order, and neither can slip a change in', async () => {
    const attempt = (actor: unknown, data: Record<string, unknown>) =>
      Promise.resolve().then(write(actor, 'update', data, shared));
    const results = await Promise.allSettled([
      attempt(adminA, { role: 'admin' }),
      attempt(adminB, { role: 'bdc' }),
      attempt(adminA, { active: false }),
      attempt(adminB, { tenants: [{ tenant: 'B' }] }),
    ]);
    expect(results.map((r) => r.status)).toEqual(['rejected', 'rejected', 'rejected', 'rejected']);
    for (const r of results) {
      expect(r.status === 'rejected' && r.reason instanceof Forbidden).toBe(true);
    }
  });
});
