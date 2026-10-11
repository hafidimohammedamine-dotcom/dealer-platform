import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const repoRoot = dirname(fileURLToPath(import.meta.url));

// The Payload lint rules live at the repo root but are tested by infra/checks, so they count toward
// that workspace's coverage gate.
export const lintRuleFiles = ['eslint-rules/**/*.mjs', 'eslint.payload-ban.mjs'].map((glob) =>
  resolve(repoRoot, glob),
);
const isInfraChecks = resolve(process.cwd()) === resolve(repoRoot, 'infra/checks');

// Shared config. Every workspace runs `vitest run --config <root>/vitest.config.ts`
// from its own folder, so `yarn test` fails when coverage drops below 90%.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts', ...(isInfraChecks ? lintRuleFiles : [])],
      exclude: ['src/**/*.test.ts'],
      allowExternal: isInfraChecks,
      reporter: ['text-summary', 'json-summary'],
      // Each file must reach the thresholds on its own, so one weak file cannot hide behind the totals.
      thresholds: {
        perFile: true,
        lines: 90,
        functions: 90,
        branches: 90,
        statements: 90,
      },
    },
  },
});
