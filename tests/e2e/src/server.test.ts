import { describe, expect, it } from 'vitest';
import { startHealthServer } from './server.js';

describe('startHealthServer', () => {
  it('answers GET /health with ok', async () => {
    const server = await startHealthServer();
    try {
      const res = await fetch(`${server.url}/health`);
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({ status: 'ok' });
    } finally {
      await server.close();
    }
  });

  it('answers 404 for another path and for a non-GET method', async () => {
    const server = await startHealthServer();
    try {
      expect((await fetch(`${server.url}/nope`)).status).toBe(404);
      expect((await fetch(`${server.url}/health`, { method: 'POST' })).status).toBe(404);
    } finally {
      await server.close();
    }
  });

  it('stops listening after close', async () => {
    const server = await startHealthServer();
    await server.close();
    await expect(fetch(`${server.url}/health`)).rejects.toThrow();
  });
});
