import { APIError, AuthenticationError, Forbidden, ValidationError } from 'payload';
import type {
  CollectionAfterChangeHook,
  CollectionAfterDeleteHook,
  CollectionAfterErrorHook,
  CollectionAfterReadHook,
  CollectionBeforeLoginHook,
  CollectionBeforeOperationHook,
  CollectionBeforeValidateHook,
  CollectionConfig,
  Field,
  Where,
} from 'payload';
import { isRecord, tenantIdsOf, USERS_COLLECTION, wherePaths } from '@dealer/data';
import { denyAll, idOf, isAdmin, ROLE_OPTIONS, roleOf } from '../access/roles.js';
import type { AuditLog } from './audit.js';
import { accessAudit } from './audit.js';
import { passwordProblem } from './password-policy.js';
import { endSessionsOnDeactivate } from './sessions.js';

type UserScope = Where | false;

/**
 * The users a logged-in user may reach: themself, and anyone who works for one of their dealers. The multi-tenant plugin
 * adds the dealer field to this collection but does not filter it, so the filter is written here (tested with two dealers).
 */
export const usersInMyDealers = ({ req }: { req: { user?: unknown } }): UserScope => {
  const id = idOf(req.user);
  if (roleOf(req.user) === null || id === null) return false;
  const dealers = tenantIdsOf(req.user);
  const self = { id: { equals: id } };
  return { or: dealers.length > 0 ? [self, { 'tenants.tenant': { in: dealers } }] : [self] };
};

/**
 * An admin may update users of their dealers (the hook below then refuses anyone who also belongs to a dealer the admin
 * does not); everyone else only themself. A filter, not `true`, is what keeps a sales rep from editing a colleague.
 */
export const canUpdateUser = ({ req }: { req: { user?: unknown } }): UserScope => {
  const role = roleOf(req.user);
  if (role === 'admin') return usersInMyDealers({ req });
  const id = idOf(req.user);
  return role !== null && id !== null ? { id: { equals: id } } : false;
};

const within = (ids: ReadonlyArray<string | number>, allowed: ReadonlyArray<string | number>) => {
  const set = new Set(allowed.map(String));
  return ids.every((id) => set.has(String(id)));
};

/**
 * Who may write a user (Payload rules 14 and 15):
 *  - nobody without a login: there is no self-registration, no first-user route and no system-job bypass (the seed job
 *    that creates a dealer's first admin is a reviewed follow-up that needs the override allowlist, issue #36);
 *  - a password is set only when an admin creates the user, and must pass the password rule. It is never changed by
 *    editing a user; the reset-link flow is closed until issue #73;
 *  - a new user needs at least one dealer, all of them the actor's own;
 *  - a user can be changed only if EVERY dealer the user belongs to is one of the actor's dealers, so an admin of dealer
 *    A can never change, move or take over a user who also works for dealer B;
 *  - new dealer rows must all be the actor's own, and must be well-formed.
 */
export const guardUserWrite: CollectionBeforeValidateHook = ({
  data,
  originalDoc,
  operation,
  req,
}) => {
  const actor = req.user;
  if (!actor) throw new Forbidden(req.t);
  if (data && 'password' in data) {
    if (operation === 'update') throw new Forbidden(req.t);
    const problem = passwordProblem(data['password'], data['email']);
    if (problem !== null) throw new APIError(problem, 400);
  }
  const allowed = tenantIdsOf(actor);
  if (operation === 'update' && !within(tenantIdsOf(originalDoc), allowed))
    throw new Forbidden(req.t);
  const rows: unknown = data?.['tenants'];
  if (rows === undefined) {
    if (operation === 'create') throw new Forbidden(req.t);
    return data;
  }
  const wanted = tenantIdsOf({ tenants: rows });
  const wellFormed = Array.isArray(rows) && wanted.length === rows.length;
  if (!wellFormed || (operation === 'create' && wanted.length === 0) || !within(wanted, allowed))
    throw new Forbidden(req.t);
  return data;
};

// Operations closed until the login surface (rate limits, trusted client IP, login audit) exists: issue #73.
const CLOSED_OPERATIONS: readonly string[] = ['forgotPassword', 'resetPassword'];
// A filter or sort under the dealer rows would test which dealers a user belongs to, or another dealer's name.
const DEALER_ROWS = /^-?tenants(\.|$)/;

const sortPaths = (sort: unknown): string[] =>
  (Array.isArray(sort) ? sort : [sort])
    .filter((part) => typeof part === 'string')
    .flatMap((part) => part.split(','))
    .map((part) => part.trim());

/**
 * Runs before every users operation (REST, GraphQL and the Local API):
 *  - forgot-password and reset-password are refused (fail closed until issue #73);
 *  - a deactivated user cannot refresh a token (their sessions are also ended when they are deactivated);
 *  - `where` and `sort` may not name the dealer rows (`tenants`, `tenants.tenant`, `tenants.tenant.name` ...): the
 *    access filter already limits the list to the reader's dealers, and a filter there could only probe other dealers.
 */
export const guardUserOperation: CollectionBeforeOperationHook = ({ args, operation, req }) => {
  if (CLOSED_OPERATIONS.includes(operation)) throw new Forbidden(req.t);
  if (operation === 'refresh' && isRecord(req.user) && req.user['active'] === false)
    throw new Forbidden(req.t);
  const given: unknown = args;
  const where = isRecord(given) ? given['where'] : undefined;
  const sort = isRecord(given) ? given['sort'] : undefined;
  const paths = [...wherePaths(where), ...sortPaths(sort)];
  if (paths.some((path) => DEALER_ROWS.test(path))) throw new Forbidden(req.t);
  return args;
};

