import { buildConfig, type CollectionConfig } from 'payload';
import { describe, expect, it } from 'vitest';
import { denyAll, isStaff } from '../access/roles.js';
import { buildAppConfig } from './config.js';
import { denyByDefaultProblems, sanitizedConfigProblems } from './deny-by-default.js';
import { readAppEnv } from './env.js';
import { notTenantScopedAllowlist, tenantScopedCollections } from './registry.js';

const env = {
  secret: 'x'.repeat(40),
  databaseUrl: 'postgres://app_user:fake@localhost:5432/dealer',
  serverURL: 'http://localhost:3000',
  production: false,
};

// A stand-in for a CRM collection. Real ones are added to the registry by their builders.
const widgets: CollectionConfig = {
  slug: 'widgets',
  access: { create: isStaff, read: isStaff, update: isStaff, delete: denyAll },
  lockDocuments: false,
  fields: [{ name: 'title', type: 'text' }],
};

// Calls an access function or hook with a minimal fake request. Method syntax makes the parameter bivariant, so no cast.
interface Loose {
  run(args: unknown): unknown;
}
const loose = (fn: Loose['run']): Loose => ({ run: fn });

describe('the real config', () => {
  it('passes the deny-by-default checks', async () => {
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
    expect(sanitizedConfigProblems(config.collections.map((c) => c.slug))).toEqual([]);
    expect(config.collections.map((c) => c.slug)).toEqual(
      expect.arrayContaining(['dealers', 'users']),
    );
  });

  it('uses migrations only, signed-in users only, and the dealers as tenants', async () => {
    const config = await buildConfig(buildAppConfig({ env }));
    expect(config.admin.user).toBe('users');
    // Payload adds the server URL itself, so the lists hold only that one origin.
    expect(new Set(config.csrf)).toEqual(new Set([env.serverURL]));
    expect(config.cors).not.toContain('*');
    expect(config.cors).toContain(env.serverURL);
    const users = config.collections.find((c) => c.slug === 'users');
    expect(users?.auth).toMatchObject({ maxLoginAttempts: 5, useSessions: true });
    expect(users?.fields.some((f) => 'name' in f && f.name === 'tenants')).toBe(true);
  });
});

describe('a dealer-scoped collection', () => {
  it('gets a tenant field and plugin-wrapped access', async () => {
    const config = await buildConfig(buildAppConfig({ env, scoped: [{ ...widgets }] }));
    const sanitized = config.collections.find((c) => c.slug === 'widgets');
    expect(sanitized?.fields.some((f) => 'name' in f && f.name === 'tenant')).toBe(true);
    expect(sanitizedConfigProblems(config.collections.map((c) => c.slug))).toEqual([]);
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
    expect(sanitizedConfigProblems(config.collections.map((c) => c.slug))).toEqual([
      'payload-locked-documents exists',
    ]);
  });
});

describe('users and dealers access, after the plugin', () => {
  async function sanitized() {
    const config = await buildConfig(buildAppConfig({ env }));
    const users = config.collections.find((c) => c.slug === 'users');
    const dealers = config.collections.find((c) => c.slug === 'dealers');
    if (!users || !dealers) throw new Error('missing');
    return { users, dealers };
  }
  const rep = { id: 'rep1', collection: 'users', role: 'sales_rep', tenants: [{ tenant: 'A' }] };
  const admin = { id: 'adm1', collection: 'users', role: 'admin', tenants: [{ tenant: 'A' }] };
  const asUser = (user: unknown) => ({ req: { user } });

  it('a rep may update only themself, and not read other dealers', async () => {
    const { users } = await sanitized();
    const update = loose(users.access?.update ?? denyAll);
    const result = await update.run(asUser(rep));
    expect(JSON.stringify(result)).toContain('rep1');
    expect(JSON.stringify(result)).not.toBe('true');
    const read = loose(users.access?.read ?? denyAll);
    expect(JSON.stringify(await read.run(asUser(rep)))).toContain('"A"');
  });

  it('nobody can create or delete users or dealers without being an admin', async () => {
    const { users, dealers } = await sanitized();
    expect(await loose(users.access?.create ?? denyAll).run(asUser(rep))).toBe(false);
    expect(await loose(users.access?.delete ?? denyAll).run(asUser(rep))).toBe(false);
    expect(await loose(users.access?.create ?? denyAll).run(asUser(undefined))).toBe(false);
    expect(await loose(dealers.access?.create ?? denyAll).run(asUser(admin))).toBe(false);
    expect(await loose(dealers.access?.delete ?? denyAll).run(asUser(admin))).toBe(false);
    expect(await loose(dealers.access?.update ?? denyAll).run(asUser(rep))).toBe(false);
  });

  it('an admin keeps a dealer filter, and a user with no dealer sees only themself', async () => {
    const { users } = await sanitized();
    const read = loose(users.access?.read ?? denyAll);
    expect(JSON.stringify(await read.run(asUser(admin)))).toContain('"A"');
    const lost = { id: 'x', collection: 'users', role: 'bdc', tenants: [] };
    expect(await read.run(asUser(lost))).toEqual({ id: { equals: 'x' } });
  });
});

