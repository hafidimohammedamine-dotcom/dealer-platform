import { AuthenticationError, Forbidden, ValidationError } from 'payload';
import type {
  CollectionAfterChangeHook,
  CollectionAfterDeleteHook,
  CollectionAfterErrorHook,
  CollectionBeforeLoginHook,
  CollectionBeforeValidateHook,
  CollectionConfig,
  Where,
} from 'payload';
import { tenantIdsOf } from '@dealer/data';
import { denyAll, isAdmin, ROLE_OPTIONS, roleOf, userIdOf } from '../access/roles.js';
import type { AuditLog } from './audit.js';
import { accessAudit } from './audit.js';

export const USERS_SLUG = 'users';

/** Set on the request context by a reviewed system job (for example the first-admin seed). Never by a request. */
export const SYSTEM_JOB_CONTEXT = 'reviewedSystemJob';

// The only fields a request with no logged-in user may write: the password-reset token Payload stores itself.
const NO_ACTOR_FIELDS: readonly string[] = ['resetPasswordToken', 'resetPasswordExpiration'];

type UserScope = Where | false;

/**
 * The users a logged-in user may reach: themself, and anyone who works for one of their dealers. The multi-tenant plugin
 * adds the dealer field to this collection but does not filter it, so the filter is written here (tested with two dealers).
 */
export const usersInMyDealers = ({ req }: { req: { user?: unknown } }): UserScope => {
  const id = userIdOf(req.user);
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
  const id = userIdOf(req.user);
  return role !== null && id !== null ? { id: { equals: id } } : false;
};

const within = (ids: ReadonlyArray<string | number>, allowed: ReadonlyArray<string | number>) => {
  const set = new Set(allowed.map(String));
  return ids.every((id) => set.has(String(id)));
};

/**
 * Who may write a user (Payload rules 14 and 15; security findings 2, 5 and 36):
 *  - with no logged-in user, nothing but the reset-token fields, unless a reviewed system job set the context marker
 *    (this also shuts the first-user registration route on a fresh deploy);
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
  context,
}) => {
  const actor = req.user;
  if (!actor) {
    if (context[SYSTEM_JOB_CONTEXT] === true) return data;
    const keys = Object.keys(data ?? {});
    if (operation === 'update' && keys.length > 0 && keys.every((k) => NO_ACTOR_FIELDS.includes(k)))
      return data;
    throw new Forbidden(req.t);
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
  const record: Record<string, unknown> = typeof doc === 'object' && doc !== null ? { ...doc } : {};
  return {
    role: record['role'] ?? null,
    active: record['active'] ?? null,
    email: record['email'] ?? null,
    tenants: tenantIdsOf(record).map(String),
  };
};

export const auditUserChange =
  (audit: AuditLog): CollectionAfterChangeHook =>
  async ({ doc, previousDoc, operation, req }) => {
    const before = operation === 'update' ? snapshot(previousDoc) : undefined;
    const after = snapshot(doc);
    if (before && JSON.stringify(before) === JSON.stringify(after)) return doc; // e.g. a reset token, no access change
    await audit.record({
      action: `user.${operation}`,
      actorId: userIdOf(req.user),
      target: { collection: USERS_SLUG, id: userIdOf(doc) },
      dealerIds: tenantIdsOf(doc),
      before,
      after,
    });
    return doc;
  };

export const auditUserDelete =
  (audit: AuditLog): CollectionAfterDeleteHook =>
  async ({ doc, req }) => {
    await audit.record({
      action: 'user.delete',
      actorId: userIdOf(req.user),
      target: { collection: USERS_SLUG, id: userIdOf(doc) },
      dealerIds: tenantIdsOf(doc),
      before: snapshot(doc),
    });
    return doc;
  };

export interface UsersOptions {
  /** Secure cookies (staging and production). */
  secureCookies: boolean;
  audit?: AuditLog;
}

export function buildUsers({ secureCookies, audit = accessAudit }: UsersOptions): CollectionConfig {
  return {
    slug: USERS_SLUG,
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
      beforeValidate: [guardUserWrite],
      beforeLogin: [refuseInactiveLogin],
      afterChange: [auditUserChange(audit)],
      afterDelete: [auditUserDelete(audit)],
      afterError: [hideDuplicateEmail],
    },
    fields: [
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
        // Deactivation replaces deletion. An inactive user has no role, so every access function says no.
        name: 'active',
        type: 'checkbox',
        defaultValue: true,
        access: { create: isAdmin, update: isAdmin },
      },
    ],
  };
}
