import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mergeConfig } from 'vitest/config';
import rootConfig from '../../vitest.config.js';

const repoRoot = fileURLToPath(new URL('../..', import.meta.url));

// The Payload lint rules live at the repo root but are tested by infra/checks, so they count toward
// this workspace's coverage gate. Everything else comes from the shared config.
export const lintRuleFiles = ['eslint-rules/**/*.mjs', 'eslint.payload-ban.mjs'].map((glob) =>
  resolve(repoRoot, glob),
);

export default mergeConfig(rootConfig, {
  test: {
    coverage: {
      include: lintRuleFiles,
      allowExternal: true,
    },
  },
});
