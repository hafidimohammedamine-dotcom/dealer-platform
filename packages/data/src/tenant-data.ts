// The tenant-safe data helper (CLAUDE.md, Payload rules 1 and 2). Every read and write of CRM data goes through here.
//
// What this file guarantees for every call:
//  - the user is the one Payload's own `auth` finds from the request headers (the login cookie or token, checked
//    against the user's live sessions), never an object the caller built; it must be active and belong to the dealer,
//    and that record is the `user` passed to Payload, with `overrideAccess` always `false`;
//  - `where` may only name the collection's own fields: a dotted path (through a linked record) is refused;
//  - the dealer (tenant) is added to the query (`where`) and to the data (`create`, `update`), whatever the caller passed;
//  - `depth`, `draft`, `limit` and `pagination` are always explicit, `depth` and `limit` are capped;
//  - Payload's own collections (dealers, users, payload-*) cannot be reached from here.
// The Payload instance is never exported and never handed out. The caller passes the request headers; identity comes
// only from Payload's built-in login (Payload rule 14).
//
// Second lock: row-level security in Postgres is tracked in issue #58 and is NOT in place yet. `context.tenantId` is
// passed on so the future database layer can set the dealer per transaction.
import type { Where } from 'payload';

/** The dealer (tenant) ID. */
export type TenantId = string | number;

/** The logged-in user, as Payload gives it to us. Only the fields the helper reads are named. */
export interface DataUser {
  id: string | number;
  collection?: string;
  tenants?: ReadonlyArray<{ tenant: unknown }> | null;
  [field: string]: unknown;
}

export interface DataContext {
  /** The incoming request's headers. Payload reads the login cookie or token from them. */
  headers: Headers;
  tenantId: TenantId;
}

/** Payload's `where` filter, kept loose on purpose: Payload validates it against the collection. */
export type DataWhere = Where;

export interface FindOptions {
  where?: DataWhere;
  sort?: string;
  limit?: number;
  page?: number;
  depth?: number;
  /** Count pages? Off by default (Payload rule 10): it costs a second query on every list. */
  pagination?: boolean;
}

export interface ReadOptions {
  depth?: number;
}

// The part of Payload's Local API the helper uses (structural, so tests can fake it and the real instance fits).
export interface CallBase {
  collection: string;
  user: DataUser;
  overrideAccess: false;
  depth: number;
  draft: false;
  context: { tenantId: TenantId };
}
export interface FindCall extends CallBase {
  where: DataWhere;
  sort?: string;
  limit: number;
  page?: number;
  pagination: boolean;
}
export interface LocalApi {
  find(args: FindCall): Promise<{ docs: unknown[]; totalDocs?: number }>;
  auth(args: { headers: Headers }): Promise<{ user: unknown }>;
  count(args: {
    collection: string;
    where: DataWhere;
    user: DataUser;
    overrideAccess: false;
    context: { tenantId: TenantId };
  }): Promise<{ totalDocs: number }>;
  create(args: CallBase & { data: Record<string, unknown> }): Promise<unknown>;
  update(
    args: CallBase & { where: DataWhere; data: Record<string, unknown> },
  ): Promise<{ docs: unknown[] }>;
  delete(args: CallBase & { where: DataWhere }): Promise<{ docs: unknown[] }>;
}

export const TENANT_FIELD = 'tenant';
/** The slug of Payload's users collection, shared by the admin app and this package. */
export const USERS_COLLECTION = 'users';
export const MAX_DEPTH = 2;
export const DEFAULT_LIMIT = 50;
export const MAX_LIMIT = 200;
export const MAX_PAGE = 1_000_000;

// Collections the helper refuses: they are not dealer-scoped by a `tenant` field, so they need their own reviewed paths.
const BLOCKED = /^(dealers|users|payload-.*)$/;
// One top-level field name. A dotted path would sort through a linked record; allowed again only when the leak suite
// (issue #60) proves sorting respects access on linked records.
const SORT = /^-?[A-Za-z_][A-Za-z0-9_]{0,63}$/;
// Payload's `where` operators. A key that is not one of these, inside a field's condition, is read as a deeper path.
const OPERATORS = new Set([
  'equals',
  'not_equals',
  'in',
  'not_in',
  'all',
  'exists',
  'greater_than',
  'greater_than_equal',
  'less_than',
  'less_than_equal',
  'like',
  'not_like',
  'contains',
  'near',
  'within',
  'intersects',
]);
const AND_OR = /^(and|or)$/i;

