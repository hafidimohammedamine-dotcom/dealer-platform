import { expect, test } from '@playwright/test';
import { startHealthServer, type TestServer } from '../src/server.js';

let server: TestServer;

test.beforeAll(async () => {
  server = await startHealthServer();
});

test.afterAll(async () => {
  await server.close();
});

test.describe('with a base URL', () => {
  test('a relative path resolves against baseURL', async ({ playwright }) => {
    const request = await playwright.request.newContext({ baseURL: server.url });
    const res = await request.get('/health');
    expect(await res.json()).toEqual({ status: 'ok' });
    await request.dispose();
  });
});

test.describe('without a base URL', () => {
  test('a relative path fails instead of calling something else', async ({ playwright }) => {
    const request = await playwright.request.newContext();
    await expect(request.get('/health')).rejects.toThrow(/Invalid URL/i);
    await request.dispose();
  });
});
