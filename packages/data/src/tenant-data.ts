// The tenant-safe data helper (CLAUDE.md, Payload rules 1 and 2). Every read and write of CRM data goes through here.
//
// What this file guarantees for every call:
//  - the user is loaded again from the database by ID, must belong to the dealer there (not in the object the caller
//    built), and that fresh record is the `user` passed to Payload, with `overrideAccess` always `false`;
//  - the dealer (tenant) is added to the query (`where`) and to the data (`create`, `update`), whatever the caller passed;
//  - `depth`, `draft`, `limit` and `pagination` are always explicit, `depth` and `limit` are capped;
//  - Payload's own collections (dealers, users, payload-*) cannot be reached from here.
// The Payload instance is never exported and never handed out. The caller must pass the `req.user` that Payload's own
// login produced; this package cannot authenticate anyone by itself.
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
  user: DataUser;
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
interface CallBase {
  collection: string;
  user: DataUser;
  overrideAccess: false;
  depth: number;
  draft: false;
  context: { tenantId: TenantId };
}
interface FindCall extends CallBase {
  where: DataWhere;
  sort?: string;
  limit: number;
  page?: number;
  pagination: boolean;
}
export interface LocalApi {
  find(args: FindCall): Promise<{ docs: unknown[]; totalDocs?: number }>;
  findByID(args: {
    collection: string;
    id: string | number;
    user: DataUser;
    overrideAccess: false;
    depth: number;
    draft: false;
    disableErrors: true;
  }): Promise<unknown>;
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
export const USERS_COLLECTION = 'users';
export const MAX_DEPTH = 2;
export const DEFAULT_LIMIT = 50;
export const MAX_LIMIT = 200;
export const MAX_PAGE = 1_000_000;

// Collections the helper refuses: they are not dealer-scoped by a `tenant` field, so they need their own reviewed paths.
const BLOCKED = /^(dealers|users|payload-.*)$/;
const SORT = /^-?[A-Za-z_][A-Za-z0-9_.]{0,63}$/;

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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function validId(value: unknown): value is TenantId {
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

function assertCollection(collection: string): void {
  if (BLOCKED.test(collection)) {
    throw new TenantAccessError(
      `The collection "${collection}" cannot be used through the tenant data helper.`,
    );
  }
}

function depthOf(depth: number | undefined): number {
  const value = depth ?? 0;
  if (!Number.isInteger(value) || value < 0 || value > MAX_DEPTH) {
    throw new RangeError(`depth must be a whole number from 0 to ${MAX_DEPTH}.`);
  }
  return value;
}

function limitOf(limit: number | undefined): number {
  const value = limit ?? DEFAULT_LIMIT;
  if (!Number.isInteger(value) || value < 1) {
    throw new RangeError('limit must be a whole number of at least 1.');
  }
  return Math.min(value, MAX_LIMIT);
}

function pageOf(page: number): number {
  if (!Number.isInteger(page) || page < 1 || page > MAX_PAGE) {
    throw new RangeError(`page must be a whole number from 1 to ${MAX_PAGE}.`);
  }
  return page;
}

function sortOf(sort: string): string {
  if (!SORT.test(sort)) throw new RangeError('sort must be one field name, optionally with a "-".');
  return sort;
}

/** The caller's data without `id` and without a `tenant`: the dealer is always ours. */
function ownData(data: Record<string, unknown>, tenantId: TenantId): Record<string, unknown> {
  const own: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(data)) {
    if (key !== 'id' && key !== TENANT_FIELD) own[key] = value;
  }
  own[TENANT_FIELD] = tenantId;
  return own;
}

interface Scope {
  user: DataUser;
  tenantId: TenantId;
}

function methods(api: LocalApi, { user, tenantId }: Scope): TenantData {
  const context = { tenantId };
  const tenantClause: DataWhere = { [TENANT_FIELD]: { equals: tenantId } };
  const scope = (where?: DataWhere): DataWhere =>
    where ? { and: [where, tenantClause] } : tenantClause;
  const byID = (id: string | number): DataWhere => ({
    and: [{ id: { equals: id } }, tenantClause],
  });
  const base = (collection: string, depth: number | undefined): CallBase => {
    assertCollection(collection);
    return {
      collection,
      user,
      overrideAccess: false,
      depth: depthOf(depth),
      draft: false,
      context,
    };
  };

  return {
    async find(collection, options = {}) {
      return api.find({
        ...base(collection, options.depth),
        where: scope(options.where),
        ...(options.sort === undefined ? {} : { sort: sortOf(options.sort) }),
        ...(options.page === undefined ? {} : { page: pageOf(options.page) }),
        limit: limitOf(options.limit),
        pagination: options.pagination ?? false,
      });
    },

    async findByID(collection, id, options = {}) {
      const result = await api.find({
        ...base(collection, options.depth),
        where: byID(id),
        limit: 1,
        pagination: false,
      });
      return result.docs[0] ?? null;
    },

    async count(collection, where) {
      assertCollection(collection);
      const result = await api.count({
        collection,
        where: scope(where),
        user,
        overrideAccess: false,
        context,
      });
      return result.totalDocs;
    },

    async create(collection, data, options = {}) {
      return api.create({
        ...base(collection, options.depth),
        data: ownData(data, tenantId),
      });
    },

    async update(collection, id, data, options = {}) {
      const result = await api.update({
        ...base(collection, options.depth),
        where: byID(id),
        data: ownData(data, tenantId),
      });
      const doc = result.docs[0];
      if (doc === undefined) throw new NotFoundError('Record not found.');
      return doc;
    },

    async delete(collection, id) {
      const result = await api.delete({ ...base(collection, 0), where: byID(id) });
      const doc = result.docs[0];
      if (doc === undefined) throw new NotFoundError('Record not found.');
      return doc;
    },
  };
}

/**
 * Builds the helper for one user and one dealer. The user is read again by ID (under its own access) so the dealer list
 * and role come from the database, not from the object the caller passed. A missing, deactivated or other-dealer user
 * gets no helper.
 */
export async function forTenant(api: LocalApi, ctx: DataContext): Promise<TenantData> {
  if (!validId(ctx.tenantId)) throw new TenantAccessError('A dealer ID is required.');
  if (!validId(ctx.user.id)) throw new TenantAccessError('A logged-in user is required.');
  const loaded = await api.findByID({
    collection: USERS_COLLECTION,
    id: ctx.user.id,
    user: ctx.user,
    overrideAccess: false,
    depth: 0,
    draft: false,
    disableErrors: true,
  });
  if (
    !isRecord(loaded) ||
    String(loaded['id']) !== String(ctx.user.id) ||
    loaded['active'] === false
  ) {
    throw new TenantAccessError('The user could not be verified.');
  }
  const member = tenantIdsOf(loaded).some((id) => String(id) === String(ctx.tenantId));
  if (!member) throw new TenantAccessError('The user does not belong to this dealer.');
  const user: DataUser = { ...loaded, id: ctx.user.id, collection: USERS_COLLECTION };
  return methods(api, { user, tenantId: ctx.tenantId });
}