describe('enforceOwnDealers (a user can only be placed in your own dealers)', () => {
  async function hook() {
    const config = await buildConfig(buildAppConfig({ env }));
    const users = config.collections.find((c) => c.slug === 'users');
    const fn = users?.hooks?.beforeValidate?.[0];
    if (!fn) throw new Error('missing hook');
    return loose(fn);
  }
  const actor = { id: 'a', role: 'admin', tenants: [{ tenant: 'A' }] };

  it('lets own dealers through and untouched data through', async () => {
    const run = (await hook()).run;
    const own = { tenants: [{ tenant: 'A' }] };
    expect(await run({ data: own, req: { user: actor } })).toBe(own);
    const other = { email: 'e' };
    expect(await run({ data: other, req: { user: actor } })).toBe(other);
    expect(await run({ data: undefined, req: { user: actor } })).toBeUndefined();
  });

  it('skips system jobs that have no actor', async () => {
    const run = (await hook()).run;
    const data = { tenants: [{ tenant: 'B' }] };
    expect(await run({ data, req: {} })).toBe(data);
  });

  it('refuses another dealer, junk rows and a non-array', async () => {
    const run = (await hook()).run;
    const attempt = async (tenants: unknown) => run({ data: { tenants }, req: { user: actor } });
    await expect(attempt([{ tenant: 'B' }])).rejects.toThrow('only be placed');
    await expect(attempt([{ tenant: 'A' }, { tenant: 'B' }])).rejects.toThrow('only be placed');
    await expect(attempt([{ tenant: 'A' }, 'junk'])).rejects.toThrow('only be placed');
    await expect(attempt('A')).rejects.toThrow('only be placed');
  });
});

describe('readAppEnv', () => {
  const good = {
    PAYLOAD_SECRET: 'y'.repeat(32),
    DATABASE_URL: 'postgres://u:p@h/db',
    PAYLOAD_PUBLIC_SERVER_URL: 'https://x.example',
  };

  it('reads good settings, and dev is the default', () => {
    expect(readAppEnv(good)).toEqual({
      secret: good.PAYLOAD_SECRET,
      databaseUrl: good.DATABASE_URL,
      serverURL: good.PAYLOAD_PUBLIC_SERVER_URL,
      production: false,
    });
    expect(readAppEnv({ ...good, APP_ENV: 'production' }).production).toBe(true);
    expect(readAppEnv({ ...good, APP_ENV: 'staging' }).production).toBe(true);
  });

  it('fails loudly on a missing, empty or weak setting', () => {
    expect(() => readAppEnv({ ...good, DATABASE_URL: undefined })).toThrow('DATABASE_URL');
    expect(() => readAppEnv({ ...good, PAYLOAD_SECRET: '' })).toThrow('PAYLOAD_SECRET');
    expect(() => readAppEnv({ ...good, PAYLOAD_SECRET: 'short' })).toThrow('32');
    expect(() => readAppEnv({ ...good, APP_ENV: 'prod' })).toThrow('APP_ENV');
  });
});
