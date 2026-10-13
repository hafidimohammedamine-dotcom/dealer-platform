import { spawnSync } from 'node:child_process';
import { mkdtempSync, readdirSync, rmSync, symlinkSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import rootVitestConfig from '../../../vitest.config.js';
import { dependenciesMetaProblems, lifecycleScriptProblems, yarnrcProblems } from './checks.js';
import { hasScripts, isRecord, listWorkspaces, readJson, readText, trackedFiles } from './repo.js';
import { root } from './test-helpers/root.js';

const hasCompilerOptions = (
  value: unknown,
): value is { compilerOptions?: Record<string, unknown> } =>
  isRecord(value) && (value['compilerOptions'] === undefined || isRecord(value['compilerOptions']));

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
      perFile: true,
      lines: 90,
      functions: 90,
      branches: 90,
      statements: 90,
    });
  });

  it('measures every source file (src, the admin entry point and migrations), not tests or test helpers, and prints a per-file table', () => {
    const coverage = rootVitestConfig.test?.coverage;
    expect(coverage?.include).toEqual(['src/**/*.ts', 'payload.config.ts', 'migrations/**/*.ts']);
    expect(coverage?.exclude).toEqual(['src/**/*.test.ts', 'src/**/test-helpers/**']);
    expect(coverage?.reporter).toContainEqual(['text', { skipFull: false }]);
  });
});

describe('root scripts, yarn.lock and CI', () => {
  const { scripts } = readJson(root, 'package.json', hasScripts);

  it('has the lint, typecheck, test and build scripts CI runs', () => {
    expect(scripts['lint']).toBe('eslint --config eslint.config.mjs . && prettier --check .');
    expect(scripts['typecheck']).toBe('nx run-many -t typecheck');
    expect(scripts['test']).toBe('nx run-many -t test');
    expect(scripts['build']).toBe('nx run-many -t build');
  });

  it('runs those scripts in CI after `yarn install --immutable`, in this order', () => {
    const ci = readText(root, '.github/workflows/ci.yml');
    const steps = [
      'yarn install --immutable',
      'yarn lint',
      'yarn typecheck',
      'yarn test',
      'yarn build',
      'yarn npm audit --severity moderate --all --recursive',
    ];
    const positions = steps.map((step) =>
      ci.search(new RegExp(`^\\s+run: (?:corepack enable && )?${step}$`, 'm')),
    );
    expect(
      positions.every((position) => position >= 0),
      steps.join(', '),
    ).toBe(true);
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
  });

  // `yarn install --immutable` fails when yarn.lock would change, so the lockfile must list every workspace
  // (and no folder that is not one) with its current name.
  it('lists every workspace, and only the workspaces, in yarn.lock', () => {
    const lock = readText(root, 'yarn.lock');
    const locked = [...lock.matchAll(/^ {2}resolution: "(.+)@workspace:(.+)"$/gm)].map(
      (match) => `${match[1]}@${match[2]}`,
    );
    const hasName = (value: unknown): value is { name: string } =>
      isRecord(value) && typeof value['name'] === 'string';
    const expected = ['.', ...listWorkspaces(root)].map((workspace) => {
      const { name } = readJson(
        root,
        `${workspace === '.' ? '' : `${workspace}/`}package.json`,
        hasName,
      );
      return `${name}@${workspace}`;
    });
    expect(locked.sort()).toEqual(expected.sort());
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
  function runCoverage(
    source: string,
    testCode: string,
    { extra = [], files = [] }: { extra?: string[]; files?: [string, string][] } = {},
  ): number | null {
    const dir = mkdtempSync(join(tmpdir(), 'coverage-gate-'));
    temps.push(dir);
    mkdirSync(join(dir, 'src'));
    symlinkSync(join(root, 'node_modules'), join(dir, 'node_modules'), 'dir');
    writeFileSync(join(dir, 'src', 'unit.ts'), source);
    writeFileSync(join(dir, 'src', 'unit.test.ts'), testCode);
    for (const [name, text] of files) writeFileSync(join(dir, 'src', name), text);
    const env = { ...process.env };
    for (const name of Object.keys(env)) if (name.startsWith('VITEST')) delete env[name];
    const vitestBin = join(root, 'node_modules', 'vitest', 'vitest.mjs');
    return spawnSync(
      process.execPath,
      [vitestBin, 'run', '--coverage', '--config', join(root, 'vitest.config.ts'), ...extra],
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

  // Two files: `big.ts` is fully covered and large, so the totals pass, but `unit.ts` alone is below 90%.
  const big = Array.from(
    { length: 40 },
    (_, n) =>
      `export function f${n}(x: boolean): number {\n  if (x) return 1;\n  return 2;\n}\nf${n}(true);\nf${n}(false);`,
  ).join('\n');
  const useBig = "import './big.js';\n";

  it('exits non-zero when one file is below 90% even though the totals pass', () => {
    const test = `${useBig}${imports}it('one', () => expect(pick(1)).toBe('one'));\n`;
    expect(runCoverage(unit, test, { files: [['big.ts', big]] })).toBe(1);
  }, 180_000);

  it('passes the same run when per-file checking is turned off (control: the totals are fine)', () => {
    const test = `${useBig}${imports}it('one', () => expect(pick(1)).toBe('one'));\n`;
    const extra = ['--coverage.thresholds.perFile=false'];
    expect(runCoverage(unit, test, { files: [['big.ts', big]], extra })).toBe(0);
  }, 180_000);
});

describe('.yarnrc.yml and install scripts', () => {
  it('holds exactly the allowed settings, with install scripts off', () => {
    expect(yarnrcProblems(readText(root, '.yarnrc.yml'))).toEqual([]);
  });

  it('is the only .yarnrc.yml in the repo', () => {
    const yarnrcs = trackedFiles(root).filter(
      (path) => path === '.yarnrc.yml' || path.endsWith('/.yarnrc.yml'),
    );
    expect(yarnrcs).toEqual(['.yarnrc.yml']);
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
