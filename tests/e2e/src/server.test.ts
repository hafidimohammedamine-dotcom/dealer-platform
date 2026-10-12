import { EventEmitter } from 'node:events';
import { afterEach, describe, expect, it, vi } from 'vitest';
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

  it('rejects a second close', async () => {
    const server = await startHealthServer();
    await server.close();
    await expect(server.close()).rejects.toThrow();
  });
});

describe('startHealthServer with a fake node:http', () => {
  afterEach(() => {
    vi.doUnmock('node:http');
    vi.resetModules();
  });

  async function loadWith(fake: EventEmitter & { listen: unknown; address: unknown }) {
    vi.resetModules();
    vi.doMock('node:http', () => ({ createServer: () => fake }));
    return import('./server.js');
  }

  it('rejects when the server cannot listen', async () => {
    const fake = Object.assign(new EventEmitter(), {
      listen: () => {
        queueMicrotask(() => fake.emit('error', new Error('EADDRINUSE')));
      },
      address: () => null,
    });
    const { startHealthServer: start } = await loadWith(fake);
    await expect(start()).rejects.toThrow('EADDRINUSE');
  });

  it('fails when the server has no TCP address', async () => {
    const fake = Object.assign(new EventEmitter(), {
      listen: (_port: number, _host: string, cb: () => void) => cb(),
      address: () => '/tmp/some.sock',
    });
    const { startHealthServer: start } = await loadWith(fake);
    await expect(start()).rejects.toThrow('test server has no TCP address');
  });

  it('fails when the address is null', async () => {
    const fake = Object.assign(new EventEmitter(), {
      listen: (_port: number, _host: string, cb: () => void) => cb(),
      address: () => null,
    });
    const { startHealthServer: start } = await loadWith(fake);
    await expect(start()).rejects.toThrow('test server has no TCP address');
  });
});
