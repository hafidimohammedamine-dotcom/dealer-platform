import type { DataContext, DataUser, TenantData } from './tenant-data.js';
import type { LocalApi } from './tenant-data.js';
import {
  isRecord,
  TenantAccessError,
  tenantIdsOf,
  USERS_COLLECTION,
  validId,
} from './tenant-data.js';
import { methods } from './tenant-methods.js';

/**
 * Builds the helper for the person making the request and one dealer. Who that is comes only from Payload's built-in
 * `auth` over the request headers (the login cookie or token, checked against the user's live sessions), so a caller
 * cannot name a user. A missing, deactivated or other-dealer user gets no helper.
 */
export async function forTenant(api: LocalApi, ctx: DataContext): Promise<TenantData> {
  if (!validId(ctx.tenantId)) throw new TenantAccessError('A dealer ID is required.');
  const { user: found } = await api.auth({ headers: ctx.headers });
  if (
    !isRecord(found) ||
    !validId(found['id']) ||
    found['collection'] !== USERS_COLLECTION ||
    found['active'] === false
  ) {
    throw new TenantAccessError('The user could not be verified.');
  }
  const member = tenantIdsOf(found).some((id) => String(id) === String(ctx.tenantId));
  if (!member) throw new TenantAccessError('The user does not belong to this dealer.');
  const user: DataUser = { ...found, id: found['id'], collection: USERS_COLLECTION };
  return methods(api, { user, tenantId: ctx.tenantId });
}
