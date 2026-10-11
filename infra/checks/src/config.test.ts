import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, rmSync, symlinkSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import rootVitestConfig, { lintRuleFiles } from '../../../vitest.config.js';
import {
  dependenciesMetaProblems,
  envValueProblems,
  lifecycleScriptProblems,
  yarnrcProblems,
} from './checks.js';
import {
  findFiles,
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
        'packages/contracts',
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

  it('counts the Payload lint rules toward the infra/checks coverage gate', () => {
    // These tests run from infra/checks, so the config adds the rule files outside src/.
    expect(lintRuleFiles).toEqual([
      join(root, 'eslint-rules/**/*.mjs'),
      join(root, 'eslint.payload-ban.mjs'),
    ]);
    expect(rootVitestConfig.test?.coverage?.include).toEqual(['src/**/*.ts', ...lintRuleFiles]);
    expect(rootVitestConfig.test?.coverage?.allowExternal).toBe(true);
  });
});

const coverageRunTimeout = 150_000;

describe('shared vitest config, failure case', () => {
  const temps: string[] = [];
  afterEach(() => {
    for (const dir of temps.splice(0)) rmSync(dir, { recursive: true, force: true });
  });

  // Runs the real shared config on a throw-away workspace in the temp folder. A run that is killed by the
  // timeout has no exit status (null), so the tests below compare with exact exit codes: a slow runner
  // makes the test fail loudly, and can never make the "below 90%" case pass by accident.
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
      { cwd: dir, env, encoding: 'utf8', timeout: coverageRunTimeout },
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
    expect(status).toBe(1);
  }, 180_000);

  it('exits zero when coverage is full (control)', () => {
    const all = [1, 2, 3, 4, 5].map((n) => `expect(pick(${n})).toBeTypeOf('string');`).join('\n');
    expect(runCoverage(unit, `${imports}it('all', () => {\n${all}\n});\n`)).toBe(0);
  }, 180_000);
});

describe('.yarnrc.yml and install scripts', () => {
  it('holds exactly the allowed settings, with install scripts off', () => {
    expect(yarnrcProblems(readText(root, '.yarnrc.yml'))).toEqual([]);
  });

  it('is the only .yarnrc.yml in the repo', () => {
    expect(findFiles(root, (name) => name === '.yarnrc.yml')).toEqual(['.yarnrc.yml']);
  });

  const manifests = ['package.json', ...listWorkspaces(root).map((ws) => `${ws}/package.json`)];

  it('lets no package build a dependency (dependenciesMeta built: true)', () => {
    for (const file of manifests) {
      expect(dependenciesMetaProblems(readJson(root, file, isRecord), file)).toEqual([]);
    }
  });

  // Yarn's `enableScripts: false` stops dependencies' scripts, not a workspace's own (Yarn docs), so no
  // package.json in the repo may define one.
  it('has no install or pack lifecycle script in the root or any workspace package.json', () => {
    expect(manifests.length).toBeGreaterThan(15);
    for (const file of manifests) {
      expect(lifecycleScriptProblems(readJson(root, file, isRecord), file)).toEqual([]);
    }
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
});

describe('.prettierignore', () => {
  const lines = readText(root, '.prettierignore').split('\n');

  // `yarn format` (prettier --write .) must never rewrite a founder-only file.
  it.each([
    '.github',
    '.claude',
    'CLAUDE.md',
    'scripts/check-*',
    '.gitleaks.toml',
    '.gitleaksignore',
    '.yarnrc.yml',
    '.mcp.json',
    'CLAUDE.local.md',
  ])('skips the founder-only file %s', (entry) => {
    expect(lines).toContain(entry);
  });
});
