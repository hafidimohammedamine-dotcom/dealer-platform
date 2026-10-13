import js from '@eslint/js';
import globals from 'globals';
import { defineConfig } from 'eslint/config';
import tseslint from 'typescript-eslint';

const NOT_A_PAYLOAD_INSTANCE =
  'Get data through packages/data (Payload rule 1), not a Payload instance.';
const PAYLOAD_INSTANCE_IMPORTS = ['payload', '@payloadcms/next/utilities'].map((name) => ({
  name,
  importNames: ['getPayload'],
  message: NOT_A_PAYLOAD_INSTANCE,
}));
const LOCAL_API =
  '/^(find|findByID|findDistinct|count|countVersions|create|update|delete|duplicate|findGlobal|updateGlobal|findVersions|findVersionByID|restoreVersion|login|forgotPassword|resetPassword|unlock|verifyEmail|sendEmail|auth)$/';
const PAYLOAD_PACKAGES = '/^(payload|@payloadcms\\/next\\/utilities)$/';
const RULE_1 = {
  call: {
    // `payload.find(...)`, `req.payload.find(...)`.
    selector: `CallExpression[callee.type='MemberExpression'][callee.property.name=${LOCAL_API}]:matches([callee.object.name='payload'], [callee.object.property.name='payload'])`,
    message:
      'Do not call the Payload Local API directly (Payload rule 1). Use packages/data (tenant-safe helper).',
  },
  localApiShape: {
    // Any object or bare function called like the Local API: `p.find({ collection })`, `find({ collection })`.
    selector: `CallExpression:matches([callee.property.name=${LOCAL_API}], [callee.name=${LOCAL_API}]) > ObjectExpression.arguments:first-child > Property:matches([key.name=/^(collection|slug)$/], [key.value=/^(collection|slug)$/])`,
    message:
      'Do not call the Payload Local API directly (Payload rule 1). Use packages/data (tenant-safe helper).',
  },
  alias: {
    // Aliases hide the instance from the checks above: `const p = req.payload`, `p = req.payload`, `x = { db } = ...`.
    selector:
      ':matches(VariableDeclarator > MemberExpression.init, AssignmentExpression > MemberExpression.right)[property.name=/^(payload|db)$/]',
    message: 'Do not keep the Payload instance or its database in a variable (Payload rule 1).',
  },
  destructure: {
    // `const { payload } = req`, `({ req: { payload } }) => ...`, `const { db } = payload`.
    selector:
      'ObjectPattern > Property:matches([key.name=/^(payload|db)$/], [key.value=/^(payload|db)$/])',
    message: 'Do not take the Payload instance or its database out of an object (Payload rule 1).',
  },
  accessOverride: {
    // Anything but the literal `false`: `true`, a variable, shorthand `{ overrideAccess }`, an expression.
    selector:
      "Property:matches([key.name='overrideAccess'], [key.value='overrideAccess']):not([value.value=false])",
    message:
      'overrideAccess must be the literal false. true is only for a reviewed system job in packages/data/override-allowlist.txt (Payload rule 1).',
  },
  namespaceImport: {
    selector: `ImportDeclaration[source.value=${PAYLOAD_PACKAGES}] > :matches(ImportNamespaceSpecifier, ImportDefaultSpecifier)`,
    message: NOT_A_PAYLOAD_INSTANCE,
  },
  dynamicImport: {
    selector: `:matches(ImportExpression[source.value=${PAYLOAD_PACKAGES}], ImportExpression[source.type!='Literal'], CallExpression[callee.name='require'])`,
    message:
      'Import Payload statically and by name (Payload rule 1); dynamic imports and require hide what is used.',
  },
  db: {
    selector:
      ":matches(MemberExpression[object.name='payload'], MemberExpression[object.property.name='payload'])[property.name='db']",
    message: 'Do not reach the database through Payload directly (Payload rule 1).',
  },
};
/** The Payload rule 1 checks, minus the named ones (each exception below is one file pattern and one check). */
const rule1Without = (...skip) => [
  'error',
  ...Object.entries(RULE_1)
    .filter(([name]) => !skip.includes(name))
    .map(([, check]) => check),
];

// The only ESLint config. `yarn lint` passes it with `--config`, so a config file anywhere else is never used.
export default defineConfig(
  // Lint every source extension. ESLint only picks up a file whose extension some block names.
  { files: ['**/*.{js,jsx,mjs,cjs,ts,tsx,mts,cts}'] },
  {
    // A rule cannot be switched off by a comment in a file. An exception goes in this file, where review sees it.
    linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: 'error' },
  },
  {
    // Install, cache and build output only. A config test fails if any file in these folders is committed.
    ignores: [
      '{apps,services,packages,infra}/*/dist/**',
      '{apps,services,packages,infra}/*/coverage/**',
      '**/node_modules/**',
      '.nx/**',
      '.yarn/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  { languageOptions: { globals: { ...globals.node } } },
  {
    // No unchecked casts (`x as T`, `<T>x`). Narrow with a type guard instead.
    files: ['**/*.ts', '**/*.tsx', '**/*.mts', '**/*.cts'],
    rules: {
      '@typescript-eslint/consistent-type-assertions': ['error', { assertionStyle: 'never' }],
    },
  },
  {
    // Payload rule 1 (CLAUDE.md): all data access goes through packages/data, which passes the user and
    // `overrideAccess: false`. These are syntax checks (a stopgap): the type-aware rule and the reviewed system-job
    // allowlist (packages/data/override-allowlist.txt) are issue #36, waiting for a founder decision (#46).
    files: ['**/*.{js,jsx,mjs,cjs,ts,tsx,mts,cts}'],
    rules: {
      'no-restricted-imports': ['error', { paths: PAYLOAD_INSTANCE_IMPORTS }],
      'no-restricted-syntax': rule1Without(),
    },
  },
  {
    // The helper itself: it is the one place that calls the Local API (with the user and `overrideAccess: false`).
    files: ['packages/data/src/**'],
    rules: { 'no-restricted-syntax': rule1Without('localApiShape') },
  },
  {
    // Payload generates `up({ db, payload, req })` for every migration; migrations run SQL through `db` in the CI job.
    files: ['apps/admin/migrations/*.ts'],
    rules: { 'no-restricted-syntax': rule1Without('destructure') },
  },
  {
    // The one reviewed place that writes Payload's `sessions` field (no API can: its update access is false), to end
    // every login of a deactivated user. It may reach `req.payload.db`; every other Payload rule 1 check still applies.
    files: ['apps/admin/src/tenants/sessions.ts'],
    rules: { 'no-restricted-syntax': rule1Without('db') },
  },
);
