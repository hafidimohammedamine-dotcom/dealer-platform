import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { ESLint } from 'eslint';
import { describe, expect, it } from 'vitest';
import {
  allowedPayloadMembers,
  bannedImports,
  overrideAccessAllowedPaths,
  payloadBanConfigs,
} from '../../../eslint.payload-ban.mjs';
import { findRepoRoot, listWorkspaces } from './repo.js';

const root = findRepoRoot();
const eslint = new ESLint({ cwd: root });

const ACCESS = 'local/no-payload-instance-access';
const OVERRIDE = 'local/no-override-access';
const IMPORTS = 'no-restricted-imports';

const ours = new Set([ACCESS, OVERRIDE, IMPORTS]);

/** Error rule ids of the bans only (warnings such as "inline config ignored" are not counted). */
async function errors(code: string, file: string): Promise<string[]> {
  const [result] = await eslint.lintText(code, { filePath: join(root, file) });
  return (result?.messages ?? [])
    .filter((message) => message.severity === 2)
    .map((message) => message.ruleId ?? 'parse-error')
    .filter((id) => id === 'parse-error' || ours.has(id));
}

const outside = 'services/intake/src/example.ts';
const inside = 'packages/data/src/example.ts';

// Each snippet is a bypass that must be flagged outside packages/data, once per use.
const bypasses: Record<string, string> = {
  'payload.find': 'payload.find({});',
  'req.payload.create': 'req.payload.create({});',
  'nested ctx.req.payload.delete': 'ctx.req.payload.delete({});',
  'computed payload["update"]': "payload['update']({});",
  'computed req["payload"].count': "req['payload'].count({});",
  'template literal payload[`find`]': 'payload[`find`]({});',
  'dynamic key payload[name]': 'payload[name]({});',
  'optional payload?.find': 'payload?.find({});',
  'optional req.payload?.create': 'req.payload?.create({});',
  'non-null payload!.find': 'payload!.find({});',
  'cast (payload as Payload).find': '(payload as Payload).find({});',
  'await getPayload() call': 'const p = await getPayload({}); void p;',
  '(await getPayload()).find': '(await getPayload({})).find({});',
  'getPayload().find': 'getPayload({}).find({});',
  'payload.find.call': 'payload.find.call(payload, {});',
  'payload.find.apply': 'payload.find.apply(payload, [{}]);',
  'destructure from payload': 'const { find } = payload; void find;',
  'destructure from req.payload': 'const { find } = req.payload; void find;',
  'alias const p = req.payload': 'const p = req.payload; p.find({});',
  'alias of getPayload': 'const p = await getPayload({}); p.find({});',
  'typed parameter': 'function f(p: Payload) { p.find({}); }',
  'typed BasePayload parameter': 'function f(p: BasePayload) { return p.create({}); }',
  'typed qualified parameter': 'function f(p: Types.Payload) { return p.create({}); }',
  'payload passed to a function': 'helper(payload);',
  'payload.db.find (adapter)': 'payload.db.find({});',
  'req.payload.db.drizzle.execute': 'req.payload.db.drizzle.execute(sql);',
  'payload.db.drizzle': 'const d = payload.db.drizzle; void d;',
  'payload.forgotPassword': 'payload.forgotPassword({});',
  'payload.resetPassword': 'payload.resetPassword({});',
  'payload.login': 'payload.login({});',
  'payload.unlock': 'payload.unlock({});',
  'payload.verifyEmail': 'payload.verifyEmail({});',
  'payload.auth': 'payload.auth({});',
  'payload.jobs.queue': 'payload.jobs.queue({});',
  'payload.sendEmail': 'payload.sendEmail({});',
  'import getPayload': "import { getPayload } from 'payload'; void getPayload;",
  'renamed import of getPayload': "import { getPayload as gp } from 'payload'; void gp;",
};

