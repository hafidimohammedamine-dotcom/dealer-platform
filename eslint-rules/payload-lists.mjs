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

/** Files (globs) besides packages/data that may import a database client: the desking credit schema. */
export const dbClientAllowedPaths = ['services/desking/src/db/**'];

/**
 * Files (globs) where `overrideAccess` may be something other than literal false (system jobs).
 * Empty on purpose.
 * @type {string[]}
 */
export const overrideAccessAllowedPaths = [];

/**
 * The one reviewed file in packages/data that may use the raw database adapter (`payload.db`): it sets the dealer for
 * each transaction (CLAUDE.md, Payload rule 2). Everywhere else in packages/data, `.db` is banned.
 */
export const payloadDbAllowedPaths = ['packages/data/src/tenant-transaction.ts'];

/** Options every Local API call in packages/data must spell out (CLAUDE.md, Payload rules 1 and 4). */
export const requiredLocalApiOptions = ['overrideAccess', 'depth', 'versions'];

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
/** The raw database adapter member of the Payload instance (`payload.db`). */
export const rawDbMember = 'db';
/** Reflection reaches any property by a computed name. */
export const reflectionName = /^Reflect$/;
/** The `payload` package and its subpaths. */
export const payloadModule = /^payload(?:\/.*)?$/;
/** Database clients, query builders, ORMs and Payload database adapters. */
const dbClientModule = new RegExp(
  `^(?:${[
    'node:sqlite',
    'pg',
    'pg-[^/]+',
    'postgres',
    'postgresql',
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
