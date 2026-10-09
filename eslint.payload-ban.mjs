// @ts-check
// Payload rule 1: the Local API skips access checks by default, so every data call goes through
// packages/data. A list of "bad uses" of the Payload instance can never be complete, so these rules
// ban where the instance comes from and every name it goes by. False positives are fine here.
// Bypasses are not.
//
//   local/no-payload-instance-access  outside packages/data: no identifier, key, string or type named
//                                     payload / getPayload* / Payload / BasePayload (only `payload.logger`),
//                                     no `Reflect`, and no dynamic key (`obj[k]`) that is called, chained
//                                     or destructured.
//   local/no-restricted-modules       outside packages/data: no value import of `payload` (type-only imports
//                                     are fine), no database client at all, no import()/require() with a
//                                     computed name, no `require` or `createRequire` used as a value.
//   local/no-override-access          everywhere: `overrideAccess` is only ever the literal `false`. In
//                                     packages/data every Local API call passes one object literal with
//                                     `overrideAccess: false`, `depth` and `versions`, no spreads and no
//                                     computed keys.
//
// Inline eslint comments are off (see eslint.config.mjs), so none of these can be disabled in a file.
// The last locks are Postgres row-level security and the cross-dealer leak tests.
//
// Files: eslint-rules/payload-lists.mjs (reviewed allow-lists and banned names), one file per rule
// in eslint-rules/, and eslint-rules/ast.mjs (shared helpers).

import { noOverrideAccess } from './eslint-rules/no-override-access.mjs';
import { noPayloadInstanceAccess } from './eslint-rules/no-payload-instance-access.mjs';
import { noRestrictedModules } from './eslint-rules/no-restricted-modules.mjs';
import {
  dbClientAllowedPaths,
  overrideAccessAllowedPaths,
  payloadNameAllowedPaths,
} from './eslint-rules/payload-lists.mjs';

export {
  allowedPayloadMembers,
  allowedPayloadValueImports,
  dbClientAllowedPaths,
  isDbClientModule,
  localApiMethods,
  overrideAccessAllowedPaths,
  payloadNameAllowedPaths,
  requiredLocalApiOptions,
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
 * applies only to its own paths.
 * @param {{ overrideAccessAllowed?: string[], payloadNameAllowed?: string[], dbClientAllowed?: string[] }} [lists]
 */
export function payloadBanConfigs({
  overrideAccessAllowed = overrideAccessAllowedPaths,
  payloadNameAllowed = payloadNameAllowedPaths,
  dbClientAllowed = dbClientAllowedPaths,
} = {}) {
  /** @type {{ files?: string[], plugins?: Record<string, unknown>, rules: Record<string, unknown> }[]} */
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
  if (overrideAccessAllowed.length > 0) {
    configs.push({ files: overrideAccessAllowed, rules: { 'local/no-override-access': 'off' } });
  }
  return configs;
}
