import { defineConfig } from 'vitest/config';

// Shared config. Every workspace runs `vitest run --config <root>/vitest.config.ts`
// from its own folder, so `yarn test` fails when coverage drops below 90%.
export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.test.ts'],
      reporter: ['text-summary', 'json-summary'],
      thresholds: {
        lines: 90,
        functions: 90,
        branches: 90,
        statements: 90,
      },
    },
  },
});
