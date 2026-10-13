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

describe('Payload rule 1: data access only through packages/data', () => {
  const where = 'apps/admin/src/x.ts';
  const banned = [
    'declare const payload: { find(a: object): void };\npayload.find({ collection: "leads" });\n',
    'declare const req: { payload: { update(a: object): void } };\nreq.payload.update({});\n',
    'declare const payload: { delete(a: object): void };\npayload.delete({});\n',
    'declare const payload: { db: object };\nexport const d = payload.db;\n',
    'export const a = { collection: "leads", overrideAccess: true };\n',
    'export const a = { "overrideAccess": true };\n',
    'import { getPayload } from "payload";\nexport const g = getPayload;\n',
    // Bypasses of a name-based check (security review round 3, finding 6).
    'declare const req: { payload: object };\nexport const p = req.payload;\n',
    'declare const req: { payload: object };\nlet p: object;\np = req.payload;\nexport { p };\n',
    'declare const req: { payload: object };\nexport const { payload } = req;\n',
    'export const f = ({ req: { payload } }: { req: { payload: unknown } }) => payload;\n',
    'declare const x: { db: object };\nexport const { db } = x;\n',
    'declare const p: { find(a: object): void };\np.find({ collection: "leads" });\n',
    'declare function find(a: object): void;\nfind({ collection: "leads" });\n',
    'declare const p: { findGlobal(a: object): void };\np.findGlobal({ slug: "settings" });\n',
    'declare const x: boolean;\nexport const a = { overrideAccess: x };\n',
    'declare const overrideAccess: boolean;\nexport const a = { overrideAccess };\n',
    'export const a = { overrideAccess: !0 };\n',
    'export const a = { ["overrideAccess"]: true };\n',
    'import * as payload from "payload";\nexport const p = payload;\n',
    'import payload from "payload";\nexport const p = payload;\n',
    'export const p = import("payload");\n',
    'declare const name: string;\nexport const p = import(name);\n',
    'export const p = require("payload");\n',
  ];

  it('refuses a Local API call, raw database access, overrideAccess: true and getPayload', async () => {
    for (const code of banned) {
      for (const file of [
        where,
        'services/ai/src/x.ts',
        'apps/admin/src/x.mjs',
        'tests/e2e/x.cjs',
      ]) {
        // The JavaScript files get the same code without its TypeScript-only lines and annotations.
        const source = file.endsWith('ts')
          ? code
          : code
              .split('\n')
              .filter((line) => !line.startsWith('declare'))
              .join('\n')
              .replace(/: \{ req: \{ payload: unknown \} \}/, '')
              .replace(/let p: object;/, 'let p;');
        if (/^\s*$/.test(source)) continue;
        const ids = await ruleIds(source, file);
        expect(
          ids.some((id) => id === 'no-restricted-syntax' || id === 'no-restricted-imports'),
          `${file}: ${source}`,
        ).toBe(true);
      }
    }
  });

  it('keeps every other check in the reviewed exceptions', async () => {
    const overrideTrue = 'export const a = { overrideAccess: true };\n';
    for (const file of [
      'packages/data/src/x.ts',
      'apps/admin/migrations/x.ts',
      'apps/admin/src/tenants/sessions.ts',
    ]) {
      expect(await ruleIds(overrideTrue, file), file).toContain('no-restricted-syntax');
    }
    // Each exception lifts exactly one check.
    const call = 'declare const p: { find(a: object): void };\np.find({ collection: "leads" });\n';
    expect(await ruleIds(call, 'packages/data/src/x.ts')).not.toContain('no-restricted-syntax');
    expect(await ruleIds(call, 'apps/admin/migrations/x.ts')).toContain('no-restricted-syntax');
    const migration = 'export async function up({ db }: { db: object }) {\n  return db;\n}\n';
    expect(await ruleIds(migration, 'apps/admin/migrations/x.ts')).not.toContain(
      'no-restricted-syntax',
    );
    expect(await ruleIds(migration, 'packages/data/src/x.ts')).toContain('no-restricted-syntax');
    const db =
      'declare const req: { payload: { db: object } };\nexport const run = () => req.payload.db;\n';
    expect(await ruleIds(db, 'apps/admin/src/tenants/sessions.ts')).not.toContain(
      'no-restricted-syntax',
    );
    expect(await ruleIds(db, 'apps/admin/src/tenants/users.ts')).toContain('no-restricted-syntax');
  });

  it('allows overrideAccess: false and other uses of the same names', async () => {
    for (const code of [
      'export const a = { overrideAccess: false };\n',
      'declare const list: { find(a: number): void };\nlist.find(1);\n',
      'import { Forbidden } from "payload";\nexport const f = Forbidden;\n',
      'declare const rows: number[];\nexport const r = rows.find((n) => n > 1);\n',
      'declare const m: Map<string, number>;\nm.delete("a");\n',
      'export const m = import("./local.js");\n',
    ]) {
      const ids = await ruleIds(code, where);
      expect(ids, code).not.toContain('no-restricted-syntax');
      expect(ids, code).not.toContain('no-restricted-imports');
    }
  });

  it('is not switched off by a comment', async () => {
    const ids = await ruleIds(
      '/* eslint-disable no-restricted-syntax */\nexport const a = { overrideAccess: true };\n',
      where,
    );
    expect(ids).toContain('no-restricted-syntax');
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