/** A deactivated user cannot log in (access is already gone through `roleOf`; this also stops a new session). */
export const refuseInactiveLogin: CollectionBeforeLoginHook = ({ user }) => {
  if (user?.['active'] === false) throw new AuthenticationError();
};

// The email must not tell an admin of one dealer which addresses exist at another dealer.
const GENERIC_MESSAGE = 'The user could not be saved. Check the details and try again.';
export const hideDuplicateEmail: CollectionAfterErrorHook = ({ error }) => {
  if (error instanceof ValidationError && error.data.errors.some((e) => e.path === 'email')) {
    return { status: 400, response: { errors: [{ message: GENERIC_MESSAGE }] } };
  }
  return undefined;
};

const snapshot = (doc: unknown): Record<string, unknown> => {
  const record: Record<string, unknown> = isRecord(doc) ? { ...doc } : {};
  return {
    role: record['role'] ?? null,
    active: record['active'] ?? null,
    email: record['email'] ?? null,
    tenants: tenantIdsOf(record).map(String),
  };
};

/** Every user create, and every update that changes role, active, email or dealers. Fail closed: inside the write. */
export const auditUserChange =
  (audit: AuditLog): CollectionAfterChangeHook =>
  async ({ doc, previousDoc, operation, req }) => {
    const before = operation === 'update' ? snapshot(previousDoc) : undefined;
    const after = snapshot(doc);
    if (before && JSON.stringify(before) === JSON.stringify(after)) return doc;
    await audit.record({
      action: `user.${operation}`,
      actorId: idOf(req.user),
      target: { collection: USERS_COLLECTION, id: idOf(doc) },
      dealerIds: tenantIdsOf(doc),
      before,
      after,
    });
    return doc;
  };

/**
 * A user is never told about dealers they do not work for: the dealer rows of another person's record are cut to the
 * reader's own dealers. A person's own record is returned whole (login and the access rules read it).
 */
export const showOnlyMyDealers: CollectionAfterReadHook = ({ doc, req }) => {
  const reader = req.user;
  if (!reader || !isRecord(doc) || !Array.isArray(doc['tenants'])) return doc;
  const readerId = idOf(reader);
  if (readerId !== null && String(readerId) === String(idOf(doc))) return doc;
  const mine = new Set(tenantIdsOf(reader).map(String));
  const rows: unknown[] = doc['tenants'];
  return {
    ...doc,
    tenants: rows.filter((row) =>
      tenantIdsOf({ tenants: [row] }).some((id) => mine.has(String(id))),
    ),
  };
};

export const auditUserDelete =
  (audit: AuditLog): CollectionAfterDeleteHook =>
  async ({ doc, req }) => {
    await audit.record({
      action: 'user.delete',
      actorId: idOf(req.user),
      target: { collection: USERS_COLLECTION, id: idOf(doc) },
      dealerIds: tenantIdsOf(doc),
      before: snapshot(doc),
    });
    return doc;
  };

export const USER_FIELDS: Field[] = [
  {
    // Identity is never taken from the email (Payload rule 14): users are tied to dealers by the fixed IDs in
    // `tenants`. The email can be set on create only; a change needs a reviewed flow (current password and
    // re-verification), which is issue #61.
    name: 'email',
    type: 'email',
    required: true,
    unique: true,
    index: true,
    access: { create: isAdmin, update: denyAll },
  },
  {
    name: 'role',
    type: 'select',
    required: true,
    defaultValue: 'sales_rep',
    options: [...ROLE_OPTIONS],
    // Nobody but an admin can set a role, so no one can promote themselves.
    access: { create: isAdmin, update: isAdmin },
  },
  {
    // Deactivation replaces deletion. An inactive user has no role, so every access function says no, and every open
    // login ends (sessions.ts).
    name: 'active',
    type: 'checkbox',
    defaultValue: true,
    access: { create: isAdmin, update: isAdmin },
  },
];

export interface UsersOptions {
  /** Secure cookies (staging and production). */
  secureCookies: boolean;
  audit?: AuditLog;
}

export function buildUsers({ secureCookies, audit = accessAudit }: UsersOptions): CollectionConfig {
  return {
    slug: USERS_COLLECTION,
    admin: { useAsTitle: 'email' },
    auth: {
      tokenExpiration: 2 * 60 * 60, // seconds
      maxLoginAttempts: 5,
      lockTime: 10 * 60 * 1000, // milliseconds
      useSessions: true,
      verify: true,
      cookies: { secure: secureCookies, sameSite: 'Strict' },
    },
    access: {
      create: isAdmin,
      read: usersInMyDealers,
      update: canUpdateUser,
      // Users are deactivated (the `active` flag), never deleted, so the audit trail keeps its subjects.
      delete: denyAll,
      // Unlocking a locked account is a system job: an unlock-by-email could reach a user of another dealer.
      unlock: denyAll,
      readVersions: denyAll,
    },
    lockDocuments: false,
    hooks: {
      beforeOperation: [guardUserOperation],
      beforeValidate: [guardUserWrite],
      afterRead: [showOnlyMyDealers],
      beforeLogin: [refuseInactiveLogin],
      afterChange: [auditUserChange(audit), endSessionsOnDeactivate],
      afterDelete: [auditUserDelete(audit)],
      afterError: [hideDuplicateEmail],
    },
    // A copy: the multi-tenant plugin adds its `tenants` field to this array in place, once per built config.
    fields: [...USER_FIELDS],
  };
}
