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

/**
 * The role of a logged-in user, or null (no user, an unknown value, or a deactivated user: deny by default). Users are
 * never deleted; setting `active` to false removes every right at once.
 */
export function roleOf(user: unknown): Role | null {
  if (!isRecord(user) || user['active'] === false) return null;
  const role = user['role'];
  return isRole(role) ? role : null;
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
