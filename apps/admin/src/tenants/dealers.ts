import type { CollectionConfig } from 'payload';
import { denyAll, isAdmin, isStaff } from '../access/roles.js';

export const DEALERS_SLUG = 'dealers';

// The tenants collection: one document per dealership. The multi-tenant plugin limits every query to the dealers on the
// logged-in user. Creating and deleting dealers is not allowed through the API; onboarding is a reviewed system job.
export const Dealers: CollectionConfig = {
  slug: DEALERS_SLUG,
  admin: { useAsTitle: 'name' },
  access: {
    create: denyAll,
    read: isStaff,
    update: isAdmin,
    delete: denyAll,
    readVersions: denyAll,
  },
  lockDocuments: false,
  fields: [
    { name: 'name', type: 'text', required: true },
    { name: 'slug', type: 'text', required: true, unique: true, index: true },
  ],
};
