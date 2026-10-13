import { defineConfig } from '@playwright/test';

// A browser is a one-time manual install (`yarn workspace @dealer/e2e playwright install chromium`). It downloads
// binaries at run time, so run it only on a developer machine or in a CI job with no secrets, and never set
// PLAYWRIGHT_DOWNLOAD_HOST (issue #62). The specs here use Playwright's request client only, so they need no browser.
// The leak-test harness (issue #5) adds API projects here and reads the base URL from E2E_BASE_URL (never a secret).
export default defineConfig({
  testDir: './specs',
  testMatch: '**/*.spec.ts',
  fullyParallel: true,
  forbidOnly: true,
  retries: 0,
  reporter: [['list']],
  // An empty E2E_BASE_URL counts as unset.
  use: { baseURL: process.env['E2E_BASE_URL'] || undefined },
});
