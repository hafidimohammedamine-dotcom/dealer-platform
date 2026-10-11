import { defineConfig } from 'vitest/config';

// Shared config. Every workspace runs `vitest run --config <its vitest.config.ts>` from its own folder
// (most use this file directly), so `yarn test` fails when coverage drops below 90%.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.test.ts'],
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
