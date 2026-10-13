// The six data methods, each a small function over the scope (user, dealer). Every call passes the fresh user,
// `overrideAccess: false`, an explicit `depth` and `draft`, and the dealer in the query or the data.
import type { CallBase, DataWhere, LocalApi, Scope, TenantData } from './tenant-data.js';
import {
  assertCollection,
  depthOf,
  flatWhere,
  limitOf,
  NotFoundError,
  ownData,
  pageOf,
  sortOf,
  TENANT_FIELD,
} from './tenant-data.js';

const tenantClause = ({ tenantId }: Scope): DataWhere => ({ [TENANT_FIELD]: { equals: tenantId } });
const scoped = (scope: Scope, where?: DataWhere): DataWhere =>
  where ? { and: [flatWhere(where), tenantClause(scope)] } : tenantClause(scope);
const byID = (scope: Scope, id: string | number): DataWhere => ({
  and: [{ id: { equals: id } }, tenantClause(scope)],
});

function base(scope: Scope, collection: string, depth: number | undefined): CallBase {
  assertCollection(collection);
  return {
    collection,
    user: scope.user,
    overrideAccess: false,
    depth: depthOf(depth),
    draft: false,
    context: { tenantId: scope.tenantId },
  };
}

const find =
  (api: LocalApi, scope: Scope): TenantData['find'] =>
  async (collection, options = {}) =>
    api.find({
      ...base(scope, collection, options.depth),
      where: scoped(scope, options.where),
      ...(options.sort === undefined ? {} : { sort: sortOf(options.sort) }),
      ...(options.page === undefined ? {} : { page: pageOf(options.page) }),
      limit: limitOf(options.limit),
      pagination: options.pagination ?? false,
    });

const findByID =
  (api: LocalApi, scope: Scope): TenantData['findByID'] =>
  async (collection, id, options = {}) => {
    const result = await api.find({
      ...base(scope, collection, options.depth),
      where: byID(scope, id),
      limit: 1,
      pagination: false,
    });
    return result.docs[0] ?? null;
  };

const count =
  (api: LocalApi, scope: Scope): TenantData['count'] =>
  async (collection, where) => {
    assertCollection(collection);
    const result = await api.count({
      collection,
      where: scoped(scope, where),
      user: scope.user,
      overrideAccess: false,
      context: { tenantId: scope.tenantId },
    });
    return result.totalDocs;
  };

const create =
  (api: LocalApi, scope: Scope): TenantData['create'] =>
  async (collection, data, options = {}) =>
    api.create({
      ...base(scope, collection, options.depth),
      data: ownData(data, scope.tenantId),
    });

const update =
  (api: LocalApi, scope: Scope): TenantData['update'] =>
  async (collection, id, data, options = {}) => {
    const result = await api.update({
      ...base(scope, collection, options.depth),
      where: byID(scope, id),
      data: ownData(data, scope.tenantId),
    });
    const doc = result.docs[0];
    if (doc === undefined) throw new NotFoundError('Record not found.');
    return doc;
  };

const remove =
  (api: LocalApi, scope: Scope): TenantData['delete'] =>
  async (collection, id) => {
    const result = await api.delete({ ...base(scope, collection, 0), where: byID(scope, id) });
    const doc = result.docs[0];
    if (doc === undefined) throw new NotFoundError('Record not found.');
    return doc;
  };

export function methods(api: LocalApi, scope: Scope): TenantData {
  return {
    find: find(api, scope),
    findByID: findByID(api, scope),
    count: count(api, scope),
    create: create(api, scope),
    update: update(api, scope),
    delete: remove(api, scope),
  };
}
