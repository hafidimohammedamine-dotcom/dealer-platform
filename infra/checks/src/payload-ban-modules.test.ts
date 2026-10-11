import { describe, expect, it } from 'vitest';
import {
  allowedPayloadValueImports,
  dbClientAllowedPaths,
  isDbClientModule,
  isProcessModule,
  loaderMembers,
  payloadBanConfigs,
} from '../../../eslint.payload-ban.mjs';
import { MODULES, errors, errorsWith, eslintWith, inside, outside } from './test-helpers/lint.js';

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
  'massive',
  '@sequelize/core',
  '@sequelize/postgres',
  '@effect/sql',
  '@effect/sql-pg',
  '@effect/sql-drizzle',
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
      'massively',
      '@effect/platform',
      '@sequelizer/core',
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

  it('allows them in packages/data only, until a reviewed file is listed', async () => {
    expect(dbClientAllowedPaths).toEqual([]);
    const code = "import x from 'pg';\nvoid x;\nawait import('kysely');\n";
    expect(await errors(code, inside)).toEqual([]);
    expect(await errors(code, desking)).toEqual([MODULES, MODULES]);
    expect(await errors(code, 'services/desking/src/deals.ts')).toEqual([MODULES, MODULES]);
  });

  it('allows them in a listed file only', async () => {
    const listed = eslintWith(
      payloadBanConfigs({ overrideAccessAllowed: [], dbClientAllowed: [desking] }),
    );
    const code = "import x from 'pg';\nvoid x;\n";
    expect(await errorsWith(listed, code, desking)).toEqual([]);
    expect(await errorsWith(listed, code, 'services/desking/src/db/other.ts')).toEqual([MODULES]);
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

describe('process, thread and VM modules and hand-made module loaders', () => {
  const modules = [
    'vm',
    'node:vm',
    'worker_threads',
    'node:worker_threads',
    'child_process',
    'node:child_process',
    'module',
    'node:module',
    'cluster',
    'node:cluster',
    'repl',
    'node:repl',
  ];

  it.each(modules)('recognizes %s', (name) => {
    expect(isProcessModule(name)).toBe(true);
  });

  it('does not match lookalike names', () => {
    for (const name of ['node:fs', 'vmware', 'modules', 'node:modules', 'my-child_process']) {
      expect(isProcessModule(name), name).toBe(false);
    }
  });

  it.each(modules)('bans every way to load %s, in packages/data too', async (name) => {
    const forms = [
      `import x from '${name}';\nvoid x;\n`,
      `import { y } from '${name}';\nvoid y;\n`,
      `import type { T } from '${name}';\n`,
      `import '${name}';\n`,
      `export * from '${name}';\n`,
      `import z = require('${name}');\nvoid z;\n`,
      `await import('${name}');\n`,
      `require('${name}');\n`,
    ];
    for (const file of [outside, inside, 'apps/admin/src/x.ts']) {
      for (const code of forms)
        expect(await errors(code, file), `${file} ${code}`).toEqual([MODULES]);
    }
  });

  it('bans the members that load modules by hand, in packages/data too', async () => {
    const forms = [
      "process.getBuiltinModule('node:vm');\n",
      "process['getBuiltinModule']('node:vm');\n",
      "globalThis.process.getBuiltinModule('node:vm');\n",
      "const { getBuiltinModule } = process;\nvoid getBuiltinModule('node:vm');\n",
      'const { getBuiltinModule: g } = process;\nvoid g;\n',
      "Module._load('pg');\n",
      "Module['_load']('pg');\n",
      'const { _load } = Module;\nvoid _load;\n',
      "process.binding('natives');\n",
      'const { binding } = process;\nvoid binding;\n',
      'process[name]();\n',
      'const { [name]: f } = process;\nvoid f;\n',
      "process.dlopen(m, 'x');\n",
      "process._linkedBinding('x');\n",
      "module.require('pg');\n",
      "process.mainModule.require('pg');\n",
    ];
    for (const file of [outside, inside]) {
      for (const code of forms)
        expect(await errors(code, file), `${file} ${code}`).toContain(MODULES);
    }
    expect(loaderMembers).toEqual([
      'getBuiltinModule',
      '_load',
      '_linkedBinding',
      'dlopen',
      'require',
    ]);
  });

  it('leaves ordinary members and destructuring alone', async () => {
    const code = [
      'void process.env;',
      'void process.cwd();',
      "void process['argv'];",
      'void other.binding;',
      'const { env, cwd } = process;',
      'const { binding } = other;',
      'void env; void cwd; void binding;',
      '',
    ].join('\n');
    expect(await errors(code, outside)).toEqual([]);
  });

  it('allows them in the two listed test files only', async () => {
    const code = "import { spawnSync } from 'node:child_process';\nvoid spawnSync;\n";
    const listed = 'infra/checks/src/config.test.ts';
    expect(await errors(code, listed)).toEqual([]);
    expect(await errors(code, 'infra/checks/src/other.test.ts')).toEqual([MODULES]);
    expect(await errors("process.getBuiltinModule('node:vm');\n", listed)).toEqual([]);
  });
});
