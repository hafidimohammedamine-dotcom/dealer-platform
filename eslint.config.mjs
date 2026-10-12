import js from '@eslint/js';
import globals from 'globals';
import { defineConfig } from 'eslint/config';
import tseslint from 'typescript-eslint';

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
);
