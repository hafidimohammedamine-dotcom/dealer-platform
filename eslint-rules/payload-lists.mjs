// @ts-check
// The reviewed policy behind the Payload bans: allow-lists and the names and modules that are banned.
// Security must approve every change to this file. The rules live next to it; eslint.payload-ban.mjs wires them up.

// ---------------------------------------------------------------------------------------------
// Reviewed allow-lists. Security must approve every addition.
// ---------------------------------------------------------------------------------------------

/** Members of the Payload instance that may be used outside packages/data. */
export const allowedPayloadMembers = ['logger'];

/** Named value imports from the `payload` module allowed outside packages/data. Empty on purpose. */
/** @type {string[]} */
export const allowedPayloadValueImports = [];

/**
 * Files (globs) outside packages/data where the instance names may appear, for example a webhook
 * body that has a field with that name. Only the name check is off there. Empty on purpose.
 * @type {string[]}
 */
export const payloadNameAllowedPaths = [];

/**
 * Files (globs) besides packages/data that may import a database client. Empty on purpose: add the exact file
 * in the PR that adds the reviewed file (the desking credit schema, `services/desking/src/db/`, is the first).
 * @type {string[]}
 */
export const dbClientAllowedPaths = [];

/**
 * The one reviewed file in packages/data that may use the raw database adapter (`payload.db`): it will set the dealer
 * for each transaction (CLAUDE.md, Payload rule 2). Empty on purpose: the PR that adds that file adds its path here.
 * Everywhere else in packages/data, `.db` is banned.
 * @type {string[]}
 */
export const payloadDbAllowedPaths = [];

/**
 * Exact files that may load process, thread and VM modules (`child_process` and friends). Only the tests that start
 * a real vitest or eslint process. Nothing else may.
 * @type {string[]}
 */
export const spawnAllowedPaths = [
  'infra/checks/src/config.test.ts',
  'infra/checks/src/payload-ban-config.test.ts',
];

/** Options every Local API call in packages/data must spell out (CLAUDE.md, Payload rules 1 and 4). */
export const requiredLocalApiOptions = ['overrideAccess', 'depth', 'versions'];

/** Every Local API call in packages/data must also pass at least one of these (the logged-in user, directly or in `req`). */
export const requiredOneOfLocalApiOptions = ['user', 'req'];

/** Payload Local API methods. In packages/data each call must pass the required options. */
export const localApiMethods = [
  'find',
  'findByID',
  'findDistinct',
  'findGlobal',
  'findVersions',
  'findVersionByID',
  'findGlobalVersions',
  'findGlobalVersionByID',
  'count',
  'countVersions',
  'countGlobalVersions',
  'create',
  'update',
  'updateGlobal',
  'delete',
  'duplicate',
  'restoreVersion',
  'restoreGlobalVersion',
  'login',
  'forgotPassword',
  'resetPassword',
  'unlock',
  'verifyEmail',
  'auth',
];

// ---------------------------------------------------------------------------------------------
// What is banned. Patterns, not string lists, so this file does not trip its own name rule.
// ---------------------------------------------------------------------------------------------

/** Every name the Payload instance, its factory or its type goes by. */
export const instanceName = /^(?:payload|getPayload\w*|Payload|BasePayload)$/;
/** The one name that may be read for an allowed member (`payload.logger`). */
export const memberOwnerName = /^payload$/;
/** Members that hand out an object's values without naming them. Banned in packages/data. */
export const reflectiveMembers = [
  'values',
  'entries',
  'getOwnPropertyDescriptor',
  'getOwnPropertyDescriptors',
];
/** Members of `Object` that hand out or copy an object's properties without naming them. Banned outside packages/data. */
export const objectBannedMembers = [...reflectiveMembers, 'getOwnPropertyNames', 'assign'];
/** The global `Object`. Only `Object.<fixed safe member>` may be written outside packages/data. */
export const objectName = /^Object$/;
/** The raw database adapter member of the Payload instance (`payload.db`). */
export const rawDbMember = 'db';
/** Reflection reaches any property by a computed name. */
export const reflectionName = /^Reflect$/;
/** The `payload` package and its subpaths. */
export const payloadModule = /^payload(?:\/.*)?$/;
/** Modules that start processes, threads or VMs, or load other modules by hand. Banned except in spawnAllowedPaths. */
const processModule =
  /^(?:node:)?(?:vm|worker_threads|child_process|module|cluster|repl)(?:\/.*)?$/;
/** @param {string} source */
export const isProcessModule = (source) => processModule.test(source);
/** Members that load a module or native code by hand (`Module._load`, `process.getBuiltinModule`, `module.require`). */
export const loaderMembers = ['getBuiltinModule', '_load', '_linkedBinding', 'dlopen', 'require'];
/** `process.binding` loads internal modules. Only banned on `process`. */
export const processBindingMember = 'binding';
/** The desking credit schema: nothing outside services/desking/ may import from it. */
export const deskingDbDir = 'services/desking/src/db';
/** The desking package, imported by name: its `src`/`dist` `db` folder. */
export const deskingDbPackage = /^@dealer\/desking\/(?:(?:src|dist)\/)?db(?:\/|$)/;
/** Database clients, query builders, ORMs and Payload database adapters. */
const dbClientModule = new RegExp(
  `^(?:${[
    'node:sqlite',
    'pg',
    'pg-[^/]+',
    'postgres',
    'postgresql',
    'massive',
    '@sequelize/[^/]+',
    '@effect/sql(?:-[^/]+)?',
    'knex',
    'kysely',
    'kysely-[^/]+',
    'drizzle-orm',
    'drizzle-kit',
    'prisma',
    'typeorm',
    'sequelize',
    'mysql2?',
    'sqlite3?',
    'better-sqlite3',
    'mongodb',
    'mongoose',
    'slonik',
    'objection',
    '@neondatabase/[^/]+',
    '@vercel/postgres',
    '@prisma/[^/]+',
    '@libsql/[^/]+',
    '@supabase/[^/]+',
    '@planetscale/[^/]+',
    '@mikro-orm/[^/]+',
    '@electric-sql/[^/]+',
    '@databases/[^/]+',
    '@payloadcms/db-[^/]+',
    '@payloadcms/drizzle',
  ].join('|')})(?:/.*)?$`,
);

/** @param {string} source */
export const isDbClientModule = (source) => dbClientModule.test(source);
