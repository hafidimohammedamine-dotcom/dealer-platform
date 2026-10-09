import js from '@eslint/js';
import globals from 'globals';
import tseslint from 'typescript-eslint';
import { payloadBanConfig } from './eslint.payload-ban.mjs';

export default tseslint.config(
  { ignores: ['**/dist/**', '**/node_modules/**', '**/.nx/**', '**/.yarn/**', '**/coverage/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  { languageOptions: { globals: { ...globals.node } } },
  payloadBanConfig,
);
