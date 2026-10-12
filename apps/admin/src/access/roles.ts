// The access functions read only `req.user`, so they are typed on just that. They still plug in as Payload `Access`
// and `FieldAccess` (a function that needs less is accepted where more is offered).
interface UserArgs {
  req: { user?: unknown };
}

// Roles (issue #5). `admin` is a dealer's own administrator: it never reaches another dealer (the multi-tenant plugin
// limits every query to the dealer IDs on the user, and `userHasAccessToAllTenants` is always false).
export const ROLES = ['admin', 'desking_manager', 'sales_rep', 'bdc'] as const;
export type Role = (typeof ROLES)[number];

export const ROLE_OPTIONS = [
  { label: 'Admin', value: 'admin' },
  { label: 'Desking manager', value: 'desking_manager' },
  { label: 'Sales rep', value: 'sales_rep' },
  { label: 'BDC', value: 'bdc' },
] as const satisfies ReadonlyArray<{ label: string; value: Role }>;

function isRole(value: unknown): value is Role {
  return ROLES.some((role) => role === value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/** The role of a logged-in user, or null (no user, or an unknown value: deny by default). */
export function roleOf(user: unknown): Role | null {
  if (!isRecord(user)) return null;
  const role = user['role'];
  return isRole(role) ? role : null;
}

/** The dealer IDs on a user, read from the fixed `tenants` array (never from the email or any editable text). */
export function tenantIdsOf(user: unknown): Array<string | number> {
  if (!isRecord(user)) return [];
  const rows = user['tenants'];
  if (!Array.isArray(rows)) return [];
  const ids: Array<string | number> = [];
  for (const row of rows) {
    if (!isRecord(row)) continue;
    const tenant = row['tenant'];
    if (typeof tenant === 'string' || typeof tenant === 'number') ids.push(tenant);
    else if (isRecord(tenant)) {
      const id = tenant['id'];
      if (typeof id === 'string' || typeof id === 'number') ids.push(id);
    }
  }
  return ids;
}

export function userIdOf(user: unknown): string | number | null {
  if (!isRecord(user)) return null;
  const id = user['id'];
  return typeof id === 'string' || typeof id === 'number' ? id : null;
}

export const denyAll = (): boolean => false;

/** Any logged-in user with a known role. The multi-tenant plugin then adds the dealer filter. */
export const isStaff = ({ req }: UserArgs): boolean => roleOf(req.user) !== null;

export const isAdmin = ({ req }: UserArgs): boolean => roleOf(req.user) === 'admin';

export const hasRole =
  (...allowed: Role[]) =>
  ({ req }: UserArgs): boolean => {
    const role = roleOf(req.user);
    return role !== null && allowed.includes(role);
  };

export const adminFieldAccess = ({ req }: UserArgs): boolean => roleOf(req.user) === 'admin';
export const denyFieldAccess = (): boolean => false;
