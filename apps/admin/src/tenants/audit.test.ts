import { describe, expect, it, vi } from 'vitest';
import { accessAudit, writeToStdout } from './audit.js';

describe('the access audit log', () => {
  it('writes one JSON line per entry to stdout', async () => {
    const write = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    try {
      await accessAudit.record({
        action: 'user.create',
        actorId: 'a',
        target: { collection: 'users', id: 'u' },
        dealerIds: ['d'],
        after: { role: 'bdc', password: 'secret' },
      });
      writeToStdout('x\n');
      const first = String(write.mock.calls[0]?.[0]);
      expect(JSON.parse(first)).toMatchObject({ audit: { action: 'user.create' } });
      expect(first).not.toContain('secret');
      expect(write.mock.calls[1]?.[0]).toBe('x\n');
    } finally {
      write.mockRestore();
    }
  });
});
