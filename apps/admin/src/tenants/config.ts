import { postgresAdapter } from '@payloadcms/db-postgres';
import { multiTenantPlugin } from '@payloadcms/plugin-multi-tenant';
import type { CollectionConfig, Config } from 'payload';
import { adminFieldAccess } from '../access/roles.js';
import { Dealers, DEALERS_SLUG } from './dealers.js';
import type { AppEnv } from './env.js';
import { tenantScopedCollections } from './registry.js';
import { Users, USERS_SLUG } from './users.js';

export interface BuildOptions {
  env: AppEnv;
  /** Tests pass their own list; production uses the registry. */
  scoped?: CollectionConfig[];
}

export function buildAppConfig({ env, scoped = tenantScopedCollections }: BuildOptions): Config {
  const collections = [Dealers, Users, ...scoped];
  return {
    secret: env.secret,
    serverURL: env.serverURL,
    cors: [env.serverURL],
    csrf: [env.serverURL],
    admin: { user: USERS_SLUG },
    collections,
    // Migrations only (Payload rule 5): `push` is off everywhere, and migrations run as one CI job, never at start.
    db: postgresAdapter({
      pool: { connectionString: env.databaseUrl },
      push: false,
      idType: 'uuid',
      migrationDir: './migrations',
    }),
    plugins: [
      multiTenantPlugin({
        tenantsSlug: DEALERS_SLUG,
        collections: Object.fromEntries(scoped.map((collection) => [collection.slug, {}])),
        // Nobody sees across dealers, not even an admin. Platform staff access is a separate reviewed follow-up.
        userHasAccessToAllTenants: () => false,
        cleanupAfterTenantDelete: false,
        tenantsArrayField: {
          includeDefaultField: true,
          arrayFieldAccess: { create: adminFieldAccess, update: adminFieldAccess },
          tenantFieldAccess: { create: adminFieldAccess, update: adminFieldAccess },
        },
      }),
    ],
    graphQL: { disablePlaygroundInProduction: true },
  };
}