describe('Payload rule 1: no Payload instance outside packages/data', () => {
  it.each(Object.entries(bypasses))('flags %s', async (_name, code) => {
    const found = await errors(`${code}\n`, outside);
    expect(found).toContain(ACCESS);
    expect(found.every((id) => id === ACCESS)).toBe(true);
  });

  it.each(Object.entries(bypasses))('allows %s inside packages/data', async (_name, code) => {
    const found = await errors(`${code}\n`, inside);
    expect(found).not.toContain(ACCESS);
  });

  it('fails closed: a method that is not on any list is flagged', async () => {
    expect(await errors('payload.someBrandNewMethod({});\n', outside)).toEqual([ACCESS]);
    expect(await errors('req.payload.someBrandNewMethod({});\n', outside)).toEqual([ACCESS]);
  });

  it('keeps the allow-list short', () => {
    expect(allowedPayloadMembers).toEqual(['logger']);
  });

  it.each(allowedPayloadMembers)('allows payload.%s', async (member) => {
    expect(
      await errors(`payload.${member}.info('x');\nreq.payload.${member}.info('x');\n`, outside),
    ).toEqual([]);
    expect(await errors(`payload['${member}'].info('x');\n`, outside)).toEqual([]);
  });

  it('does not flag unrelated code', async () => {
    const code = [
      'items.find(() => true);',
      'map.delete(1);',
      'const payload2 = { payload: 1 };',
      'const { payload } = req; void payload2;',
      'function f(payload: string) { return typeof payload; }',
      'let q; q = 1;',
      '',
    ].join('\n');
    // `payload` as a declared name is only flagged when it is used.
    const found = await errors(code, outside);
    expect(found).toEqual([ACCESS]); // the `typeof payload` use only
  });

  it('does not flag plain declarations and assignment targets named payload', async () => {
    expect(await errors('let payload; payload = 1;\n', outside)).toEqual([]);
    expect(await errors('const { payload } = req;\n', outside)).toEqual([]);
  });

  it('does not flag an untyped parameter that is not named payload', async () => {
    expect(await errors('function f(p: string) { return p.length; }\n', outside)).toEqual([]);
    expect(await errors('function f(p: Other) { return p.find(); }\n', outside)).toEqual([]);
  });

  it('keeps packages/data as the only exemption', async () => {
    const code = 'payload.find({});\n';
    for (const file of [
      'services/intake/src/x.ts',
      'services/desking/src/x.ts',
      'apps/admin/src/x.ts',
      'apps/admin/src/views/board.tsx',
      'apps/admin/payload.config.ts',
      'packages/platform/src/x.ts',
      'packages/ui/src/x.ts',
      'packages/contracts/src/x.ts',
      'tests/e2e/leak.spec.ts',
      'infra/checks/src/x.ts',
      'packages/database/src/x.ts',
      'packages/data-extra/src/x.ts',
    ]) {
      expect(await errors(code, file), file).toEqual([ACCESS]);
    }
    expect(await errors(code, 'packages/data/src/x.ts')).toEqual([]);
    expect(await errors(code, 'packages/data/src/deep/dir/x.ts')).toEqual([]);
  });

  it('flags a probe in every workspace, as .ts and .tsx, and in admin views', async () => {
    const files = listWorkspaces(root).filter((workspace) => workspace !== 'packages/data');
    expect(files.length).toBeGreaterThan(10);
    for (const workspace of files) {
      for (const ext of ['ts', 'tsx']) {
        const file = `${workspace}/src/probe.${ext}`;
        expect(await errors('payload.find({});\n', file), file).toEqual([ACCESS]);
      }
    }
    expect(await errors('payload.find({});\n', 'apps/admin/src/views/crm/board.tsx')).toEqual([
      ACCESS,
    ]);
    expect(
      await errors(
        'export const V = () => <div>{String(req.payload.find({}))}</div>;\n',
        'apps/admin/src/views/v.tsx',
      ),
    ).toEqual([ACCESS]);
  });
});

