import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildConfig } from 'payload';
import { describe, expect, it } from 'vitest';
import { buildAppConfig } from './config.js';
import { adminDir, adminFiles, devEnv } from '../test-helpers/fixtures.js';
import {
  exposureProblems,
  gateProblems,
  GATE_FREE_COLLECTIONS,
  securityGates,
  tablesWithoutRls,
} from './readiness.js';
import { tenantScopedCollections } from './registry.js';

const env = devEnv;
const open = { twoFactorRequired: false, rowLevelSecurity: false, auditStore: false };
const closed = { twoFactorRequired: true, rowLevelSecurity: true, auditStore: true };

describe('gate: no customer data before 2FA (#57), row-level security (#58) and the audit table', () => {
  it('holds for the real config: only the dealers, the users and Payload bookkeeping exist', async () => {
    const config = await buildConfig(buildAppConfig({ env }));
    expect(tenantScopedCollections).toEqual([]);
    expect(
      gateProblems({ ...securityGates, collectionSlugs: config.collections.map((c) => c.slug) }),
    ).toEqual([]);
    expect(GATE_FREE_COLLECTIONS).toEqual(expect.arrayContaining(['dealers', 'users']));
  });

  it('fails for a customer collection while any gate is open, and passes when all are closed', () => {
    const slugs = ['dealers', 'users', 'widgets'];
    expect(gateProblems({ ...open, collectionSlugs: slugs })).toEqual([
      'widgets: registered before 2FA (issue #57) is enforced',
      'widgets: registered before row-level security (issue #58) is in place',
      'widgets: registered before the durable audit table (issue #71) is in place',
    ]);
    for (const gate of ['twoFactorRequired', 'rowLevelSecurity', 'auditStore'] as const) {
      expect(gateProblems({ ...open, [gate]: true, collectionSlugs: slugs })).toHaveLength(2);
    }
    expect(gateProblems({ ...closed, collectionSlugs: slugs })).toEqual([]);
  });

  it('fails for a collection added any way other than the registry', () => {
    expect(
      gateProblems({ ...securityGates, collectionSlugs: ['dealers', 'users', 'leads'] }),
    ).not.toEqual([]);
  });

  it('all four gates are open today, so this PR carries no customer collection and no HTTP route', () => {
    expect(securityGates).toEqual({
      twoFactorRequired: false,
      rowLevelSecurity: false,
      auditStore: false,
      loginSurface: false,
    });
  });
});

describe('gate: the app is not reachable before 2FA (#57) and the login surface (#73)', () => {
  const why = 'an HTTP entry point exists before 2FA (issue #57) and the login surface (issue #73)';
  const file = (path: string, text = '') => ({ path, text });

  it('holds for the real admin app: the whole folder is scanned, and nothing answers over HTTP', () => {
    const files = adminFiles();
    expect(files.length).toBeGreaterThan(20);
    expect(files.map((f) => f.path)).toEqual(
      expect.arrayContaining(['payload.config.ts', 'src/tenants/users.ts']),
    );
    expect(files.some((f) => f.path.startsWith('migrations/'))).toBe(true);
    expect(exposureProblems(securityGates, files)).toEqual([]);
  });

  it('fails (break it on purpose) for routes, pages, server files and Next imports anywhere', () => {
    const exposed = [
      file('src/app/(payload)/admin/[[...segments]]/page.tsx'),
      file('src/app/(payload)/api/[...slug]/route.ts'),
      file('app/layout.tsx'),
      file('app/helper.ts'),
      file('pages/api/users.ts'),
      file('src/pages/index.jsx'),
      file('middleware.ts'),
      file('src/proxy.mjs'),
      file('server.cjs'),
      file('instrumentation.ts'),
      file('next.config.mjs'),
      file('src/tenants/x.ts', "import { RootPage } from '@payloadcms/next/views';"),
      file('src/tenants/y.ts', 'export const r = await import("@payloadcms/next/routes");'),
      file('src/tenants/z.js', "const n = require('next/server');"),
      file('lib/w.ts', "import '@payloadcms/next/css';"),
    ];
    const problems = exposureProblems({ twoFactorRequired: false, loginSurface: false }, exposed);
    expect(problems).toEqual(exposed.map((f) => `${f.path}: ${why}`));
    // Either gate still open is enough to fail; both closed lets the routes in.
    expect(exposureProblems({ twoFactorRequired: true, loginSurface: false }, exposed)).toEqual(
      problems,
    );
    expect(exposureProblems({ twoFactorRequired: false, loginSurface: true }, exposed)).toEqual(
      problems,
    );
    expect(exposureProblems({ twoFactorRequired: true, loginSurface: true }, exposed)).toEqual([]);
  });

  it('ignores what does not answer over HTTP', () => {
    const gates = { twoFactorRequired: false, loginSurface: false };
    expect(
      exposureProblems(gates, [
        file('src/tenants/page.ts'),
        file('src/lib/route.ts'),
        file('docs/app/x.md'),
        file('src/tenants/server-time.ts'),
        file('src/tenants/a.test.ts', "import { x } from '@payloadcms/next/views';"),
        file('src/tenants/b.ts', "import { buildConfig } from 'payload'; // next steps"),
        file('src/tenants/c.ts', "import { x } from 'next-intl';"),
      ]),
    ).toEqual([]);
  });
});

