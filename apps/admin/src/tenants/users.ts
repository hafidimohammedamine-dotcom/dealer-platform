import type { CollectionBeforeValidateHook, CollectionConfig } from 'payload';
import {
  adminFieldAccess,
  denyAll,
  denyFieldAccess,
  isAdmin,
  ROLE_OPTIONS,
  roleOf,
  tenantIdsOf,
  userIdOf,
} from '../access/roles.js';

export const USERS_SLUG = 'users';

/**
 * An admin may update any user of the dealer; everyone else only themself. Returning a filter (not true) is what keeps
 * a sales rep from editing a colleague: the plugin adds the dealer filter on top.
 */
export const canUpdateUser = ({
  req,
}: {
  req: { user?: unknown };
}): boolean | { id: { equals: string | number } } => {
  const role = roleOf(req.user);
  if (role === 'admin') return true;
  const id = userIdOf(req.user);
  return role !== null && id !== null ? { id: { equals: id } } : false;
};

// Only a logged-in admin can put a user into dealers, and only into dealers the admin belongs to. Without this an admin
// of dealer A could add a user to dealer B by writing B's ID in the `tenants` array.
export const enforceOwnDealers: CollectionBeforeValidateHook = ({ data, req }) => {
  const actor = req.user;
  if (!actor || !data) return data; // system jobs have no actor; they are reviewed one by one (override allowlist)
  const rows: unknown = data['tenants'];
  if (rows === undefined) return data;
  const allowed = tenantIdsOf(actor).map(String);
  const wanted = tenantIdsOf({ tenants: rows }).map(String);
  if (
    !Array.isArray(rows) ||
    wanted.length !== rows.length ||
    wanted.some((id) => !allowed.includes(id))
  ) {
    throw new Error('A user can only be placed in dealers you belong to.');
  }
  return data;
};

export const Users: CollectionConfig = {
  slug: USERS_SLUG,
  admin: { useAsTitle: 'email' },
  auth: {
    tokenExpiration: 2 * 60 * 60, // seconds
    maxLoginAttempts: 5,
    lockTime: 10 * 60 * 1000, // milliseconds
    useSessions: true,
    verify: false,
  },
  access: {
    create: isAdmin,
    // The plugin narrows these to the user themself or users who share a dealer.
    read: ({ req }) => roleOf(req.user) !== null,
    update: canUpdateUser,
    delete: isAdmin,
    unlock: isAdmin,
    readVersions: denyAll,
  },
  lockDocuments: false,
  hooks: { beforeValidate: [enforceOwnDealers] },
  fields: [
    {
      // Identity is never taken from the email (Payload rule 14): users are tied to dealers by the fixed IDs in
      // `tenants`. The email can be set on create only; a change needs a reviewed flow (current password and
      // re-verification), which is a follow-up.
      name: 'email',
      type: 'email',
      required: true,
      unique: true,
      index: true,
      access: { create: adminFieldAccess, update: denyFieldAccess },
    },
    {
      name: 'role',
      type: 'select',
      required: true,
      defaultValue: 'sales_rep',
      options: [...ROLE_OPTIONS],
      // Nobody but an admin can set a role, so no one can promote themselves.
      access: { create: adminFieldAccess, update: adminFieldAccess },
    },
  ],
};
