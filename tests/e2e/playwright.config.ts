import { defineConfig } from '@playwright/test';

// Browsers are NOT downloaded at install (lifecycle scripts are off). Run `yarn workspace @dealer/e2e playwright install chromium`
// once on a machine that needs a browser. The smoke test uses Playwright's request client only, so it needs no browser.
// The leak-test harness (issue #5) adds API projects here and reads the base URL from E2E_BASE_URL (never a secret).
export default defineConfig({
  testDir: './specs',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  forbidOnly: true,
  retries: 0,
  reporter: [['list']],
  use: { baseURL: process.env['E2E_BASE_URL'] },
});
