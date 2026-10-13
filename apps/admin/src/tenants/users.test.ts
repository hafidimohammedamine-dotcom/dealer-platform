import { AuthenticationError, Forbidden, ValidationError } from 'payload';
import type { Field } from 'payload';
import { describe, expect, it } from 'vitest';
import type { AuditEntry } from '@dealer/platform';
import { createAuditLog } from '@dealer/platform';
import {
  auditUserChange,
  auditUserDelete,
  buildUsers,
  canUpdateUser,
  guardUserWrite,
  hideDuplicateEmail,
  refuseInactiveLogin,
  SYSTEM_JOB_CONTEXT,
  usersInMyDealers,
} from './users.js';

// Hooks take big argument objects; the tests hand them only what they read, through one cast.
interface Loose {
  run(args: unknown): unknown;
}
const call = (fn: Loose['run'] | undefined, args: unknown): unknown => fn?.(args);
const t = () => 'x';

const adminA = { id: 'adminA', role: 'admin', tenants: [{ tenant: 'A' }] };
const adminAB = { id: 'adminAB', role: 'admin', tenants: [{ tenant: 'A' }, { tenant: 'B' }] };
const repA = { id: 'repA', role: 'sales_rep', tenants: [{ tenant: 'A' }] };

function write(
  user: unknown,
  operation: 'create' | 'update',
  data: Record<string, unknown> | undefined,
  originalDoc?: unknown,
  context: Record<string, unknown> = {},
) {
  return () => call(guardUserWrite, { data, originalDoc, operation, req: { user, t }, context });
}

describe('canUpdateUser and usersInMyDealers', () => {
  it('limits an admin to users of their dealers, and everyone else to themself', () => {
    expect(canUpdateUser({ req: { user: adminA } })).toEqual({
      or: [{ id: { equals: 'adminA' } }, { 'tenants.tenant': { in: ['A'] } }],
    });
    expect(canUpdateUser({ req: { user: repA } })).toEqual({ id: { equals: 'repA' } });
    expect(canUpdateUser({ req: { user: { id: 2, role: 'bdc' } } })).toEqual({ id: { equals: 2 } });
  });

  it('reads: self plus the user dealers; a user with no dealer sees only themself', () => {
    expect(usersInMyDealers({ req: { user: adminAB } })).toEqual({
      or: [{ id: { equals: 'adminAB' } }, { 'tenants.tenant': { in: ['A', 'B'] } }],
    });
    expect(usersInMyDealers({ req: { user: { id: 'x', role: 'bdc', tenants: [] } } })).toEqual({
      or: [{ id: { equals: 'x' } }],
    });
  });

  it('denies a missing user, an unknown role, a deactivated user and a user without an ID', () => {
    for (const fn of [canUpdateUser, usersInMyDealers]) {
      expect(fn({ req: {} })).toBe(false);
      expect(fn({ req: { user: { id: 1, role: 'root' } } })).toBe(false);
      expect(fn({ req: { user: { ...adminA, active: false } } })).toBe(false);
      expect(fn({ req: { user: { role: 'bdc' } } })).toBe(false);
    }
  });
});

describe('the user collection', () => {
  const users = buildUsers({ secureCookies: true });
  const as = (user: unknown) => ({ req: { user } });

  it('cannot be deleted or unlocked through the API, and has no versions', () => {
    expect(call(users.access?.delete, as(adminA))).toBe(false);
    expect(call(users.access?.unlock, as(adminAB))).toBe(false);
    expect(call(users.access?.readVersions, as(adminAB))).toBe(false);
  });

  it('turns on email verification and secure strict cookies', () => {
    expect(users.auth).toMatchObject({
      verify: true,
      cookies: { secure: true, sameSite: 'Strict' },
    });
    expect(buildUsers({ secureCookies: false }).auth).toMatchObject({
      cookies: { secure: false },
    });
  });

  it('lets only an admin set email, role and active; nobody changes the email later', () => {
    const access = (fields: Field[], name: string) => {
      const found = fields.find((f) => 'name' in f && f.name === name);
      if (!found || !('access' in found)) throw new Error(`${name} has no field access`);
      return found.access;
    };
    for (const name of ['email', 'role', 'active']) {
      expect(call(access(users.fields, name)?.create, as(adminA))).toBe(true);
      expect(call(access(users.fields, name)?.create, as(repA))).toBe(false);
    }
    expect(call(access(users.fields, 'role')?.update, as(repA))).toBe(false);
    expect(call(access(users.fields, 'active')?.update, as(adminA))).toBe(true);
    expect(call(access(users.fields, 'email')?.update, as(adminA))).toBe(false);
  });
});

