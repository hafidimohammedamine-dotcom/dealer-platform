import { describe, expect, it } from 'vitest';
import { createAuditLog, lineSink, redact } from './audit.js';
import type { AuditEntry } from './audit.js';

const fixed = () => new Date('2026-10-12T10:00:00.000Z');

describe('redact', () => {
  it('replaces secret-looking keys and keeps plain values', () => {
    expect(
      redact({
        role: 'admin',
        password: 'p',
        resetPasswordToken: 't',
        salt: 's',
        hash: 'h',
        ssn: '900-00-0000',
        apiKey: 'k',
        nested: { sessions: [1], ok: true },
        n: 3,
      }),
    ).toEqual({
      role: 'admin',
      password: '[removed]',
      resetPasswordToken: '[removed]',
      salt: '[removed]',
      hash: '[removed]',
      ssn: '[removed]',
      apiKey: '[removed]',
      nested: { sessions: '[removed]', ok: true },
      n: 3,
    });
  });

  it('drops functions, odd numbers and very deep data', () => {
    const out = redact({
      f: () => 1,
      bad: Number.NaN,
      nil: null,
      deep: { a: { b: { c: { d: { e: 1 } } } } },
    });
    expect(out['f']).toBe('[removed]');
    expect(out['bad']).toBeNull();
    expect(out['nil']).toBeNull();
    expect(redact({ list: [{ token: 't', ok: 1 }, 2] })).toEqual({
      list: [{ token: '[removed]', ok: 1 }, 2],
    });
    expect(JSON.stringify(out['deep'])).toContain('[removed]');
  });
});

describe('createAuditLog', () => {
  it('writes a frozen, redacted entry with an ISO UTC time', async () => {
    const seen: AuditEntry[] = [];
    const log = createAuditLog({ append: (e) => void seen.push(e) }, fixed);
    const entry = await log.record({
      action: 'user.update',
      actorId: 7,
      target: { collection: 'users', id: 'u1' },
      dealerIds: ['d1', 2],
      before: { role: 'bdc', password: 'x' },
      after: { role: 'admin' },
    });
    expect(seen).toEqual([entry]);
    expect(entry).toEqual({
      at: '2026-10-12T10:00:00.000Z',
      action: 'user.update',
      actorId: 7,
      target: { collection: 'users', id: 'u1' },
      dealerIds: ['d1', '2'],
      before: { role: 'bdc', password: '[removed]' },
      after: { role: 'admin' },
    });
    expect(Object.isFrozen(entry)).toBe(true);
    expect(Object.isFrozen(entry.before)).toBe(true);
    expect(Reflect.set(entry, 'action', 'x')).toBe(false);
  });

  it('omits before and after when not given, and uses the real clock by default', async () => {
    const log = createAuditLog({ append: () => undefined });
    const entry = await log.record({
      action: 'dealer.update',
      actorId: null,
      target: { collection: 'dealers', id: null },
      dealerIds: [],
    });
    expect('before' in entry).toBe(false);
    expect('after' in entry).toBe(false);
    expect(entry.at).toMatch(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/);
  });

  it('fails when the sink fails, so the caller stops the change', async () => {
    const log = createAuditLog({
      append: () => {
        throw new Error('disk full');
      },
    });
    await expect(
      log.record({
        action: 'a',
        actorId: 1,
        target: { collection: 'users', id: 1 },
        dealerIds: [],
      }),
    ).rejects.toThrow('disk full');
  });
});

describe('lineSink', () => {
  it('writes one JSON line per entry', async () => {
    const lines: string[] = [];
    const log = createAuditLog(
      lineSink((l) => void lines.push(l)),
      fixed,
    );
    await log.record({
      action: 'a',
      actorId: 1,
      target: { collection: 'users', id: 1 },
      dealerIds: ['d'],
    });
    expect(lines).toHaveLength(1);
    expect(lines[0]?.endsWith('\n')).toBe(true);
    expect(JSON.parse(lines[0] ?? '')).toMatchObject({ audit: { action: 'a', dealerIds: ['d'] } });
  });
});
