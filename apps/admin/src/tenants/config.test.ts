import { existsSync } from 'node:fs';
import { buildConfig, type CollectionConfig } from 'payload';
import { describe, expect, it } from 'vitest';
import { denyAll, isStaff } from '../access/roles.js';
import { buildAppConfig, neverAllDealers } from './config.js';
import {
  denyByDefaultProblems,
  PAYLOAD_BUILT_IN,
  sanitizedConfigProblems,
} from './deny-by-default.js';
import type { AppEnv } from './env.js';
import { gateProblems, securityGates } from './readiness.js';
import { notTenantScopedAllowlist, tenantScopedCollections } from './registry.js';

const devEnv: AppEnv = {
  stage: 'dev',
  production: false,
  secret: 'x'.repeat(40),
  databaseUrl: 'postgres://app_user:fake@localhost:5432/dealer',
  serverURL: 'http://localhost:3000',
};
const stagingEnv: AppEnv = {
  ...devEnv,
  stage: 'staging',
  production: true,
  serverURL: 'https://staging.example.test',
  email: { apiKey: 're_fake_key', from: 'noreply@example.test' },
};
const env = devEnv;

// A stand-in for a CRM collection. Real ones are added to the registry by their builders.
const widgets: CollectionConfig = {
  slug: 'widgets',
  access: { create: isStaff, read: isStaff, update: isStaff, delete: denyAll },
  lockDocuments: false,
  fields: [{ name: 'title', type: 'text' }],
};

const reviewedSlugs = (scoped: readonly string[] = []) => [
  'dealers',
  'users',
  ...PAYLOAD_BUILT_IN,
  ...scoped,
  ...notTenantScopedAllowlist,
];

describe('the real config', () => {
  it('passes the deny-by-default checks, on the raw list and on the final config', async () => {
    const config = await buildConfig(buildAppConfig({ env }));
    const raw = buildAppConfig({ env }).collections ?? [];
    expect(
      denyByDefaultProblems({
        collections: raw,
        pluginSlugs: tenantScopedCollections.map((c) => c.slug),
        coreSlugs: ['dealers', 'users'],
        allowlist: notTenantScopedAllowlist,
      }),
    ).toEqual([]);
    const slugs = config.collections.map((c) => c.slug);
    expect(sanitizedConfigProblems(slugs, reviewedSlugs())).toEqual([]);
    expect(slugs).toEqual(expect.arrayContaining(['dealers', 'users']));
  });

  it('uses a pinned origin for cors and csrf, and signed-in users only', async () => {
    const config = await buildConfig(buildAppConfig({ env }));
    expect(config.admin.user).toBe('users');
    // Payload adds the server URL itself, so the lists hold only that one origin.
    expect(new Set(config.csrf)).toEqual(new Set([env.serverURL]));
    expect(config.cors).not.toContain('*');
    expect(config.cors).toContain(env.serverURL);
    const users = config.collections.find((c) => c.slug === 'users');
    expect(users?.auth).toMatchObject({ maxLoginAttempts: 5, useSessions: true });
    expect(users?.auth.verify).toBeTruthy();
    expect(users?.fields.some((f) => 'name' in f && f.name === 'tenants')).toBe(true);
  });

  it('sets secure strict cookies and the Resend adapter outside dev, and neither in dev', async () => {
    const dev = await buildConfig(buildAppConfig({ env: devEnv }));
    const live = await buildConfig(buildAppConfig({ env: stagingEnv }));
    const cookies = (c: typeof dev) => c.collections.find((x) => x.slug === 'users')?.auth;
    expect(cookies(live)).toMatchObject({ cookies: { secure: true, sameSite: 'Strict' } });
    expect(cookies(dev)).toMatchObject({ cookies: { secure: false, sameSite: 'Strict' } });
    expect(buildAppConfig({ env: stagingEnv }).email).toBeDefined();
    expect(buildAppConfig({ env: devEnv }).email).toBeUndefined();
  });

  it('lets nobody see across dealers, not even an admin', () => {
    expect(neverAllDealers()).toBe(false);
  });

  it('keeps the migrations folder next to the app, whatever the working directory', () => {
    expect(existsSync(new URL('../../migrations/', import.meta.url))).toBe(true);
  });
});

