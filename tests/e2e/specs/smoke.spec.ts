import { expect, test } from '@playwright/test';
import { startHealthServer, type TestServer } from '../src/server.js';

let server: TestServer;

test.beforeAll(async () => {
  server = await startHealthServer();
});

test.afterAll(async () => {
  await server.close();
});

test('harness runs: the request client reaches a local server', async ({ request }) => {
  const res = await request.get(`${server.url}/health`);
  expect(res.ok()).toBe(true);
  expect(await res.json()).toEqual({ status: 'ok' });
});

test('harness reports failures: an unknown path is a 404', async ({ request }) => {
  const res = await request.get(`${server.url}/missing`);
  expect(res.status()).toBe(404);
});