describe('guardUserWrite: logged-in actor', () => {
  it('lets own dealers and untouched data through', () => {
    const own = { tenants: [{ tenant: 'A' }] };
    expect(write(adminA, 'create', own)()).toBe(own);
    expect(write(adminA, 'update', own, { tenants: [{ tenant: 'A' }] })()).toBe(own);
    const other = { email: 'e' };
    expect(write(adminA, 'update', other, { tenants: [{ tenant: 'A' }] })()).toBe(other);
    expect(
      write(adminAB, 'create', { tenants: [{ tenant: 'A' }, { tenant: 'B' }] })(),
    ).toBeDefined();
  });

  it('a rep may update their own record', () => {
    const data = { email: 'e' };
    expect(write(repA, 'update', data, { id: 'repA', tenants: [{ tenant: 'A' }] })()).toBe(data);
  });

  it('refuses another dealer, junk rows, a non-array, and a create without dealers', () => {
    const attempt = (tenants: unknown, operation: 'create' | 'update' = 'create') =>
      write(adminA, operation, { tenants }, { tenants: [{ tenant: 'A' }] });
    expect(attempt([{ tenant: 'B' }])).toThrow(Forbidden);
    expect(attempt([{ tenant: 'A' }, { tenant: 'B' }])).toThrow(Forbidden);
    expect(attempt([{ tenant: 'A' }, 'junk'])).toThrow(Forbidden);
    expect(attempt([{ tenant: 'A' }, { tenant: '' }], 'update')).toThrow(Forbidden);
    expect(attempt('A')).toThrow(Forbidden);
    expect(attempt([])).toThrow(Forbidden);
    expect(write(adminA, 'create', { email: 'e' })).toThrow(Forbidden);
    expect(write(adminA, 'create', undefined)).toThrow(Forbidden);
  });

  it('an admin of dealer A cannot change, move or reset a user who also works for dealer B', () => {
    const shared = { id: 'shared', tenants: [{ tenant: 'A' }, { tenant: 'B' }] };
    expect(write(adminA, 'update', { role: 'admin' }, shared)).toThrow(Forbidden);
    expect(write(adminA, 'update', { password: 'new-password' }, shared)).toThrow(Forbidden);
    expect(write(adminA, 'update', { tenants: [{ tenant: 'A' }] }, shared)).toThrow(Forbidden);
    expect(write(adminA, 'update', { active: false }, shared)).toThrow(Forbidden);
    // A user of dealer B alone is out of reach too.
    expect(
      write(adminA, 'update', { role: 'admin' }, { id: 'b', tenants: [{ tenant: 'B' }] }),
    ).toThrow(Forbidden);
    // An admin of both dealers may.
    expect(write(adminAB, 'update', { role: 'bdc' }, shared)()).toEqual({ role: 'bdc' });
  });

  it('editing a user of A and C as an admin of A alone does not silently drop C', () => {
    const ac = { id: 'ac', tenants: [{ tenant: 'A' }, { tenant: 'C' }] };
    expect(write(adminA, 'update', { tenants: [{ tenant: 'A' }] }, ac)).toThrow(Forbidden);
  });

  it('refuses an update when the original record has no readable dealers', () => {
    expect(write(adminA, 'update', { role: 'bdc' }, { id: 'x' })()).toEqual({ role: 'bdc' });
    expect(
      write(adminA, 'update', { role: 'bdc' }, { id: 'x', tenants: [{ tenant: 'B' }] }),
    ).toThrow(Forbidden);
  });
});

describe('guardUserWrite: no logged-in actor', () => {
  it('refuses a create (this shuts first-user registration on a fresh deploy)', () => {
    const data = { email: 'a@x.test', role: 'admin', tenants: [{ tenant: 'A' }] };
    expect(write(undefined, 'create', data)).toThrow(Forbidden);
    expect(write(undefined, 'create', undefined)).toThrow(Forbidden);
  });

  it('accepts a create only from a reviewed system job', () => {
    const data = { email: 'a@x.test', role: 'admin', tenants: [{ tenant: 'A' }] };
    expect(write(undefined, 'create', data, undefined, { [SYSTEM_JOB_CONTEXT]: true })()).toBe(
      data,
    );
    expect(write(undefined, 'create', data, undefined, { [SYSTEM_JOB_CONTEXT]: 'yes' })).toThrow(
      Forbidden,
    );
  });

  it('allows only the reset-token fields on an update', () => {
    const token = { resetPasswordToken: 't', resetPasswordExpiration: 'd' };
    expect(write(undefined, 'update', token, { id: 'u' })()).toBe(token);
    expect(write(undefined, 'update', { ...token, role: 'admin' }, { id: 'u' })).toThrow(Forbidden);
    expect(write(undefined, 'update', { tenants: [] }, { id: 'u' })).toThrow(Forbidden);
    expect(write(undefined, 'update', {}, { id: 'u' })).toThrow(Forbidden);
    expect(write(undefined, 'update', undefined, { id: 'u' })).toThrow(Forbidden);
  });
});

