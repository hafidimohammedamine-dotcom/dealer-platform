import { denyAll } from '../access/roles.js';

export const MIGRATIONS_SLUG = 'payload-migrations';

interface Lockable {
  slug: string;
  access: {
    create?: unknown;
    read?: unknown;
    update?: unknown;
    delete?: unknown;
  };
}

/**
 * Payload 3.90.2 adds `payload-migrations` with no access rules, so its default applies: every logged-in user, of any
 * dealer, could read, add, change or delete migration records over REST. Nobody needs to: the migration job talks to the
 * database directly. Runs once at start-up (`onInit`) on the final, sanitized config, which is the first moment the
 * collection exists. A test applies the same function and proves the access is closed.
 */
export function lockBuiltInCollections(config: { collections: Lockable[] }): void {
  for (const collection of config.collections) {
    if (collection.slug !== MIGRATIONS_SLUG) continue;
    collection.access = {
      ...collection.access,
      create: denyAll,
      read: denyAll,
      update: denyAll,
      delete: denyAll,
    };
  }
}
