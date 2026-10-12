import { Server } from 'node:http';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { startHealthServer } from './server.js';

describe('startHealthServer', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

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

  it('rejects a second close', async () => {
    const server = await startHealthServer();
    await server.close();
    await expect(server.close()).rejects.toThrow();
  });

  it('rejects when the port cannot be opened', async () => {
    vi.spyOn(Server.prototype, 'listen').mockImplementation(function (this: Server) {
      queueMicrotask(() => this.emit('error', new Error('listen failed')));
      return this;
    });
    await expect(startHealthServer()).rejects.toThrow('listen failed');
  });

  it('fails when the server has no TCP address', async () => {
    vi.spyOn(Server.prototype, 'address').mockReturnValue('/tmp/pipe');
    await expect(startHealthServer()).rejects.toThrow('test server has no TCP address');
  });
});
