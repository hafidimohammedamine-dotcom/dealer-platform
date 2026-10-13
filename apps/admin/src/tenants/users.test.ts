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
  guardUserOperation,
  refuseInactiveLogin,
  usersInMyDealers,
} from './users.js';
import { endSessionsOnDeactivate } from './sessions.js';
import { adminA, adminAB, call, repA, t, write } from '../test-helpers/fixtures.js';

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

  it('refuses every update too: there is no system-job marker and no reset-token write', () => {
    const token = { resetPasswordToken: 't', resetPasswordExpiration: 'd' };
    for (const data of [token, { role: 'admin' }, { tenants: [] }, {}, undefined]) {
      expect(write(undefined, 'update', data, { id: 'u' }), JSON.stringify(data)).toThrow(
        Forbidden,
      );
    }
  });

  it('a request context flag no longer opens anything (security review round 3, finding 5)', () => {
    const data = { email: 'a@x.test', role: 'admin', tenants: [{ tenant: 'A' }] };
    for (const context of [{ reviewedSystemJob: true }, { passwordResetOperation: true }]) {
      expect(() =>
        call(guardUserWrite, { data, operation: 'create', req: { user: undefined, t }, context }),
      ).toThrow(Forbidden);
    }
  });
});

describe('guardUserOperation: closed flows, inactive refresh, no probing of dealer rows', () => {
  const run =
    (operation: string, args: Record<string, unknown> = {}, user: unknown = adminA) =>
    () =>
      call(guardUserOperation, { args, operation, req: { user, t } });

  it('refuses forgot-password and reset-password for everyone until issue #73', () => {
    for (const operation of ['forgotPassword', 'resetPassword']) {
      for (const user of [undefined, adminA, repA]) {
        expect(run(operation, { data: { email: 'rep@a.example' } }, user)).toThrow(Forbidden);
      }
    }
  });

  it('refuses a refresh by a deactivated user, and lets an active one through', () => {
    expect(run('refresh', {}, { ...repA, active: false })).toThrow(Forbidden);
    const args = {};
    expect(run('refresh', args, repA)()).toBe(args);
    expect(run('refresh', args, undefined)()).toBe(args);
  });

  it('refuses where and sort paths on the dealer rows, in every spelling (finding 4)', () => {
    const wheres = [
      { 'tenants.tenant.name': { like: 'Dealer B' } },
      { or: [{ and: [{ 'tenants.tenant.slug': { equals: 'b' } }] }] },
      { tenants: { tenant: { name: { equals: 'Dealer B' } } } },
      { 'tenants.tenant': { equals: 'B' } },
      { tenants: { exists: true } },
      { OR: [{ 'tenants.id': { equals: 'row' } }] },
    ];
    for (const operation of ['read', 'count', 'update', 'delete']) {
      for (const where of wheres) {
        expect(run(operation, { where }), `${operation} ${JSON.stringify(where)}`).toThrow(
          Forbidden,
        );
      }
      for (const sort of [
        'tenants.tenant.name',
        '-tenants.tenant.name',
        'email,tenants',
        ['tenants.tenant'],
      ]) {
        expect(run(operation, { sort }), `${operation} ${String(sort)}`).toThrow(Forbidden);
      }
    }
  });

  it('lets own-field filters and sorts through unchanged', () => {
    const args = {
      where: { and: [{ role: { equals: 'bdc' } }, { email: { like: 'a' } }] },
      sort: '-createdAt,email',
    };
    expect(run('read', args)()).toBe(args);
    const other = { sort: ['email', 7] };
    expect(run('count', other)()).toBe(other);
    expect(
      call(guardUserOperation, { args: undefined, operation: 'read', req: { t } }),
    ).toBeUndefined();
  });
});

describe('endSessionsOnDeactivate: deactivation ends every login (finding 9)', () => {
  const setup = () => {
    const writes: unknown[] = [];
    const req = {
      payload: {
        db: {
          updateOne: async (args: unknown) => {
            writes.push(args);
          },
        },
      },
    };
    return { writes, req };
  };

  it('clears the sessions of the deactivated user, inside the same request (transaction)', async () => {
    const { writes, req } = setup();
    const doc = { id: 'repA', active: false };
    await expect(
      call(endSessionsOnDeactivate, {
        doc,
        previousDoc: { id: 'repA', active: true },
        operation: 'update',
        req,
      }),
    ).resolves.toBe(doc);
    expect(writes).toEqual([
      { collection: 'users', id: 'repA', data: { sessions: [] }, req, returning: false },
    ]);
  });

  it('does nothing for an active user, an already inactive user or a create', async () => {
    const { writes, req } = setup();
    const runHook = (doc: unknown, previousDoc: unknown, operation: string) =>
      call(endSessionsOnDeactivate, { doc, previousDoc, operation, req });
    await runHook({ id: 1, active: true }, { id: 1, active: true }, 'update');
    await runHook({ id: 1, active: false }, { id: 1, active: false }, 'update');
    await runHook({ id: 1, active: false }, undefined, 'create');
    await runHook(undefined, undefined, 'update');
    expect(writes).toEqual([]);
  });

  it('fails the deactivation when the sessions cannot be cleared', async () => {
    const req = {
      payload: { db: { updateOne: async () => Promise.reject(new Error('db down')) } },
    };
    await expect(
      call(endSessionsOnDeactivate, {
        doc: { id: 1, active: false },
        previousDoc: { id: 1 },
        operation: 'update',
        req,
      }),
    ).rejects.toThrow('db down');
  });

  it('is wired into the users collection', () => {
    const users = buildUsers({ secureCookies: true });
    expect(users.hooks?.afterChange).toContain(endSessionsOnDeactivate);
    expect(users.hooks?.beforeOperation).toEqual([guardUserOperation]);
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
