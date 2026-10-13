import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ESLint } from 'eslint';
import { afterAll, describe, expect, it } from 'vitest';
import { trackedFileProblems } from './checks.js';
import { trackedFiles } from './repo.js';
import { root } from './test-helpers/root.js';

const rootConfig = join(root, 'eslint.config.mjs');
const eslint = new ESLint({ cwd: root, overrideConfigFile: rootConfig });

/** Rule ids ESLint reports for `code`, linted as if it were the repo file `file`. */
async function ruleIds(code: string, file: string): Promise<(string | null)[]> {
  const [result] = await eslint.lintText(code, { filePath: join(root, file) });
  return (result?.messages ?? []).map((message) => message.ruleId);
}

describe('lint ignores', () => {
  it('ignore install, cache and build output folders', async () => {
    for (const file of [
      'apps/admin/dist/index.js',
      'services/intake/dist/deep/x.js',
      'packages/data/coverage/x.js',
      'tests/e2e/dist/x.js',
      'tests/e2e/coverage/x.js',
      'tests/e2e/playwright-report/data/x.js',
      'tests/e2e/test-results/x.js',
      'tests/e2e/blob-report/x.js',
      'test-results/x.js',
      'playwright-report/data/x.js',
      'services/ai/blob-report/x.js',
      'apps/admin/src/playwright-report/y.js',
      'node_modules/x/index.js',
      'services/ai/src/node_modules/x/index.js',
      '.nx/cache/x.js',
      '.yarn/releases/x.cjs',
    ]) {
      expect(await eslint.isPathIgnored(join(root, file)), file).toBe(true);
    }
  });

  it('lint a source file in a folder called dist, coverage, .nx or .yarn below the top level', async () => {
    for (const file of [
      'apps/admin/src/x/dist/y.ts',
      'services/intake/src/coverage/y.ts',
      'tests/e2e/src/dist/y.ts',
      'packages/data/src/.nx/y.ts',
      'services/ai/.yarn/y.js',
    ]) {
      expect(await eslint.isPathIgnored(join(root, file)), file).toBe(false);
    }
  });

  it('skip no committed source file', async () => {
    const sources = trackedFiles(root).filter((path) => /\.[cm]?[jt]sx?$/.test(path));
    expect(sources.length).toBeGreaterThan(30);
    for (const file of sources) {
      expect(await eslint.isPathIgnored(join(root, file)), file).toBe(false);
    }
  });
});

describe('committed files', () => {
  it('include nothing in a folder lint skips, and no ESLint config but the root one', () => {
    expect(trackedFileProblems(trackedFiles(root))).toEqual([]);
  });
});

describe('lint rules', () => {
  it('cannot be switched off by a comment in the file', async () => {
    const ids = await ruleIds('/* eslint-disable */\ndebugger;\n', 'services/ai/src/x.ts');
    expect(ids).toContain('no-debugger');
  });

  it('ban type casts in TypeScript files', async () => {
    const ids = await ruleIds(
      'declare const y: unknown;\nexport const x = y as string;\n',
      'packages/ui/src/x.ts',
    );
    expect(ids).toContain('@typescript-eslint/consistent-type-assertions');
  });
});

// `yarn lint` runs `eslint --config eslint.config.mjs .` (checked in config.test.ts). These runs show what `--config`
// buys: a nested config file that switches a rule off is used without it and ignored with it.
describe('eslint --config', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lint-config-'));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'src', 'dist'), { recursive: true });
  writeFileSync(
    join(dir, 'src', 'dist', 'eslint.config.mjs'),
    "export default [{ rules: { 'no-debugger': 'off' } }];\n",
  );
  writeFileSync(join(dir, 'src', 'dist', 'x.js'), 'debugger;\n');
  const eslintBin = join(root, 'node_modules', 'eslint', 'bin', 'eslint.js');
  const run = (args: string[]): number | null =>
    spawnSync(process.execPath, [eslintBin, ...args, 'src/dist/x.js'], {
      cwd: dir,
      encoding: 'utf8',
      timeout: 60_000,
    }).status;

  it('uses a nested config when no --config is given (control)', () => {
    expect(run([])).toBe(0);
  }, 90_000);

  it('ignores the nested config with --config, so the rule still fails the run', () => {
    expect(run(['--config', rootConfig])).toBe(1);
  }, 90_000);
});