describe('gate: no customer data before 2FA (#57) and row-level security (#58)', () => {
  // This test is the CI-enforced guard. While a gate is open, no collection beyond dealers and users may exist.
  it('holds for the real config', async () => {
    const config = await buildConfig(buildAppConfig({ env }));
    expect(tenantScopedCollections).toEqual([]);
    expect(
      gateProblems({ ...securityGates, collectionSlugs: config.collections.map((c) => c.slug) }),
    ).toEqual([]);
  });

  it('fails when a dealer-scoped collection is registered while a gate is open', async () => {
    const config = await buildConfig(buildAppConfig({ env, scoped: [{ ...widgets }] }));
    const slugs = config.collections.map((c) => c.slug);
    expect(
      gateProblems({ twoFactorRequired: false, rowLevelSecurity: false, collectionSlugs: slugs }),
    ).toEqual([
      'widgets: registered before 2FA (issue #57) is enforced',
      'widgets: registered before row-level security (issue #58) is in place',
    ]);
    expect(
      gateProblems({ twoFactorRequired: true, rowLevelSecurity: false, collectionSlugs: slugs }),
    ).toEqual(['widgets: registered before row-level security (issue #58) is in place']);
    expect(
      gateProblems({ twoFactorRequired: false, rowLevelSecurity: true, collectionSlugs: slugs }),
    ).toEqual(['widgets: registered before 2FA (issue #57) is enforced']);
    expect(
      gateProblems({ twoFactorRequired: true, rowLevelSecurity: true, collectionSlugs: slugs }),
    ).toEqual([]);
  });

  it('fails for a collection added any other way (not through the registry)', () => {
    expect(
      gateProblems({ ...securityGates, collectionSlugs: ['dealers', 'users', 'leads'] }),
    ).not.toEqual([]);
  });

  it('both gates are still open, so this PR must carry no customer collection', () => {
    expect(securityGates).toEqual({ twoFactorRequired: false, rowLevelSecurity: false });
  });
});

describe('a dealer-scoped collection', () => {
  it('gets a tenant field and plugin-wrapped access', async () => {
    const config = await buildConfig(buildAppConfig({ env, scoped: [{ ...widgets }] }));
    const sanitized = config.collections.find((c) => c.slug === 'widgets');
    expect(sanitized?.fields.some((f) => 'name' in f && f.name === 'tenant')).toBe(true);
    expect(
      sanitizedConfigProblems(
        config.collections.map((c) => c.slug),
        reviewedSlugs(['widgets']),
      ),
    ).toEqual([]);
  });
});

describe('break it on purpose: the checks must fail', () => {
  const base = {
    pluginSlugs: ['widgets'],
    coreSlugs: ['dealers', 'users'],
    allowlist: [],
  };

  it('a collection missing from the plugin', () => {
    const problems = denyByDefaultProblems({ ...base, pluginSlugs: [], collections: [widgets] });
    expect(problems).toEqual(['widgets: not in the multi-tenant plugin or the reviewed allowlist']);
  });

  it('a reviewed allowlist entry is accepted', () => {
    expect(
      denyByDefaultProblems({
        ...base,
        pluginSlugs: [],
        allowlist: ['widgets'],
        collections: [widgets],
      }),
    ).toEqual([]);
  });

  it('a collection without explicit access', () => {
    const noAccess: CollectionConfig = {
      slug: 'widgets',
      lockDocuments: false,
      fields: widgets.fields,
    };
    const problems = denyByDefaultProblems({ ...base, collections: [noAccess] });
    expect(problems).toHaveLength(4);
    const partial = { ...widgets, access: { read: isStaff } };
    expect(denyByDefaultProblems({ ...base, collections: [partial] })).toHaveLength(3);
  });

  it('a collection that leaves document locking on', () => {
    const locking: CollectionConfig = {
      slug: 'widgets',
      access: widgets.access,
      fields: widgets.fields,
    };
    expect(denyByDefaultProblems({ ...base, collections: [locking] })).toEqual([
      'widgets: lockDocuments must be false',
    ]);
  });

  it('a plugin slug that is not a collection', () => {
    expect(denyByDefaultProblems({ ...base, collections: [] })).toEqual([
      'widgets: given to the plugin but not a collection',
    ]);
  });

  it('Payload creates the open locked-documents collection when locking is left on', async () => {
    const locking: CollectionConfig = {
      slug: 'widgets',
      access: widgets.access,
      fields: widgets.fields,
    };
    const config = await buildConfig(buildAppConfig({ env, scoped: [locking] }));
    expect(
      sanitizedConfigProblems(
        config.collections.map((c) => c.slug),
        reviewedSlugs(['widgets']),
      ),
    ).toEqual(['payload-locked-documents exists']);
  });

  it('a collection in the final config that nobody reviewed', () => {
    expect(sanitizedConfigProblems(['dealers', 'users', 'sneaky'], reviewedSlugs())).toEqual([
      'sneaky: in the final config but not on the reviewed list',
    ]);
  });
});
