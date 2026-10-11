import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import { payloadBanConfigs } from './eslint.payload-ban.mjs';

export default tseslint.config(
  // Lint every source extension. ESLint only picks up a file whose extension some block names, so
  // without this `.jsx` files would never be linted and the Payload bans below would not run on them.
  { files: ['**/*.{js,jsx,mjs,cjs,ts,tsx,mts,cts}'] },
  {
    // Nobody can switch the Payload bans off with a comment. A comment that tries to is an error.
    linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: 'error' },
  },
  {
    // Build outputs only, anchored to the top of a workspace. A `dist` or `coverage` folder deeper in the source tree
    // (`apps/admin/src/x/dist/y.ts`) is source and is linted, so no folder name can hide a file from the Payload bans.
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
  ...payloadBanConfigs(),
);
