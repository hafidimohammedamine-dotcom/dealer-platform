import { describe, expect, it } from 'vitest';
import { endSessionsOnDeactivate } from './sessions.js';
import { call } from '../test-helpers/fixtures.js';

const setup = () => {
  const writes: unknown[] = [];
  const req = {
    payload: {
      db: {
        updateOne: async (args: unknown) => {
          writes.push(args);
        },
      },
    },
  };
  return { writes, req };
};
const run = (req: unknown, doc: unknown, previousDoc: unknown, operation: string) =>
  call(endSessionsOnDeactivate, { doc, previousDoc, operation, req });

describe('endSessionsOnDeactivate', () => {
  it('clears every session of a user who has just been deactivated, in the same request', async () => {
    const { writes, req } = setup();
    const doc = { id: 7, active: false };
    await expect(run(req, doc, { id: 7, active: true }, 'update')).resolves.toBe(doc);
    await run(req, { id: 8, active: false }, { id: 8 }, 'update');
    expect(writes).toEqual([
      { collection: 'users', id: 7, data: { sessions: [] }, req, returning: false },
      { collection: 'users', id: 8, data: { sessions: [] }, req, returning: false },
    ]);
  });

  it('leaves the sessions of everyone else alone', async () => {
    const { writes, req } = setup();
    await run(req, { id: 1, active: true }, { id: 1, active: true }, 'update');
    await run(req, { id: 1, active: false }, { id: 1, active: false }, 'update');
    await run(req, { id: 1, active: false }, undefined, 'create');
    await run(req, undefined, undefined, 'update');
    await run(req, { id: 1 }, { id: 1, active: true }, 'update');
    expect(writes).toEqual([]);
  });

  it('fails (so the deactivation rolls back) when the sessions cannot be cleared', async () => {
    const req = {
      payload: { db: { updateOne: async () => Promise.reject(new Error('db down')) } },
    };
    await expect(run(req, { id: 1, active: false }, { id: 1 }, 'update')).rejects.toThrow(
      'db down',
    );
  });
});
