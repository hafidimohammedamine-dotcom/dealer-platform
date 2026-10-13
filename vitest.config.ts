import { defineConfig } from 'vitest/config';

// Shared config. Every workspace runs `vitest run --config <its vitest.config.ts>` from its own folder
// (most use this file directly), so `yarn test` fails when coverage drops below 90%.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      // Source only: the admin app's entry point and migrations count too; test files and test helpers do not.
      include: ['src/**/*.ts', 'payload.config.ts', 'migrations/**/*.ts'],
      exclude: ['src/**/*.test.ts', 'src/**/test-helpers/**'],
      // `text` prints a table of every file (fully covered ones too) in each workspace's test log, so the CI log shows it.
      reporter: [['text', { skipFull: false }], 'json-summary'],
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
