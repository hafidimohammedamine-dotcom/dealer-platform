import { afterEach, describe, expect, it, vi } from 'vitest';

async function loadConfig() {
  vi.resetModules();
  return (await import('../playwright.config.js')).default;
}

describe('playwright.config E2E_BASE_URL', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it('uses E2E_BASE_URL as the baseURL when set', async () => {
    vi.stubEnv('E2E_BASE_URL', 'http://localhost:3000');
    expect((await loadConfig()).use?.baseURL).toBe('http://localhost:3000');
  });

  it('has no baseURL when E2E_BASE_URL is unset', async () => {
    vi.stubEnv('E2E_BASE_URL', undefined);
    expect((await loadConfig()).use?.baseURL).toBeUndefined();
  });

  it('treats an empty E2E_BASE_URL as no base URL', async () => {
    vi.stubEnv('E2E_BASE_URL', '');
    expect((await loadConfig()).use?.baseURL).toBeUndefined();
  });
});
