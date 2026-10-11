import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { readOverrideAllowlist } from '../../../eslint-rules/override-allowlist.mjs';
import { findFiles, hasScripts, isRecord, readJson } from './repo.js';
import { ACCESS, MODULES, OVERRIDE, errors, eslint, outside, root } from './test-helpers/lint.js';

const sourceFile = /\.(?:js|jsx|mjs|cjs|ts|tsx|mts|cts)$/;
const skipped: ReadonlySet<string> = new Set([
  'node_modules',
  '.git',
  '.yarn',
  '.nx',
  '.worktrees',
]);
const buildOutput = /^(?:apps|services|packages|infra)\/[^/]+\/(?:dist|coverage)\//;

/** Repo-relative paths of every source file in the checkout, build output folders included. */
const sourceFiles = (): string[] => findFiles(root, (name) => sourceFile.test(name), skipped);

describe('lint ignores cover build output only', () => {
  it('ignores the build output folder of a workspace', async () => {
    for (const file of [
      'apps/admin/dist/index.js',
      'services/intake/dist/deep/x.js',
      'packages/data/coverage/x.js',
      'infra/checks/coverage/x.js',
      '.nx/cache/x.js',
      '.yarn/releases/x.cjs',
      'node_modules/x/index.js',
    ]) {
      expect(await eslint.isPathIgnored(join(root, file)), file).toBe(true);
    }
  });

  it('lints source files that sit in a folder called dist, coverage or .nx deeper in a workspace', async () => {
    for (const file of [
      'apps/admin/src/x/dist/y.ts',
      'apps/admin/src/coverage/y.ts',
      'services/intake/src/dist/y.ts',
      'packages/data/src/dist/y.ts',
      'apps/admin/src/.nx/y.ts',
      'apps/admin/src/.yarn/y.ts',
      'tests/e2e/dist/y.ts',
      'dist/y.ts',
    ]) {
      expect(await eslint.isPathIgnored(join(root, file)), file).toBe(false);
    }
  });

  it('runs the Payload bans on a probe in a nested dist folder', async () => {
    const file = 'apps/admin/src/x/dist/y.ts';
    expect(await errors('void req.payload;\n', file)).toEqual([ACCESS]);
  });

  it('has no source file in the checkout outside a build output folder that lint ignores', async () => {
    const files = sourceFiles();
    expect(files.length).toBeGreaterThan(50);
    for (const file of files) {
      if (buildOutput.test(file)) continue;
      expect(await eslint.isPathIgnored(join(root, file)), file).toBe(false);
    }
  });
});

describe('the lint wiring is exactly what the reviews approved', () => {
  it('has the root lint script `eslint . && prettier --check .`', () => {
    const { scripts } = readJson(root, 'package.json', hasScripts);
    expect(scripts['lint']).toBe('eslint . && prettier --check .');
  });

  it('turns inline config comments off', async () => {
    const config = await eslint.calculateConfigForFile(join(root, outside));
    expect(config?.linterOptions?.noInlineConfig).toBe(true);
  });

  it('has the three Payload rules on as errors in every source file, relaxed only where reviewed', async () => {
    const allowed = new Set(readOverrideAllowlist());
    for (const file of sourceFiles()) {
      if (buildOutput.test(file)) continue;
      const rules = (await eslint.calculateConfigForFile(join(root, file)))?.rules ?? {};
      const inData = file.startsWith('packages/data/');
      expect(rules['local/no-payload-instance-access']?.[0], `${ACCESS} ${file}`).toBe(
        inData ? 0 : 2,
      );
      expect(rules['local/no-restricted-modules']?.[0], `${MODULES} ${file}`).toBe(2);
      expect(rules['local/no-override-access']?.[0], `${OVERRIDE} ${file}`).toBe(2);
      const options = rules['local/no-override-access']?.[1];
      const relaxed = isRecord(options) && options['allowOverrideTrue'] === true;
      expect(relaxed, `allowOverrideTrue ${file}`).toBe(allowed.has(file));
    }
  });
});