describe('database drivers and Payload adapters', () => {
  it.each(bannedImports)('bans import of %s outside packages/data', async (name) => {
    expect(await errors(`import x from '${name}';\nvoid x;\n`, outside)).toEqual([IMPORTS]);
    expect(await errors(`import { y } from '${name}/sub';\nvoid y;\n`, outside)).toEqual([IMPORTS]);
    expect(await errors(`import type { T } from '${name}';\n`, outside)).toEqual([IMPORTS]);
  });

  it.each(bannedImports)('bans dynamic import and require of %s', async (name) => {
    expect(await errors(`await import('${name}');\n`, outside)).toEqual([ACCESS]);
    expect(await errors(`require('${name}');\n`, outside)).toEqual([ACCESS]);
    expect(await errors(`require(\`${name}\`);\n`, outside)).toEqual([ACCESS]);
  });

  it('allows them inside packages/data', async () => {
    for (const name of bannedImports) {
      expect(
        await errors(`import x from '${name}';\nvoid x;\nawait import('${name}');\n`, inside),
      ).toEqual([]);
    }
  });

  it('does not flag similar names or harmless dynamic loads', async () => {
    expect(await errors("import x from 'pg-boss';\nvoid x;\n", outside)).toEqual([]);
    expect(
      await errors(
        "await import('node:fs');\nrequire('node:path');\nrequire(name);\nrequire();\n",
        outside,
      ),
    ).toEqual([]);
  });
});

describe('overrideAccess must be literal false, everywhere', () => {
  const files = [outside, inside, 'apps/admin/src/x.ts', 'tests/e2e/x.ts'];

  it('starts with an empty system-job allow-list', () => {
    expect(overrideAccessAllowedPaths).toEqual([]);
  });

  it.each(files)('flags true, shorthand and computed values in %s', async (file) => {
    expect(await errors('f({ overrideAccess: true });\n', file)).toEqual([OVERRIDE]);
    expect(await errors("f({ 'overrideAccess': true });\n", file)).toEqual([OVERRIDE]);
    expect(await errors("f({ ['overrideAccess']: true });\n", file)).toEqual([OVERRIDE]);
    expect(await errors('f({ overrideAccess: flag });\n', file)).toEqual([OVERRIDE]);
    expect(await errors('const overrideAccess = false;\nf({ overrideAccess });\n', file)).toEqual([
      OVERRIDE,
    ]);
    expect(await errors('f({ overrideAccess: !user });\n', file)).toEqual([OVERRIDE]);
    expect(await errors('f({ overrideAccess: 0 });\n', file)).toEqual([OVERRIDE]);
  });

  it.each(files)('allows the literal false in %s', async (file) => {
    expect(await errors('f({ overrideAccess: false });\n', file)).toEqual([]);
  });

  it('ignores destructuring and unrelated keys', async () => {
    expect(await errors('const { overrideAccess: o } = opts; void o;\n', outside)).toEqual([]);
    expect(await errors('f({ other: true, [key]: true });\n', outside)).toEqual([]);
  });

  it('lets a reviewed path opt out, and only that path', async () => {
    const withPath = payloadBanConfigs({ overrideAccessAllowed: ['services/jobs/**'] });
    expect(withPath.at(-1)).toEqual({
      files: ['services/jobs/**'],
      rules: { [OVERRIDE]: 'off' },
    });
    expect(payloadBanConfigs()).toHaveLength(2);
  });
});

describe('the bans cannot be switched off from inside the repo', () => {
  it('ignores inline disable comments and reports them', async () => {
    const code =
      '// eslint-disable-next-line local/no-payload-instance-access\npayload.find({});\n';
    expect(await errors(code, outside)).toEqual([ACCESS]);
    const block = '/* eslint-disable */\npayload.find({});\nf({ overrideAccess: true });\n';
    expect(await errors(block, outside)).toEqual([ACCESS, OVERRIDE]);
    const [result] = await eslint.lintText(code, { filePath: join(root, outside) });
    expect(result?.messages.some((message) => message.ruleId === null)).toBe(true);
  });

  it('ignores inline config comments that change the rules', async () => {
    const code = '/* eslint local/no-payload-instance-access: off */\npayload.find({});\n';
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
          /^(eslint\.config\.[cm]?[jt]s|\.eslintrc(\..+)?)$/.test(entry.name) &&
          dir !== ''
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
      const rules = config?.rules ?? {};
      expect(config?.linterOptions?.noInlineConfig, workspace).toBe(true);
      expect(rules[OVERRIDE]?.[0] ?? rules[OVERRIDE], workspace).toBeOneOf([2, 'error']);
      expect(rules[IMPORTS] !== undefined, workspace).toBe(workspace !== 'packages/data');
    }
  });
});
