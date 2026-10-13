import type { Access, CollectionAfterChangeHook, CollectionConfig } from 'payload';
import { tenantIdsOf } from '@dealer/data';
import { denyAll, isAdmin, roleOf, userIdOf } from '../access/roles.js';
import type { AuditLog } from './audit.js';
import { accessAudit } from './audit.js';

export const DEALERS_SLUG = 'dealers';

// A dealer sees only its own dealers: the filter is written here, not left to the plugin (which is tested separately).
const ownDealers = (user: unknown): { id: { in: Array<string | number> } } | false => {
  const ids = tenantIdsOf(user);
  return roleOf(user) !== null && ids.length > 0 ? { id: { in: ids } } : false;
};

export const readOwnDealers: Access = ({ req }) => ownDealers(req.user);
export const updateOwnDealers: Access = ({ req }) =>
  isAdmin({ req }) ? ownDealers(req.user) : false;

export const auditDealerChange =
  (audit: AuditLog): CollectionAfterChangeHook =>
  async ({ doc, previousDoc, operation, req }) => {
    const pick = (d: unknown) => ({
      name: typeof d === 'object' && d !== null && 'name' in d ? d.name : null,
    });
    await audit.record({
      action: `dealer.${operation}`,
      actorId: userIdOf(req.user),
      target: { collection: DEALERS_SLUG, id: userIdOf(doc) },
      dealerIds: [userIdOf(doc) ?? ''],
      before: operation === 'update' ? pick(previousDoc) : undefined,
      after: pick(doc),
    });
    return doc;
  };

// The tenants collection: one document per dealership. Creating and deleting dealers is not allowed through the API;
// onboarding is a reviewed system job. The `slug` can be set once and never changed through the API.
export const Dealers: CollectionConfig = {
  slug: DEALERS_SLUG,
  admin: { useAsTitle: 'name' },
  access: {
    create: denyAll,
    read: readOwnDealers,
    update: updateOwnDealers,
    delete: denyAll,
    readVersions: denyAll,
  },
  lockDocuments: false,
  hooks: { afterChange: [auditDealerChange(accessAudit)] },
  fields: [
    { name: 'name', type: 'text', required: true },
    {
      name: 'slug',
      type: 'text',
      required: true,
      unique: true,
      index: true,
      access: { update: denyAll },
    },
  ],
};
