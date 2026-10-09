import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import { payloadBanConfigs } from './eslint.payload-ban.mjs';

export default tseslint.config(
  {
    // Nobody can switch the Payload bans off with a comment. A comment that tries to is an error.
    linterOptions: { noInlineConfig: true, reportUnusedDisableDirectives: 'error' },
  },
  { ignores: ['**/dist/**', '**/node_modules/**', '**/.nx/**', '**/.yarn/**', '**/coverage/**'] },
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
