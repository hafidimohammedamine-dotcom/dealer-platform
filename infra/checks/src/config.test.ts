import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, rmSync, symlinkSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import rootVitestConfig from '../../../vitest.config.js';
import { envValueProblems, yarnrcKeepsScriptsOff } from './checks.js';
import {
  findRepoRoot,
  isRecord,
  listWorkspaces,
  parseEnvTemplate,
  readJson,
  readText,
} from './repo.js';

const root = findRepoRoot();

const hasCompilerOptions = (
  value: unknown,
): value is { compilerOptions?: Record<string, unknown> } =>
  isRecord(value) && (value['compilerOptions'] === undefined || isRecord(value['compilerOptions']));
const hasScripts = (value: unknown): value is { scripts: Record<string, string> } =>
  isRecord(value) && isRecord(value['scripts']);

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
  const { compilerOptions = {} } = readJson(root, 'tsconfig.base.json', hasCompilerOptions);

  it('keeps TypeScript strict mode on', () => {
    expect(compilerOptions['strict']).toBe(true);
  });

  it('checks indexed access', () => {
    expect(compilerOptions['noUncheckedIndexedAccess']).toBe(true);
  });

  it('does not let any workspace turn strict checks off', () => {
    for (const workspace of listWorkspaces(root)) {
      for (const file of ['tsconfig.json', 'tsconfig.build.json']) {
        const { compilerOptions: own = {} } = readJson(
          root,
          `${workspace}/${file}`,
          hasCompilerOptions,
        );
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
    const { scripts } = readJson(root, `${workspace}/package.json`, hasScripts);
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

describe('shared vitest config, failure case', () => {
  const temps: string[] = [];
  afterEach(() => {
    for (const dir of temps.splice(0)) rmSync(dir, { recursive: true, force: true });
  });

  // Runs the real shared config on a throw-away workspace in the temp folder.
  function runCoverage(source: string, testCode: string): number | null {
    const dir = mkdtempSync(join(tmpdir(), 'coverage-gate-'));
    temps.push(dir);
    mkdirSync(join(dir, 'src'));
    symlinkSync(join(root, 'node_modules'), join(dir, 'node_modules'), 'dir');
    writeFileSync(join(dir, 'src', 'unit.ts'), source);
    writeFileSync(join(dir, 'src', 'unit.test.ts'), testCode);
    const env = { ...process.env };
    for (const name of Object.keys(env)) if (name.startsWith('VITEST')) delete env[name];
    const vitestBin = join(root, 'node_modules', 'vitest', 'vitest.mjs');
    return spawnSync(
      process.execPath,
      [vitestBin, 'run', '--coverage', '--config', join(root, 'vitest.config.ts')],
      { cwd: dir, env, encoding: 'utf8' },
    ).status;
  }

  const unit = `export function pick(n: number): string {
  if (n === 1) return 'one';
  if (n === 2) return 'two';
  if (n === 3) return 'three';
  if (n === 4) return 'four';
  return 'many';
}
`;
  const imports = "import { expect, it } from 'vitest';\nimport { pick } from './unit.js';\n";

  it('exits non-zero when coverage is below 90%', () => {
    const status = runCoverage(unit, `${imports}it('one', () => expect(pick(1)).toBe('one'));\n`);
    expect(status).not.toBe(0);
  }, 60_000);

  it('exits zero when coverage is full (control)', () => {
    const all = [1, 2, 3, 4, 5].map((n) => `expect(pick(${n})).toBeTypeOf('string');`).join('\n');
    expect(runCoverage(unit, `${imports}it('all', () => {\n${all}\n});\n`)).toBe(0);
  }, 60_000);
});

describe('.yarnrc.yml', () => {
  it('keeps dependency install scripts off', () => {
    expect(yarnrcKeepsScriptsOff(readText(root, '.yarnrc.yml'))).toBe(true);
  });

  it('catches scripts turned on, missing or commented out', () => {
    expect(yarnrcKeepsScriptsOff('enableScripts: true\n')).toBe(false);
    expect(yarnrcKeepsScriptsOff('nodeLinker: node-modules\n')).toBe(false);
    expect(yarnrcKeepsScriptsOff('# enableScripts: false\n')).toBe(false);
    expect(yarnrcKeepsScriptsOff('nodeLinker: node-modules\nenableScripts: false\n')).toBe(true);
  });
});

describe('.env.example', () => {
  const vars = parseEnvTemplate(readText(root, '.env.example'));

  it('lists every expected variable and nothing else', () => {
    expect([...vars.keys()].sort()).toEqual([...expectedEnvKeys].sort());
  });

  it('has no real-looking secret values', () => {
    expect(envValueProblems(vars)).toEqual([]);
  });

  it('leaves every key, token and secret empty', () => {
    for (const [key, value] of vars) {
      if (/(SECRET|KEY|TOKEN)/.test(key)) expect(value, key).toBe('');
    }
  });
});

describe('env value checker catches bad values', () => {
  // Built at run time so no secret-looking text sits in the source.
  const fake = ['not', 'a', 'real', 'value'].join('-');

  it('flags a filled key, token or secret', () => {
    expect(envValueProblems(new Map([['TELNYX_API_KEY', fake]]))).toEqual([
      'TELNYX_API_KEY: must be empty',
    ]);
    expect(envValueProblems(new Map([['META_VERIFY_TOKEN', fake]]))).toHaveLength(1);
  });

  it('flags a non-local host and a real-looking password', () => {
    const url = ['postgres://u:', fake, '@db.example.com:5432/x'].join('');
    expect(envValueProblems(new Map([['DATABASE_URL', url]]))).toEqual([
      'DATABASE_URL: host must be localhost',
      'DATABASE_URL: password must be empty or change-me',
    ]);
  });

  it('flags a plain value that is not APP_ENV=dev', () => {
    expect(envValueProblems(new Map([['SENTRY_DSN', fake]]))).toHaveLength(1);
    expect(envValueProblems(new Map([['APP_ENV', 'production']]))).toHaveLength(1);
  });

  it('accepts the allowed shapes', () => {
    const ok = new Map([
      ['APP_ENV', 'dev'],
      ['DATABASE_URL', 'postgres://u:change-me@localhost:5432/x'],
      ['REDIS_URL', 'redis://localhost:6379'],
      ['PAYLOAD_SECRET', ''],
    ]);
    expect(envValueProblems(ok)).toEqual([]);
  });
});