export class TenantAccessError extends Error {
  override readonly name = 'TenantAccessError';
}
export class NotFoundError extends Error {
  override readonly name = 'NotFoundError';
}

export interface TenantData {
  find(collection: string, options?: FindOptions): Promise<{ docs: unknown[]; totalDocs?: number }>;
  findByID(collection: string, id: string | number, options?: ReadOptions): Promise<unknown>;
  count(collection: string, where?: DataWhere): Promise<number>;
  create(
    collection: string,
    data: Record<string, unknown>,
    options?: ReadOptions,
  ): Promise<unknown>;
  update(
    collection: string,
    id: string | number,
    data: Record<string, unknown>,
    options?: ReadOptions,
  ): Promise<unknown>;
  delete(collection: string, id: string | number): Promise<unknown>;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export function validId(value: unknown): value is TenantId {
  if (typeof value === 'string') return value.trim() !== '';
  return typeof value === 'number' && Number.isSafeInteger(value);
}

/**
 * The dealer IDs on a user, from the fixed `tenants` array. Strict: a row counts only when its ID is a non-empty string
 * or a whole number (bare, or as `{ id }` when populated). Anything else is skipped, never guessed.
 */
export function tenantIdsOf(user: unknown): TenantId[] {
  if (!isRecord(user)) return [];
  const rows = user['tenants'];
  if (!Array.isArray(rows)) return [];
  const ids: TenantId[] = [];
  for (const row of rows) {
    if (!isRecord(row)) continue;
    const tenant = row['tenant'];
    const id = isRecord(tenant) ? tenant['id'] : tenant;
    if (validId(id)) ids.push(id);
  }
  return ids;
}

export function assertCollection(collection: string): void {
  if (BLOCKED.test(collection)) {
    throw new TenantAccessError(
      `The collection "${collection}" cannot be used through the tenant data helper.`,
    );
  }
}

export function depthOf(depth: number | undefined): number {
  const value = depth ?? 0;
  if (!Number.isInteger(value) || value < 0 || value > MAX_DEPTH) {
    throw new RangeError(`depth must be a whole number from 0 to ${MAX_DEPTH}.`);
  }
  return value;
}

export function limitOf(limit: number | undefined): number {
  const value = limit ?? DEFAULT_LIMIT;
  if (!Number.isInteger(value) || value < 1) {
    throw new RangeError('limit must be a whole number of at least 1.');
  }
  return Math.min(value, MAX_LIMIT);
}

export function pageOf(page: number): number {
  if (!Number.isInteger(page) || page < 1 || page > MAX_PAGE) {
    throw new RangeError(`page must be a whole number from 1 to ${MAX_PAGE}.`);
  }
  return page;
}

/**
 * Every field path a `where` names, through `and`/`or` at any depth. Both spellings of a deeper path count:
 * `{ 'a.b': {...} }` and `{ a: { b: {...} } }` both give `a.b`.
 */
export function wherePaths(where: unknown, prefix = ''): string[] {
  if (!isRecord(where)) return [];
  return Object.entries(where).flatMap(([key, value]) => {
    if (prefix === '' && AND_OR.test(key)) {
      return (Array.isArray(value) ? value : [value]).flatMap((part) => wherePaths(part));
    }
    const path = `${prefix}${key}`;
    if (!isRecord(value)) return [path];
    const deeper = Object.entries(value).filter(([name]) => !OPERATORS.has(name));
    const own = deeper.length < Object.keys(value).length ? [path] : [];
    return [...own, ...wherePaths(Object.fromEntries(deeper), `${path}.`)];
  });
}

/** Refuses a `where` that filters through a linked record (a dotted path), which could test another dealer's data. */
export function flatWhere(where: DataWhere): DataWhere {
  const deep = wherePaths(where).filter((path) => path.includes('.'));
  if (deep.length > 0) {
    throw new TenantAccessError(
      `where may only name the collection's own fields, not ${deep.join(', ')}.`,
    );
  }
  return where;
}

export function sortOf(sort: string): string {
  if (!SORT.test(sort)) throw new RangeError('sort must be one field name, optionally with a "-".');
  return sort;
}

/** The caller's data without `id` and without a `tenant`: the dealer is always ours. */
export function ownData(
  data: Record<string, unknown>,
  tenantId: TenantId,
): Record<string, unknown> {
  const own: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    if (key !== 'id' && key !== TENANT_FIELD) own[key] = value;
  }
  own[TENANT_FIELD] = tenantId;
  return own;
}

export interface Scope {
  user: DataUser;
  tenantId: TenantId;
}
