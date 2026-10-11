import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import * as lists from '../../../eslint-rules/payload-lists.mjs';
import { payloadBanConfigs } from '../../../eslint.payload-ban.mjs';
import {
  overrideAllowlistFile,
  parseOverrideAllowlist,
  readOverrideAllowlist,
} from '../../../eslint-rules/override-allowlist.mjs';
import { OVERRIDE, errorsWith, eslintWith, inside, outside, root } from './test-helpers/lint.js';

const temps: string[] = [];
afterEach(() => {
  for (const dir of temps.splice(0)) rmSync(dir, { recursive: true, force: true });
});

/** A throw-away repo root holding the given files, and the path of an allow-list file in it. */
function fakeRepo(allowlist: string | undefined, files: string[]): { dir: string; file: string } {
  const dir = mkdtempSync(join(tmpdir(), 'allowlist-'));
  temps.push(dir);
  for (const path of files) {
    mkdirSync(join(dir, path, '..'), { recursive: true });
    writeFileSync(join(dir, path), 'export {};\n');
  }
  const file = join(dir, 'allowlist.txt');
  if (allowlist !== undefined) writeFileSync(file, allowlist);
  return { dir, file };
}

describe('the overrideAccess system-job allow-list is a founder-only file, not code', () => {
  it('reads packages/data/override-allowlist.txt', () => {
    expect(overrideAllowlistFile).toBe('packages/data/override-allowlist.txt');
  });

  it('has no allow-list array in the lint policy any more', () => {
    expect('overrideAccessAllowedPaths' in lists).toBe(false);
  });

  it('reads the real file (or an empty list when it does not exist yet) without errors', () => {
    const paths = readOverrideAllowlist();
    expect(Array.isArray(paths)).toBe(true);
    expect(payloadBanConfigs().length).toBeGreaterThan(1);
  });
});

describe('parseOverrideAllowlist', () => {
  it('skips blank lines and # comments, trims, and handles CRLF', () => {
    const text =
      '# header\r\n\r\n  services/jobs/src/nightly.ts  \n#services/x.ts\n\t\napps/admin/src/a_b-c@1.ts\n';
    expect(parseOverrideAllowlist(text)).toEqual({
      paths: ['services/jobs/src/nightly.ts', 'apps/admin/src/a_b-c@1.ts'],
      problems: [],
    });
  });

  it('is empty for empty text', () => {
    expect(parseOverrideAllowlist('')).toEqual({ paths: [], problems: [] });
  });

  it.each([
    'services/**/*.ts',
    'services/jobs/*',
    'services/jobs/src/{a,b}.ts',
    'services/jobs/src/[ab].ts',
    'services/jobs/src/a?.ts',
    '!services/jobs/src/a.ts',
    '/services/jobs/src/a.ts',
    '../services/jobs/src/a.ts',
    'services/../jobs/a.ts',
    './services/jobs/a.ts',
    'services//jobs/a.ts',
    'services/jobs/',
    'services\\jobs\\a.ts',
    'services/jobs/a.ts # why',
    'services/jobs/my file.ts',
    'C:/jobs/a.ts',
  ])('rejects the malformed line %s', (line) => {
    const { paths, problems } = parseOverrideAllowlist(`${line}\n`);
    expect(paths).toEqual([]);
    expect(problems).toHaveLength(1);
    expect(problems[0]).toContain('line 1');
  });

  it('numbers the lines of each problem', () => {
    const { problems } = parseOverrideAllowlist('# c\n\nok/a.ts\n*.ts\n');
    expect(problems).toEqual(['line 4: not an exact repo-relative file path (no globs): *.ts']);
  });
});

describe('readOverrideAllowlist', () => {
  it('returns the listed paths when each file exists', () => {
    const { dir, file } = fakeRepo('# jobs\nservices/jobs/src/nightly.ts\n', [
      'services/jobs/src/nightly.ts',
    ]);
    expect(readOverrideAllowlist({ root: dir, file })).toEqual(['services/jobs/src/nightly.ts']);
  });

  it('reads the list from <root>/packages/data/override-allowlist.txt by default', () => {
    const { dir } = fakeRepo(undefined, ['services/jobs/src/a.ts']);
    expect(readOverrideAllowlist({ root: dir })).toEqual([]);
    mkdirSync(join(dir, 'packages/data'), { recursive: true });
    writeFileSync(join(dir, 'packages/data/override-allowlist.txt'), 'services/jobs/src/a.ts\n');
    expect(readOverrideAllowlist({ root: dir })).toEqual(['services/jobs/src/a.ts']);
  });

  it('allows nothing when the list file is missing', () => {
    const { dir, file } = fakeRepo(undefined, []);
    expect(readOverrideAllowlist({ root: dir, file })).toEqual([]);
  });

  it('allows nothing when the list holds only comments', () => {
    const { dir, file } = fakeRepo('# nothing yet\n\n', []);
    expect(readOverrideAllowlist({ root: dir, file })).toEqual([]);
  });

  it('fails when a listed file does not exist', () => {
    const { dir, file } = fakeRepo('services/jobs/src/gone.ts\n', []);
    expect(() => readOverrideAllowlist({ root: dir, file })).toThrow(
      'listed file does not exist: services/jobs/src/gone.ts',
    );
  });

  it('fails when a listed path is a folder', () => {
    const { dir, file } = fakeRepo('services/jobs/src\n', ['services/jobs/src/a.ts']);
    expect(() => readOverrideAllowlist({ root: dir, file })).toThrow('does not exist');
  });

  it('fails on a malformed line, even when other lines are fine', () => {
    const { dir, file } = fakeRepo('services/jobs/src/a.ts\nservices/**\n', [
      'services/jobs/src/a.ts',
    ]);
    expect(() => readOverrideAllowlist({ root: dir, file })).toThrow(
      'not an exact repo-relative file path',
    );
  });

  it('fails when the list file cannot be read as a file', () => {
    const { dir } = fakeRepo(undefined, []);
    expect(() => readOverrideAllowlist({ root: dir, file: dir })).toThrow();
  });
});

