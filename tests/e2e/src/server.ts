import { ok } from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';

export interface TestServer {
  readonly url: string;
  close(): Promise<void>;
}

// A tiny local stand-in for an app, so the harness can be proven without the real admin app or a database.
// Real suites (leak tests, issue #5) replace it with E2E_BASE_URL.
export async function startHealthServer(): Promise<TestServer> {
  const server: Server = createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'not found' }));
  });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      server.off('error', reject);
      resolve();
    });
  });
  const address = server.address();
  ok(address !== null && typeof address === 'object', 'test server has no TCP address');
  const { port }: AddressInfo = address;
  return {
    url: `http://127.0.0.1:${port}`,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.close((err) => (err ? reject(err) : resolve()));
      }),
  };
}
