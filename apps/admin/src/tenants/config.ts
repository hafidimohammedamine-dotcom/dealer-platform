import { postgresAdapter } from '@payloadcms/db-postgres';
import { multiTenantPlugin } from '@payloadcms/plugin-multi-tenant';
import type { CollectionConfig, Config } from 'payload';
import { resendAdapter } from '@payloadcms/email-resend';
import { fileURLToPath } from 'node:url';
import { isAdmin } from '../access/roles.js';
import { Dealers, DEALERS_SLUG } from './dealers.js';
import type { AppEnv } from './env.js';
import { tenantScopedCollections } from './registry.js';
import { buildUsers, USERS_SLUG } from './users.js';

export interface BuildOptions {
  env: AppEnv;
  /** Tests pass their own list; production uses the registry. */
  scoped?: CollectionConfig[];
}

export const neverAllDealers = (): boolean => false;

export function buildAppConfig({ env, scoped = tenantScopedCollections }: BuildOptions): Config {
  const collections = [Dealers, buildUsers({ secureCookies: env.production }), ...scoped];
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
      // Next to the app, whatever the working directory (src/tenants and dist/tenants are both two levels down).
      migrationDir: fileURLToPath(new URL('../../migrations', import.meta.url)),
    }),
    plugins: [
      multiTenantPlugin({
        tenantsSlug: DEALERS_SLUG,
        collections: Object.fromEntries(scoped.map((collection) => [collection.slug, {}])),
        // Nobody sees across dealers, not even an admin. Platform staff access is a separate reviewed follow-up.
        userHasAccessToAllTenants: neverAllDealers,
        cleanupAfterTenantDelete: false,
        tenantsArrayField: {
          includeDefaultField: true,
          arrayFieldAccess: { create: isAdmin, update: isAdmin },
          tenantFieldAccess: { create: isAdmin, update: isAdmin },
        },
      }),
    ],
    ...(env.email
      ? {
          email: resendAdapter({
            apiKey: env.email.apiKey,
            defaultFromAddress: env.email.from,
            defaultFromName: 'Dealer Platform',
          }),
        }
      : {}),
    graphQL: { disablePlaygroundInProduction: true },
  };
}