describe('local/no-override-access follows the allow-list file', () => {
  const listedFile = 'services/intake/src/index.ts';

  it('lets a listed path use overrideAccess: true, and nothing else', async () => {
    const { file } = fakeRepo(`# system job\n${listedFile}\n`, []);
    // The listed file really exists in the repo, so the root is the repo root.
    const listed = eslintWith(payloadBanConfigs({ allowlist: { root, file } }));
    expect(await errorsWith(listed, 'f({ overrideAccess: true });\n', listedFile)).toEqual([]);
    expect(
      await errorsWith(listed, 'f({ overrideAccess: true });\n', 'services/ai/src/x.ts'),
    ).toEqual([OVERRIDE]);
    expect(
      await errorsWith(listed, 'f({ overrideAccess: true });\n', 'services/intake/src/other.ts'),
    ).toEqual([OVERRIDE]);
  });

  it('fails an unlisted path', async () => {
    const { file } = fakeRepo('# nothing yet\n', []);
    const none = eslintWith(payloadBanConfigs({ allowlist: { root, file } }));
    expect(await errorsWith(none, 'f({ overrideAccess: true });\n', outside)).toEqual([OVERRIDE]);
  });

  it('fails every path when the list file is missing', async () => {
    const { file } = fakeRepo(undefined, []);
    const none = eslintWith(payloadBanConfigs({ allowlist: { root, file } }));
    expect(await errorsWith(none, 'f({ overrideAccess: true });\n', outside)).toEqual([OVERRIDE]);
  });

  it('cannot build a config from a list with a path that does not exist', () => {
    const { file } = fakeRepo('services/intake/src/does-not-exist.ts\n', []);
    expect(() => payloadBanConfigs({ allowlist: { root, file } })).toThrow('does not exist');
  });

  it('cannot build a config from a list with a glob', () => {
    const { file } = fakeRepo('services/**/*.ts\n', []);
    expect(() => payloadBanConfigs({ allowlist: { root, file } })).toThrow('no globs');
  });
});

describe('a system-job file may use overrideAccess: true, and nothing else is relaxed', () => {
  const job = 'packages/data/src/system-job.ts';
  const listed = eslintWith(payloadBanConfigs({ overrideAccessAllowed: [job] }));
  const messages = async (code: string, file = job): Promise<string[]> => {
    const [result] = await listed.lintText(code, { filePath: join(root, file) });
    return (result?.messages ?? [])
      .filter((message) => message.ruleId === OVERRIDE)
      .map((message) => message.messageId ?? '');
  };
  const call = (options: string): string => `payload.find({ ${options} });\n`;

  it('turns the rule on in strict mode for the listed file, with only the two skips', () => {
    const configs = payloadBanConfigs({ overrideAccessAllowed: [job] });
    const block = configs.find((config) => config.files?.includes(job));
    expect(block?.rules).toEqual({
      [OVERRIDE]: ['error', { requireOptions: true, allowOverrideTrue: true }],
    });
  });

  it('allows overrideAccess: true, with no user, when depth and versions are spelled out', async () => {
    expect(await messages(call('overrideAccess: true, depth: 0, versions: false'))).toEqual([]);
  });

  it('still fails a call without depth or versions', async () => {
    expect(await messages(call('overrideAccess: true, versions: false'))).toEqual(['missing']);
    expect(await messages(call('overrideAccess: true, depth: 0'))).toEqual(['missing']);
    expect(await messages('payload.find({});\n')).toEqual(['missing', 'missing', 'missing']);
  });

  it('still fails showHiddenFields: true', async () => {
    const options = 'overrideAccess: true, depth: 0, versions: false, showHiddenFields: true';
    expect(await messages(call(options))).toEqual(['showHidden']);
  });

  it('still fails .db, spreads, computed keys, options that are not a literal and bare method reads', async () => {
    expect(await messages('payload.db.drizzle.execute(sql);\n')).toEqual(['rawDb']);
    expect(
      await messages(call('...opts, overrideAccess: true, depth: 0, versions: false')),
    ).toEqual(['spread']);
    expect(
      await messages(call('[k]: true, overrideAccess: true, depth: 0, versions: false')),
    ).toEqual(['computedKey']);
    expect(await messages('payload.find(opts);\n')).toEqual(['notLiteral']);
    expect(await messages('const { find } = payload; void find;\n')).toEqual(['notCalled']);
  });

  it('does not relax any other file, in or out of packages/data', async () => {
    const code = call('overrideAccess: true, depth: 0, versions: false');
    expect(await messages(code, inside)).toEqual(['missingOneOf', 'notFalse']);
    expect(await messages('f({ overrideAccess: true });\n', outside)).toEqual(['notFalse']);
  });

  it('the rule schema accepts only a boolean for the option', async () => {
    const bad = eslintWith([
      {
        files: [job],
        rules: { [OVERRIDE]: ['error', { allowOverrideTrue: 'yes' }] },
      },
    ]);
    await expect(bad.lintText('x;\n', { filePath: join(root, job) })).rejects.toThrow();
  });
});
