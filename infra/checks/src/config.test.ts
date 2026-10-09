import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import rootVitestConfig from '../../../vitest.config.js';
import { findRepoRoot, listWorkspaces, parseEnvTemplate, readJson, readText } from './repo.js';

const root = findRepoRoot();

// Add a name here (and to .env.example) whenever a service needs a new variable.
const expectedEnvKeys = [
  'APP_ENV',
  'DATABASE_URL',
  'MIGRATION_DATABASE_URL',
  'DESKING_DATABASE_URL',
  'REDIS_URL',
  'PAYLOAD_SECRET',
  'PAYLOAD_PUBLIC_SERVER_URL',
  'FIELD_ENCRYPTION_KEY',
  'RESEND_API_KEY',
  'RESEND_WEBHOOK_SECRET',
  'TELNYX_API_KEY',
  'TELNYX_PUBLIC_KEY',
  'TELNYX_MESSAGING_PROFILE_ID',
  'ELEVENLABS_API_KEY',
  'ELEVENLABS_WEBHOOK_SECRET',
  'ANTHROPIC_API_KEY',
  'META_APP_SECRET',
  'META_VERIFY_TOKEN',
  'META_PAGE_ACCESS_TOKEN',
  'ROUTEONE_CLIENT_ID',
  'ROUTEONE_CLIENT_SECRET',
  'ROUTEONE_WEBHOOK_SECRET',
  'DEALERTRACK_CLIENT_ID',
  'DEALERTRACK_CLIENT_SECRET',
  'DEALERTRACK_WEBHOOK_SECRET',
  'SENTRY_DSN',
];

describe('tsconfig.base.json', () => {
  const { compilerOptions } = readJson<{ compilerOptions: Record<string, unknown> }>(
    root,
    'tsconfig.base.json',
  );

  it('keeps TypeScript strict mode on', () => {
    expect(compilerOptions['strict']).toBe(true);
  });

  it('checks indexed access', () => {
    expect(compilerOptions['noUncheckedIndexedAccess']).toBe(true);
  });

  it('does not let any workspace turn strict checks off', () => {
    for (const workspace of listWorkspaces(root)) {
      for (const file of ['tsconfig.json', 'tsconfig.build.json']) {
        const { compilerOptions: own = {} } = readJson<{
          compilerOptions?: Record<string, unknown>;
        }>(root, `${workspace}/${file}`);
        expect(own['strict'], `${workspace}/${file}`).not.toBe(false);
        expect(own['noUncheckedIndexedAccess'], `${workspace}/${file}`).not.toBe(false);
      }
    }
  });
});

describe('workspaces', () => {
  const workspaces = listWorkspaces(root);

  it('include every folder from CLAUDE.md that needs a package', () => {
    expect(workspaces).toEqual(
      expect.arrayContaining([
        'apps/admin',
        'infra/checks',
        'packages/data',
        'packages/platform',
        'packages/ui',
        'services/accounting',
        'services/ai',
        'services/callbacks',
        'services/desking',
        'services/documents',
        'services/intake',
        'services/inventory',
        'services/lenders',
        'services/messaging',
        'services/voice',
      ]),
    );
  });

  it.each(workspaces)('%s has tests and test, typecheck and build scripts', (workspace) => {
    const { scripts } = readJson<{ scripts: Record<string, string> }>(
      root,
      `${workspace}/package.json`,
    );
    expect(scripts['typecheck']).toContain('tsc');
    expect(scripts['build']).toContain('tsc');
    // Coverage must be on, with the shared config that holds the 90% gate.
    expect(scripts['test']).toContain('vitest run');
    expect(scripts['test']).toContain('--coverage');
    expect(scripts['test']).toContain('--config ../../vitest.config.ts');
    const files = readdirSync(join(root, workspace, 'src'));
    expect(files.some((name) => name.endsWith('.test.ts'))).toBe(true);
  });
});

describe('shared vitest config', () => {
  it('gates coverage at 90% for lines, functions, branches and statements', () => {
    expect(rootVitestConfig.test?.coverage?.thresholds).toEqual({
      lines: 90,
      functions: 90,
      branches: 90,
      statements: 90,
    });
  });
});

describe('.yarnrc.yml', () => {
  it('keeps dependency install scripts off', () => {
    expect(readText(root, '.yarnrc.yml')).toMatch(/^enableScripts:\s*false\s*$/m);
  });
});

describe('.env.example', () => {
  const vars = parseEnvTemplate(readText(root, '.env.example'));

  it('lists every expected variable and nothing else', () => {
    expect([...vars.keys()].sort()).toEqual([...expectedEnvKeys].sort());
  });

  it('has no real-looking secret values', () => {
    for (const [key, value] of vars) {
      if (value === '') continue;
      if (/^[a-z]+:\/\//.test(value)) {
        const url = new URL(value);
        expect(url.hostname, key).toBe('localhost');
        expect(['', 'change-me'], key).toContain(url.password);
      } else {
        // The only plain value allowed is the environment name.
        expect(key).toBe('APP_ENV');
        expect(value).toBe('dev');
      }
    }
  });

  it('leaves every key, token and secret empty', () => {
    for (const [key, value] of vars) {
      if (/(SECRET|KEY|TOKEN)/.test(key)) expect(value, key).toBe('');
    }
  });
});