describe('gate: row-level security on every table (Payload rule 2)', () => {
  const migrationsDir = join(adminDir, 'migrations');
  const sql = readdirSync(migrationsDir)
    .filter((name) => /^\d+_\d+_.*\.ts$/.test(name))
    .map((name) => readFileSync(join(migrationsDir, name), 'utf8'))
    .join('\n');

  it('lists the tables that are still open while the gate is open, and none once it is closed', () => {
    const open_ = tablesWithoutRls(sql);
    expect(open_).toEqual(expect.arrayContaining(['dealers', 'users', 'users_tenants']));
    expect(open_).not.toContain('payload_migrations');
    // The check that turns red the moment someone flips the flag without writing the policies.
    if (securityGates.rowLevelSecurity) expect(open_).toEqual([]);
  });

  it('is satisfied only by ENABLE and FORCE together', () => {
    const create = 'CREATE TABLE "leads" ("id" uuid);';
    expect(tablesWithoutRls(create)).toEqual(['leads']);
    expect(tablesWithoutRls(`${create} ALTER TABLE "leads" ENABLE ROW LEVEL SECURITY;`)).toEqual([
      'leads',
    ]);
    expect(tablesWithoutRls(`${create} ALTER TABLE "leads" FORCE ROW LEVEL SECURITY;`)).toEqual([
      'leads',
    ]);
    expect(
      tablesWithoutRls(
        `${create} ALTER TABLE "leads" ENABLE ROW LEVEL SECURITY; ALTER TABLE "leads" FORCE ROW LEVEL SECURITY;`,
      ),
    ).toEqual([]);
  });

  it('reads every way a table can be named or created, the way Postgres compares names', () => {
    const both = (name: string) =>
      `ALTER TABLE ${name} ENABLE ROW LEVEL SECURITY; ALTER TABLE ONLY ${name} FORCE ROW LEVEL SECURITY;`;
    for (const create of [
      'CREATE TABLE IF NOT EXISTS "leads" (id int);',
      'create table leads (id int);',
      'CREATE TABLE "public"."leads" (id int);',
      'CREATE TABLE public.Leads (id int);',
      'CREATE UNLOGGED TABLE\n  "leads" (id int);',
    ]) {
      expect(tablesWithoutRls(create), create).toEqual(['leads']);
      for (const name of ['"leads"', 'LEADS', 'public."leads"', '"public" . "leads"']) {
        expect(tablesWithoutRls(`${create} ${both(name)}`), `${create} / ${name}`).toEqual([]);
      }
    }
    // Different tables: a quoted mixed-case name, another schema, and a lookalike.
    expect(tablesWithoutRls(`CREATE TABLE "Leads" (id int); ${both('leads')}`)).toEqual(['Leads']);
    expect(tablesWithoutRls(`CREATE TABLE crm.leads (id int); ${both('leads')}`)).toEqual([
      'crm.leads',
    ]);
    expect(tablesWithoutRls(`CREATE TABLE crm.leads (id int); ${both('crm.leads')}`)).toEqual([]);
    expect(tablesWithoutRls(`CREATE TABLE "a.b" (id int); ${both('"a.b"')}`)).toEqual([]);
    expect(tablesWithoutRls(`CREATE TABLE leads2 (id int); ${both('leads')}`)).toEqual(['leads2']);
  });

  it('reads statements in order: a later DISABLE or NO FORCE opens the table again', () => {
    const create = 'CREATE TABLE leads (id int);';
    const on =
      'ALTER TABLE leads ENABLE ROW LEVEL SECURITY; ALTER TABLE leads FORCE ROW LEVEL SECURITY;';
    expect(
      tablesWithoutRls(`${create} ${on} ALTER TABLE leads DISABLE ROW LEVEL SECURITY;`),
    ).toEqual(['leads']);
    expect(
      tablesWithoutRls(`${create} ${on} ALTER TABLE leads NO  FORCE ROW LEVEL SECURITY;`),
    ).toEqual(['leads']);
    expect(tablesWithoutRls(`CREATE TABLE payload_migrations (id int);`)).toEqual([]);
  });
});
