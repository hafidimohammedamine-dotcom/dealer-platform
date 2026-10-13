import type { CollectionConfig } from 'payload';

// Every dealer-scoped collection (customers, leads, vehicles ...) is added to this list, and only here. The list feeds
// the multi-tenant plugin, so a collection that is not in it has no dealer field and no dealer filter, and the
// deny-by-default test (deny-by-default.ts) fails CI for it. Builders ask devops with `REQUEST:` to add theirs until
// the CRM and inventory folders export their collections.
export const tenantScopedCollections: CollectionConfig[] = [];

// Collections that are deliberately not dealer-scoped. Short, reviewed, and empty today.
export const notTenantScopedAllowlist: readonly string[] = [];
