// @ts-check
// Payload rule 1: the Local API skips access checks by default, so every data call goes through
// packages/data. A list of "bad uses" of the Payload instance can never be complete, so these rules
// ban where the instance comes from and every name it goes by. False positives are fine here.
// Bypasses are not.
//
//   local/no-payload-instance-access  outside packages/data: no identifier, key, string or type named
//                                     payload / getPayload* / Payload / BasePayload (only `payload.logger`),
//                                     no `Reflect`, no `Object.values/entries/assign/getOwnProperty*` (and no
//                                     other use of `Object` than `Object.<fixed name>`), and no computed read
//                                     whose key is not a fixed string (`obj[k]`), unless it is only assigned to.
//   local/no-restricted-modules       everywhere but packages/data: no value import of `payload` (type-only
//                                     imports are fine), no database client at all, no import()/require() with
//                                     a computed name, no `require` or `createRequire` used as a value.
//                                     Everywhere (packages/data too, except spawnAllowedPaths): no `vm`,
//                                     `worker_threads`, `child_process`, `module`, `cluster`, `repl`, and no
//                                     `Module._load`, `process.getBuiltinModule`, `process.binding`, `dlopen`.
//                                     Nothing outside services/desking/ imports from services/desking/src/db/.
//   local/no-override-access          everywhere: `overrideAccess` is only ever the literal `false`. In
//                                     packages/data every Local API call passes one object literal with
//                                     `overrideAccess: false`, `depth`, `versions` and `user` or `req`, no
//                                     spreads, no computed keys, `showHiddenFields` only as `false`, and a
//                                     Local API method is only read to call it directly:
//                                     no dynamic or numeric keys, no `Reflect`, no `.values()`/`.entries()`/
//                                     property descriptors, and no `.db` outside payloadDbAllowedPaths.
//
// The `overrideAccess: true` system-job allow-list is NOT in code. It is the founder-only file
// packages/data/override-allowlist.txt, read by eslint-rules/override-allowlist.mjs when the config loads.
//
// Inline eslint comments are off (see eslint.config.mjs), so none of these can be disabled in a file.
// The last locks are Postgres row-level security and the cross-dealer leak tests.
//
// Files: eslint-rules/payload-lists.mjs (reviewed allow-lists and banned names), one file per rule
// in eslint-rules/, and eslint-rules/ast.mjs (shared helpers).

import { noOverrideAccess } from './eslint-rules/no-override-access.mjs';
import { noPayloadInstanceAccess } from './eslint-rules/no-payload-instance-access.mjs';
import { noRestrictedModules } from './eslint-rules/no-restricted-modules.mjs';
import { readOverrideAllowlist } from './eslint-rules/override-allowlist.mjs';
import {
  dbClientAllowedPaths,
  payloadDbAllowedPaths,
  payloadNameAllowedPaths,
  spawnAllowedPaths,
} from './eslint-rules/payload-lists.mjs';

export {
  overrideAllowlistFile,
  parseOverrideAllowlist,
  readOverrideAllowlist,
} from './eslint-rules/override-allowlist.mjs';

export {
  allowedPayloadMembers,
  allowedPayloadValueImports,
  dbClientAllowedPaths,
  isDbClientModule,
  isProcessModule,
  loaderMembers,
  localApiMethods,
  objectBannedMembers,
  payloadDbAllowedPaths,
  payloadNameAllowedPaths,
  rawDbMember,
  reflectiveMembers,
  requiredLocalApiOptions,
  requiredOneOfLocalApiOptions,
  spawnAllowedPaths,
} from './eslint-rules/payload-lists.mjs';

// ---------------------------------------------------------------------------------------------
// Flat config.
// ---------------------------------------------------------------------------------------------

export const localPlugin = {
  rules: {
    'no-payload-instance-access': noPayloadInstanceAccess,
    'no-restricted-modules': noRestrictedModules,
    'no-override-access': noOverrideAccess,
  },
};

/**
 * Flat-config blocks for the Payload bans. The options exist so tests can prove each allow-list
 * applies only to its own paths. Without `overrideAccessAllowed`, the system-job list is read from the
 * founder-only file (`allowlist` points tests at a temporary one).
 * @param {{ overrideAccessAllowed?: string[], payloadNameAllowed?: string[], dbClientAllowed?: string[], payloadDbAllowed?: string[], spawnAllowed?: string[], allowlist?: { file?: string, root?: string } }} [lists]
 */
export function payloadBanConfigs({
  allowlist,
  overrideAccessAllowed = readOverrideAllowlist(allowlist),
  payloadNameAllowed = payloadNameAllowedPaths,
  dbClientAllowed = dbClientAllowedPaths,
  payloadDbAllowed = payloadDbAllowedPaths,
  spawnAllowed = spawnAllowedPaths,
} = {}) {
  /** @type {import('@typescript-eslint/utils').TSESLint.FlatConfig.Config[]} */
  const configs = [
    {
      plugins: { local: localPlugin },
      rules: {
        'local/no-payload-instance-access': ['error', {}],
        'local/no-restricted-modules': ['error', {}],
        'local/no-override-access': ['error', {}],
        'no-eval': 'error',
        'no-implied-eval': 'error',
        'no-new-func': 'error',
        'no-with': 'error',
      },
    },
  ];
  if (dbClientAllowed.length > 0) {
    configs.push({
      files: dbClientAllowed,
      rules: { 'local/no-restricted-modules': ['error', { allowDbClients: true }] },
    });
  }
  if (spawnAllowed.length > 0) {
    configs.push({
      files: spawnAllowed,
      rules: { 'local/no-restricted-modules': ['error', { allowSpawn: true }] },
    });
  }
  if (payloadNameAllowed.length > 0) {
    configs.push({
      files: payloadNameAllowed,
      rules: { 'local/no-payload-instance-access': ['error', { allowNames: true }] },
    });
  }
  configs.push({
    files: ['packages/data/**'],
    rules: {
      'local/no-payload-instance-access': 'off',
      'local/no-restricted-modules': ['error', { allowPayload: true, allowDbClients: true }],
      'local/no-override-access': ['error', { requireOptions: true }],
    },
  });
  if (payloadDbAllowed.length > 0) {
    configs.push({
      files: payloadDbAllowed,
      rules: { 'local/no-override-access': ['error', { requireOptions: true, allowDb: true }] },
    });
  }
  if (overrideAccessAllowed.length > 0) {
    // A system job may pass `overrideAccess: true` (and has no user). Every other check stays on for it, `.db` too.
    configs.push({
      files: overrideAccessAllowed,
      rules: {
        'local/no-override-access': ['error', { requireOptions: true, allowOverrideTrue: true }],
      },
    });
  }
  return configs;
}
