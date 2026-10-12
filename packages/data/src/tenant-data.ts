// The tenant-safe data helper (CLAUDE.md, Payload rules 1 and 2). Every read and write of CRM data goes through here.
//
// What this file guarantees for every call:
//  - the logged-in `user` is passed to Payload, and `overrideAccess` is always `false`;
//  - the dealer (tenant) is added to the query (`where`) and to the data (`create`, `update`), whatever the caller passed;
//  - `depth` is always explicit and capped, and `limit` is always bounded;
//  - the user must belong to the dealer (by fixed ID in `user.tenants`), or no helper is created;
//  - Payload's own collections (dealers, users, payload-*) cannot be reached from here.
// The Payload instance is never exported and never handed out.
import type { Where } from 'payload';

/** The dealer (tenant) ID. */
export type TenantId = string | number;

/** The logged-in user, as Payload gives it to us. Only the fields the helper reads are named. */
export interface DataUser {
  id: string | number;
  collection?: string;
  tenants?: ReadonlyArray<{ tenant: string | number | { id: string | number } | null }> | null;
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
export const MAX_DEPTH = 2;
export const DEFAULT_LIMIT = 50;
export const MAX_LIMIT = 200;

// Collections the helper refuses: they are not dealer-scoped by a `tenant` field, so they need their own reviewed paths.
const BLOCKED = /^(dealers|users|payload-.*)$/;

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

function tenantIdOf(entry: NonNullable<DataUser['tenants']>[number]): string | null {
  const value = entry.tenant;
  if (value === null) return null;
  if (typeof value === 'object') return String(value.id);
  return String(value);
}

function assertMember(user: DataUser, tenantId: TenantId): void {
  const ids = (user.tenants ?? []).map(tenantIdOf);
  if (!ids.includes(String(tenantId))) {
    throw new TenantAccessError('The user does not belong to this dealer.');
  }
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

export function forTenant(api: LocalApi, ctx: DataContext): TenantData {
  assertMember(ctx.user, ctx.tenantId);
  const { user, tenantId } = ctx;
  const context = { tenantId };
  const tenantClause = { [TENANT_FIELD]: { equals: tenantId } };
  const scope = (where?: DataWhere): DataWhere =>
    where ? { and: [where, tenantClause] } : tenantClause;
  const byID = (id: string | number): DataWhere => ({
    and: [{ id: { equals: id } }, tenantClause],
  });
  const base = (collection: string, depth: number | undefined): CallBase => {
    assertCollection(collection);
    return { collection, user, overrideAccess: false, depth: depthOf(depth), context };
  };

  return {
    find: (collection, options = {}) =>
      api.find({
        ...base(collection, options.depth),
        where: scope(options.where),
        ...(options.sort === undefined ? {} : { sort: options.sort }),
        ...(options.page === undefined ? {} : { page: options.page }),
        limit: limitOf(options.limit),
        pagination: true,
      }),

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

    create: (collection, data, options = {}) =>
      api.create({
        ...base(collection, options.depth),
        data: { ...data, [TENANT_FIELD]: tenantId },
      }),

    async update(collection, id, data, options = {}) {
      const result = await api.update({
        ...base(collection, options.depth),
        where: byID(id),
        data: { ...data, [TENANT_FIELD]: tenantId },
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
