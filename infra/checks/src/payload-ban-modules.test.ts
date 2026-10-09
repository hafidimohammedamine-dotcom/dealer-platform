import { describe, expect, it } from 'vitest';
import {
  allowedPayloadValueImports,
  dbClientAllowedPaths,
  isDbClientModule,
} from '../../../eslint.payload-ban.mjs';
import { MODULES, errors, inside, outside } from './test-helpers/lint.js';

const desking = 'services/desking/src/db/credit.ts';

// Every client the reviews named, plus the families the pattern covers.
const dbClients = [
  'pg',
  'pg/lib/client',
  'pg-pool',
  'pg-native',
  'pg-boss',
  'postgres',
  'kysely',
  'kysely-postgres-js',
  'knex',
  'drizzle-orm',
  'drizzle-orm/node-postgres',
  'drizzle-kit',
  '@neondatabase/serverless',
  '@vercel/postgres',
  '@payloadcms/db-postgres',
  '@payloadcms/db-sqlite',
  '@payloadcms/db-mongodb',
  '@payloadcms/db-vercel-postgres',
  '@payloadcms/drizzle',
  '@prisma/client',
  'prisma',
  'typeorm',
  'sequelize',
  'mysql2',
  'better-sqlite3',
  'node:sqlite',
  'mongodb',
  'mongoose',
  '@libsql/client',
  '@supabase/supabase-js',
];

describe('database clients', () => {
  it.each(dbClients)('recognizes %s', (name) => {
    expect(isDbClientModule(name)).toBe(true);
  });

  it('does not match lookalike names', () => {
    for (const name of [
      'pgp',
      'postgres-interval',
      'knexx',
      'bullmq',
      'node:fs',
      'payload/shared',
    ]) {
      expect(isDbClientModule(name), name).toBe(false);
    }
  });

  it.each(dbClients)('bans every way to load %s outside packages/data', async (name) => {
    const forms = [
      `import x from '${name}';\nvoid x;\n`,
      `import type { T } from '${name}';\n`,
      `import '${name}';\n`,
      `export * from '${name}';\n`,
      `export { y } from '${name}';\n`,
      `import z = require('${name}');\nvoid z;\n`,
      `await import('${name}');\n`,
      `require('${name}');\n`,
      `require(\`${name}\`);\n`,
    ];
    for (const code of forms) expect(await errors(code, outside), code).toEqual([MODULES]);
  });

  it('allows them in packages/data and the reviewed desking path only', async () => {
    expect(dbClientAllowedPaths).toEqual(['services/desking/src/db/**']);
    const code = "import x from 'pg';\nvoid x;\nawait import('kysely');\n";
    expect(await errors(code, inside)).toEqual([]);
    expect(await errors(code, desking)).toEqual([]);
    expect(await errors(code, 'services/desking/src/deals.ts')).toEqual([MODULES, MODULES]);
  });
});

describe('the payload module', () => {
  it('starts with no value imports allowed', () => {
    expect(allowedPayloadValueImports).toEqual([]);
  });

  it('allows type-only imports outside packages/data', async () => {
    const code = [
      "import type { CollectionConfig } from 'payload';",
      "import { type Field } from 'payload';",
      "export type { Where } from 'payload';",
      "type C = typeof import('payload');",
      '',
    ].join('\n');
    expect(await errors(code, outside)).toEqual([]);
  });

  it('bans every value import outside packages/data, desking included', async () => {
    const forms = [
      "import { buildConfig } from 'payload';\nvoid buildConfig;\n",
      "import P from 'payload';\nvoid P;\n",
      "import * as P from 'payload';\nvoid P;\n",
      "import 'payload';\n",
      "import { APIError } from 'payload/shared';\nvoid APIError;\n",
      "export * from 'payload';\n",
      "export { buildConfig } from 'payload';\n",
      "import p = require('payload');\nvoid p;\n",
      "await import('payload');\n",
      "require('payload');\n",
    ];
    for (const file of [outside, desking]) {
      for (const code of forms) expect(await errors(code, file), code).toContain(MODULES);
    }
  });

  it('reports each value specifier', async () => {
    const code = "import { type Field, buildConfig, APIError } from 'payload';\n";
    expect(await errors(code, outside)).toEqual([MODULES, MODULES]);
  });

  it('allows value imports inside packages/data', async () => {
    const code = "import * as P from 'payload';\nvoid P;\nawait import('payload');\n";
    expect(await errors(code, inside)).toEqual([]);
  });
});

describe('dynamic module loading', () => {
  it('bans computed names and require/createRequire as values outside packages/data', async () => {
    for (const code of [
      'await import(name);\n',
      "await import('pa' + 'yload');\n",
      'require(name);\n',
      'require();\n',
      'const r = require;\nvoid r;\n',
      "import { createRequire } from 'node:module';\nvoid createRequire;\n",
      'module.createRequire(url);\n',
    ]) {
      expect(await errors(code, outside), code).toContain(MODULES);
    }
  });

  it('bans eval, the Function constructor and with', async () => {
    expect(await errors('with (req) { find({}); }\n', outside)).toEqual(['no-with']);
    expect(await errors("eval('x');\n", outside)).toEqual(['no-eval']);
    expect(await errors("new Function('return 1');\n", outside)).toEqual(['no-new-func']);
    expect(await errors("setTimeout('x()', 1);\n", outside)).toEqual(['no-implied-eval']);
  });

  it('allows fixed names of other modules', async () => {
    const code =
      "await import('node:fs');\nrequire('node:path');\nimport x from 'bullmq';\nvoid x;\n";
    expect(await errors(code, outside)).toEqual([]);
  });

  it('allows dynamic loading inside packages/data', async () => {
    expect(await errors('await import(name);\nrequire(name);\n', inside)).toEqual([]);
  });
});
