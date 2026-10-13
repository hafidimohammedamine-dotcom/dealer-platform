import { readFileSync } from 'node:fs';
import { afterEach, describe, expect, it, vi } from 'vitest';

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

describe('payload.config.ts (the entry point)', () => {
  it('builds the config from environment variables', async () => {
    vi.stubEnv('APP_ENV', 'dev');
    vi.stubEnv('PAYLOAD_SECRET', 'q'.repeat(40));
    vi.stubEnv('DATABASE_URL', 'postgres://app_user:fake@localhost:5432/dealer');
    vi.stubEnv('PAYLOAD_PUBLIC_SERVER_URL', 'http://localhost:3000');
    const { default: config } = await import('../../payload.config.js');
    const resolved = await config;
    expect(resolved.collections.map((c) => c.slug)).toEqual(
      expect.arrayContaining(['dealers', 'users']),
    );
    expect(resolved.admin.user).toBe('users');
  });

  it('refuses to start without APP_ENV', async () => {
    vi.stubEnv('APP_ENV', '');
    vi.stubEnv('PAYLOAD_SECRET', 'q'.repeat(40));
    vi.stubEnv('DATABASE_URL', 'postgres://app_user:fake@localhost:5432/dealer');
    vi.stubEnv('PAYLOAD_PUBLIC_SERVER_URL', 'http://localhost:3000');
    await expect(import('../../payload.config.js')).rejects.toThrow('APP_ENV');
  });
});

describe('the migration', () => {
  const dir = new URL('../../migrations/', import.meta.url);
  const files = ['index.ts'];
  it('is listed, has up and down, and indexes the dealer column of users_tenants', () => {
    const index = readFileSync(new URL(files[0] ?? '', dir), 'utf8');
    expect(index).toContain('initial');
    const name = /from '\.\/(\d+_\d+_initial)\.js'/.exec(index)?.[1];
    expect(name).toBeDefined();
    const sql = readFileSync(new URL(`${name}.ts`, dir), 'utf8');
    expect(sql).toContain('export async function up');
    expect(sql).toContain('export async function down');
    expect(sql).toContain('CREATE INDEX "users_tenants_tenant_idx" ON "users_tenants"');
    expect(sql).toContain('"active"');
    expect(sql).not.toMatch(/push/i);
  });
});
