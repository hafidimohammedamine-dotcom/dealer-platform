import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import {
  dbClientAllowedPaths,
  payloadBanConfigs,
  payloadDbAllowedPaths,
  spawnAllowedPaths,
} from '../../../eslint.payload-ban.mjs';
import { findFiles, listWorkspaces } from './repo.js';
import {
  ACCESS,
  CASTS,
  MODULES,
  OVERRIDE,
  allErrors,
  errors,
  eslint,
  flatConfigOf,
  outside,
  root,
} from './test-helpers/lint.js';

/** Severity of a rule entry: `'error'`, `2` or `['error', {...}]`. */
const severity = (entry: unknown): unknown => (Array.isArray(entry) ? entry[0] : entry);
/** Options object of a rule entry, or `{}`. */
const options = (entry: unknown): unknown => (Array.isArray(entry) ? (entry[1] ?? {}) : {});

describe('the bans cannot be switched off from inside the repo', () => {
  it('ignores inline disable comments and reports them', async () => {
    const code = `// eslint-disable-next-line ${ACCESS}\nvoid req.payload;\n`;
    expect(await errors(code, outside)).toEqual([ACCESS]);
    const block = '/* eslint-disable */\nvoid req.payload;\nf({ overrideAccess: true });\n';
    expect(await errors(block, outside)).toEqual([ACCESS, OVERRIDE]);
    const [result] = await eslint.lintText(code, { filePath: join(root, outside) });
    expect(result?.messages.some((message) => message.ruleId === null)).toBe(true);
  });

  it('ignores inline config comments that change the rules', async () => {
    const code = `/* eslint ${ACCESS}: off */\nvoid req.payload;\n`;
    expect(await errors(code, outside)).toEqual([ACCESS]);
  });

  it('has no eslint config outside the repo root', () => {
    const configs = findFiles(root, (name) =>
      /^(eslint\.config\.[cm]?[jt]s|\.eslintrc(\..+)?)$/.test(name),
    );
    expect(configs).toEqual(['eslint.config.mjs']);
  });

  it.each(['js', 'jsx'])('runs the bans on .%s files', async (ext) => {
    expect(await errors('void req.payload;\n', `x.${ext}`)).toEqual([ACCESS]);
    expect(await errors('void req.payload;\n', `services/intake/src/x.${ext}`)).toEqual([ACCESS]);
  });

  it('lints every source extension', async () => {
    for (const ext of ['js', 'jsx', 'mjs', 'cjs', 'ts', 'tsx', 'mts', 'cts']) {
      expect(await eslint.isPathIgnored(join(root, `services/intake/src/x.${ext}`)), ext).toBe(
        false,
      );
      const config = await eslint.calculateConfigForFile(
        join(root, `services/intake/src/x.${ext}`),
      );
      expect(severity(config?.rules?.['local/no-payload-instance-access']), ext).toBeOneOf([
        2,
        'error',
      ]);
    }
  });

  it('turns every ban on with error severity for every workspace', async () => {
    for (const workspace of listWorkspaces(root)) {
      const config = await eslint.calculateConfigForFile(join(root, workspace, 'src/x.ts'));
      const {
        'local/no-override-access': override,
        'local/no-restricted-modules': modules,
        'local/no-payload-instance-access': access,
        '@typescript-eslint/consistent-type-assertions': casts,
        'no-eval': noEval,
        'no-implied-eval': noImpliedEval,
        'no-new-func': noNewFunc,
        'no-with': noWith,
      } = config?.rules ?? {};
      const isData = workspace === 'packages/data';
      expect(config?.linterOptions?.noInlineConfig, workspace).toBe(true);
      expect(severity(override), workspace).toBeOneOf([2, 'error']);
      expect(severity(modules), workspace).toBeOneOf([2, 'error']);
      expect(severity(access), workspace).toBeOneOf(isData ? [0, 'off'] : [2, 'error']);
      expect(severity(casts), workspace).toBeOneOf([2, 'error']);
      for (const rule of [noEval, noImpliedEval, noNewFunc, noWith]) {
        expect(severity(rule), workspace).toBeOneOf([2, 'error']);
      }
      if (!isData) {
        expect(options(access), workspace).toEqual({});
        expect(options(modules), workspace).toEqual({});
      }
    }
  });
});

