export {
  forTenant,
  TenantAccessError,
  NotFoundError,
  TENANT_FIELD,
  MAX_DEPTH,
  DEFAULT_LIMIT,
  MAX_LIMIT,
} from './tenant-data.js';
export type {
  TenantData,
  DataContext,
  DataUser,
  DataWhere,
  FindOptions,
  ReadOptions,
  LocalApi,
  TenantId,
} from './tenant-data.js';

// A real statement keeps this file inside the per-file coverage rule (a file of pure re-exports counts as 0%).
export const packageName = '@dealer/data';