describe('login and errors', () => {
  it('refuses a deactivated user at login only', () => {
    expect(() => call(refuseInactiveLogin, { user: { active: false } })).toThrow(
      AuthenticationError,
    );
    expect(call(refuseInactiveLogin, { user: { active: true } })).toBeUndefined();
    expect(call(refuseInactiveLogin, { user: {} })).toBeUndefined();
  });

  it('hides which email exists: a duplicate email gives the same generic answer', () => {
    const duplicate = new ValidationError({
      collection: 'users',
      errors: [{ path: 'email', message: 'Value must be unique' }],
    });
    const result = call(hideDuplicateEmail, { error: duplicate });
    expect(result).toEqual({
      status: 400,
      response: { errors: [{ message: expect.stringContaining('could not be saved') }] },
    });
    expect(JSON.stringify(result)).not.toContain('unique');
  });

  it('leaves other errors alone', () => {
    const other = new ValidationError({
      collection: 'users',
      errors: [{ path: 'role', message: 'Required' }],
    });
    expect(call(hideDuplicateEmail, { error: other })).toBeUndefined();
    expect(call(hideDuplicateEmail, { error: new Error('boom') })).toBeUndefined();
  });
});

describe('the audit trail', () => {
  const entries: AuditEntry[] = [];
  const audit = createAuditLog({ append: (e) => void entries.push(e) });
  const before = {
    id: 'u1',
    role: 'bdc',
    email: 'u@x.test',
    active: true,
    tenants: [{ tenant: 'A' }],
    hash: 'h',
  };
  const after = { ...before, role: 'admin' };

  it('records a create with the actor and the new role and dealers', async () => {
    entries.length = 0;
    const doc = await call(auditUserChange(audit), {
      doc: after,
      previousDoc: undefined,
      operation: 'create',
      req: { user: adminA },
    });
    expect(doc).toBe(after);
    expect(entries[0]).toMatchObject({
      action: 'user.create',
      actorId: 'adminA',
      target: { collection: 'users', id: 'u1' },
      dealerIds: ['A'],
      after: { role: 'admin', active: true, email: 'u@x.test', tenants: ['A'] },
    });
    expect(entries[0]?.before).toBeUndefined();
    expect(JSON.stringify(entries[0])).not.toContain('"h"');
  });

  it('records a role change with before and after, and skips a change that touches no access field', async () => {
    entries.length = 0;
    await call(auditUserChange(audit), {
      doc: after,
      previousDoc: before,
      operation: 'update',
      req: { user: adminA },
    });
    expect(entries[0]).toMatchObject({
      action: 'user.update',
      before: { role: 'bdc' },
      after: { role: 'admin' },
    });
    entries.length = 0;
    await call(auditUserChange(audit), {
      doc: { ...before, resetPasswordToken: 'new' },
      previousDoc: before,
      operation: 'update',
      req: {},
    });
    expect(entries).toEqual([]);
  });

  it('records a deactivation and a delete, and a system job has no actor', async () => {
    entries.length = 0;
    await call(auditUserChange(audit), {
      doc: { ...before, active: false },
      previousDoc: before,
      operation: 'update',
      req: { user: adminA },
    });
    expect(entries[0]).toMatchObject({ before: { active: true }, after: { active: false } });
    entries.length = 0;
    await call(auditUserDelete(audit), { doc: before, req: {} });
    expect(entries[0]).toMatchObject({ action: 'user.delete', actorId: null, dealerIds: ['A'] });
    await call(auditUserChange(audit), {
      doc: null,
      previousDoc: null,
      operation: 'create',
      req: {},
    });
    expect(entries[1]).toMatchObject({ after: { role: null, tenants: [] } });
  });

  it('stops the change when the audit write fails', async () => {
    const broken = createAuditLog({
      append: () => {
        throw new Error('sink down');
      },
    });
    await expect(
      call(auditUserChange(broken), {
        doc: after,
        previousDoc: before,
        operation: 'update',
        req: {},
      }),
    ).rejects.toThrow('sink down');
  });
});