describe('the tests lint with the same config as `yarn lint`', () => {
  it('reports the same problems as eslint.config.mjs loaded from disk', async () => {
    const samples: [string, string][] = [
      ['void req.payload;\nf({ overrideAccess: true });\n', outside],
      ['void req.payload;\n', 'x.jsx'],
      [
        'const { find } = payload; void payload.db; Reflect.ownKeys(x);\n',
        'packages/data/src/x.ts',
      ],
      [
        'payload.db.drizzle.execute(sql);\nconst { find } = payload;\n',
        'packages/data/src/tenant-transaction.ts',
      ],
      ["import pg from 'pg';\nexport const x = y as Foo;\n", 'services/desking/src/db/x.ts'],
    ];
    // ESLint loads eslint.config.mjs itself, in its own process, exactly as `yarn lint` does.
    const script = [
      "import { ESLint } from 'eslint';",
      'const eslint = new ESLint({ cwd: process.argv[1] });',
      'const out = [];',
      'for (const [code, file] of JSON.parse(process.argv[2])) {',
      "  const [r] = await eslint.lintText(code, { filePath: process.argv[1] + '/' + file });",
      "  out.push(r.messages.map((m) => m.line + ':' + (m.ruleId ?? '')));",
      '}',
      'console.log(JSON.stringify(out));',
    ].join('\n');
    const run = spawnSync(
      process.execPath,
      ['--input-type=module', '-e', script, root, JSON.stringify(samples)],
      { cwd: root, encoding: 'utf8' },
    );
    expect(run.status, run.stderr).toBe(0);
    const fromDisk: unknown = JSON.parse(run.stdout);
    const inProcess: string[][] = [];
    for (const [code, file] of samples) {
      const [result] = await eslint.lintText(code, { filePath: join(root, file) });
      const messages = result?.messages ?? [];
      expect(messages.length, file).toBeGreaterThan(0);
      inProcess.push(messages.map((message) => `${message.line}:${message.ruleId ?? ''}`));
    }
    expect(inProcess).toEqual(fromDisk);
  }, 60_000);

  it('rejects an eslint.config.mjs that does not export a flat config array', () => {
    expect(flatConfigOf({ default: [{ rules: {} }] })).toEqual([{ rules: {} }]);
    for (const module of [undefined, {}, { default: { rules: {} } }, { default: [1] }]) {
      expect(() => flatConfigOf(module)).toThrow('must export a flat config array');
    }
  });
});

describe('allow-lists apply only to their own paths', () => {
  const blockFor = (glob: string, configs: ReturnType<typeof payloadBanConfigs>) =>
    configs.filter((config) => config.files?.includes(glob));
  const none = { overrideAccessAllowed: [] };

  it('builds one block per non-empty list', () => {
    expect(payloadBanConfigs({ ...none })).toHaveLength(3);
    expect(payloadBanConfigs({ ...none, spawnAllowed: [] })).toHaveLength(2);
    const configs = payloadBanConfigs({
      overrideAccessAllowed: ['services/jobs/**'],
      payloadNameAllowed: ['services/messaging/src/telnyx/body.ts'],
      dbClientAllowed: ['services/desking/src/db/**'],
      payloadDbAllowed: ['packages/data/src/tenant-transaction.ts'],
      spawnAllowed: ['infra/checks/src/x.test.ts'],
    });
    expect(configs).toHaveLength(7);
    expect(blockFor('packages/data/src/tenant-transaction.ts', configs)[0]?.rules).toEqual({
      [OVERRIDE]: ['error', { requireOptions: true, allowDb: true }],
    });
    expect(blockFor('services/jobs/**', configs)[0]?.rules).toEqual({ [OVERRIDE]: 'off' });
    expect(blockFor('services/messaging/src/telnyx/body.ts', configs)[0]?.rules).toEqual({
      [ACCESS]: ['error', { allowNames: true }],
    });
    expect(blockFor('services/desking/src/db/**', configs)[0]?.rules).toEqual({
      [MODULES]: ['error', { allowDbClients: true }],
    });
    expect(blockFor('infra/checks/src/x.test.ts', configs)[0]?.rules).toEqual({
      [MODULES]: ['error', { allowSpawn: true }],
    });
  });

  it('keeps packages/data as the only full exemption, with the call-shape check on', () => {
    const [data] = blockFor('packages/data/**', payloadBanConfigs());
    expect(data?.rules).toEqual({
      [ACCESS]: 'off',
      [MODULES]: ['error', { allowPayload: true, allowDbClients: true }],
      [OVERRIDE]: ['error', { requireOptions: true }],
    });
  });

  it('allows payload.db and database clients nowhere until a reviewed file is added', () => {
    expect(payloadDbAllowedPaths).toEqual([]);
    expect(dbClientAllowedPaths).toEqual([]);
  });

  it('lets only two exact test files start processes', () => {
    expect(spawnAllowedPaths).toEqual([
      'infra/checks/src/config.test.ts',
      'infra/checks/src/payload-ban-config.test.ts',
    ]);
    for (const file of spawnAllowedPaths) expect(existsSync(join(root, file)), file).toBe(true);
  });
});

describe('no unchecked type assertions', () => {
  it.each(['ts', 'tsx'])('reports `as` casts in .%s files', async (ext) => {
    const file = `services/intake/src/x.${ext}`;
    expect(
      await allErrors('declare const y: unknown;\nexport const x = y as Foo;\n', file),
    ).toEqual([CASTS]);
  });

  it('reports angle-bracket casts in .ts files', async () => {
    expect(
      await allErrors('declare const y: unknown;\nexport const x = <Foo>y;\n', outside),
    ).toEqual([CASTS]);
  });
});
