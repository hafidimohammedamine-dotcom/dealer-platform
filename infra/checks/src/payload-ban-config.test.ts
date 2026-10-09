import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { payloadBanConfigs } from '../../../eslint.payload-ban.mjs';
import { listWorkspaces } from './repo.js';
import {
  ACCESS,
  CASTS,
  MODULES,
  OVERRIDE,
  allErrors,
  errors,
  eslint,
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
    const skip = new Set([
      'node_modules',
      '.git',
      '.yarn',
      '.nx',
      'dist',
      'coverage',
      '.worktrees',
    ]);
    const found: string[] = [];
    const walk = (dir: string): void => {
      for (const entry of readdirSync(join(root, dir), { withFileTypes: true })) {
        const relative = dir === '' ? entry.name : `${dir}/${entry.name}`;
        if (entry.isDirectory()) {
          if (!skip.has(entry.name)) walk(relative);
        } else if (
          dir !== '' &&
          /^(eslint\.config\.[cm]?[jt]s|\.eslintrc(\..+)?)$/.test(entry.name)
        ) {
          found.push(relative);
        }
      }
    };
    walk('');
    expect(found).toEqual([]);
    expect(existsSync(join(root, 'eslint.config.mjs'))).toBe(true);
  });

  it('turns every ban on with error severity for every workspace', async () => {
    for (const workspace of listWorkspaces(root)) {
      const config = await eslint.calculateConfigForFile(join(root, workspace, 'src/x.ts'));
      const rules: Record<string, unknown> = config?.rules ?? {};
      const isData = workspace === 'packages/data';
      expect(config?.linterOptions?.noInlineConfig, workspace).toBe(true);
      expect(severity(rules[OVERRIDE]), workspace).toBeOneOf([2, 'error']);
      expect(severity(rules[MODULES]), workspace).toBeOneOf([2, 'error']);
      expect(severity(rules[ACCESS]), workspace).toBeOneOf(isData ? [0, 'off'] : [2, 'error']);
      expect(severity(rules[CASTS]), workspace).toBeOneOf([2, 'error']);
      for (const rule of ['no-eval', 'no-implied-eval', 'no-new-func', 'no-with']) {
        expect(severity(rules[rule]), `${workspace} ${rule}`).toBeOneOf([2, 'error']);
      }
      if (!isData) {
        expect(options(rules[ACCESS]), workspace).toEqual({});
        expect(options(rules[MODULES]), workspace).toEqual({});
      }
    }
  });
});

describe('allow-lists apply only to their own paths', () => {
  const blockFor = (glob: string, configs: ReturnType<typeof payloadBanConfigs>) =>
    configs.filter((config) => config.files?.includes(glob));

  it('builds one block per non-empty list', () => {
    expect(payloadBanConfigs({ dbClientAllowed: [] })).toHaveLength(2);
    const configs = payloadBanConfigs({
      overrideAccessAllowed: ['services/jobs/**'],
      payloadNameAllowed: ['services/messaging/src/telnyx/body.ts'],
      dbClientAllowed: ['services/desking/src/db/**'],
    });
    expect(configs).toHaveLength(5);
    expect(blockFor('services/jobs/**', configs)[0]?.rules).toEqual({ [OVERRIDE]: 'off' });
    expect(blockFor('services/messaging/src/telnyx/body.ts', configs)[0]?.rules).toEqual({
      [ACCESS]: ['error', { allowNames: true }],
    });
    expect(blockFor('services/desking/src/db/**', configs)[0]?.rules).toEqual({
      [MODULES]: ['error', { allowDbClients: true }],
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
