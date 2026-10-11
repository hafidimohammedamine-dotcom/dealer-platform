import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import {
  findRepoRoot,
  isRecord,
  listWorkspaces,
  parseEnvTemplate,
  readJson,
  trackedFiles,
} from './repo.js';

const hasName = (value: unknown): value is { name: string } =>
  isRecord(value) && typeof value['name'] === 'string';

const temps: string[] = [];
const makeTemp = (): string => {
  const dir = mkdtempSync(join(tmpdir(), 'infra-checks-'));
  temps.push(dir);
  return dir;
};

afterEach(() => {
  for (const dir of temps.splice(0)) rmSync(dir, { recursive: true, force: true });
});

describe('repo helpers', () => {
  it('finds the repo root from this folder', () => {
    expect(readJson(findRepoRoot(), 'package.json', hasName).name).toBe('dealer-platform');
  });

  it('throws when no repo root exists above the start folder', () => {
    // Any folder under the temp dir has no .yarnrc.yml above it.
    expect(() => findRepoRoot(makeTemp())).toThrow('Repo root not found');
  });

  it('expands workspace globs and skips folders without package.json', () => {
    const root = makeTemp();
    mkdirSync(join(root, 'pkgs', 'b'), { recursive: true });
    mkdirSync(join(root, 'pkgs', 'a'), { recursive: true });
    mkdirSync(join(root, 'pkgs', 'empty'), { recursive: true });
    writeFileSync(join(root, 'pkgs', 'a', 'package.json'), '{}');
    writeFileSync(join(root, 'pkgs', 'b', 'package.json'), '{}');
    writeFileSync(join(root, 'pkgs', 'file.txt'), 'not a folder');
    writeFileSync(join(root, 'package.json'), JSON.stringify({ workspaces: ['pkgs/*'] }));
    expect(listWorkspaces(root)).toEqual(['pkgs/a', 'pkgs/b']);
  });

  it('rejects workspace patterns it cannot expand', () => {
    const root = makeTemp();
    writeFileSync(join(root, 'package.json'), JSON.stringify({ workspaces: ['pkgs/**'] }));
    expect(() => listWorkspaces(root)).toThrow('Unsupported workspace pattern');
  });

  it('lists the files git tracks, at any depth, and no untracked or ignored file', () => {
    const root = makeTemp();
    execFileSync('git', ['init', '-q'], { cwd: root });
    mkdirSync(join(root, 'a', 'b'), { recursive: true });
    mkdirSync(join(root, 'node_modules', 'x'), { recursive: true });
    writeFileSync(join(root, '.gitignore'), 'node_modules/\n');
    writeFileSync(join(root, 'top.txt'), '');
    writeFileSync(join(root, 'a', 'b', 'deep file.txt'), '');
    writeFileSync(join(root, 'node_modules', 'x', 'index.js'), '');
    writeFileSync(join(root, 'untracked.txt'), '');
    execFileSync('git', ['add', '.gitignore', 'top.txt', 'a'], { cwd: root });
    expect(trackedFiles(root).sort()).toEqual(['.gitignore', 'a/b/deep file.txt', 'top.txt']);
    // A force-added file in an ignored folder is tracked, so the checks see it.
    execFileSync('git', ['add', '-f', 'node_modules/x/index.js'], { cwd: root });
    expect(trackedFiles(root)).toContain('node_modules/x/index.js');
  });

  it('parses env templates and skips comments and blank lines', () => {
    const vars = parseEnvTemplate('# note\n\nA=1\nB=\nC=x=y\n');
    expect([...vars]).toEqual([
      ['A', '1'],
      ['B', ''],
      ['C', 'x=y'],
    ]);
  });

  it('keeps every = after the first in the value, with CRLF line endings', () => {
    expect([...parseEnvTemplate('A=x=y=\r\nB=postgres://u:change-me@localhost/x?a=b\r\n')]).toEqual(
      [
        ['A', 'x=y='],
        ['B', 'postgres://u:change-me@localhost/x?a=b'],
      ],
    );
  });

  it('rejects malformed env lines', () => {
    expect(() => parseEnvTemplate('not a variable')).toThrow('Bad env line');
  });

  it('rejects env files with duplicate keys', () => {
    expect(() => parseEnvTemplate('A=1\nA=2\n')).toThrow('Duplicate env key: A');
  });

  it('reads env files with Windows line endings', () => {
    expect([...parseEnvTemplate('# note\r\nA=1\r\n\r\nB=\r\n')]).toEqual([
      ['A', '1'],
      ['B', ''],
    ]);
  });

  it('throws when a JSON file has the wrong shape', () => {
    const root = makeTemp();
    writeFileSync(join(root, 'a.json'), JSON.stringify({ name: 5 }));
    expect(() => readJson(root, 'a.json', hasName)).toThrow('Unexpected shape in a.json');
  });

  it('throws when workspaces is not a list of strings', () => {
    const root = makeTemp();
    writeFileSync(join(root, 'package.json'), JSON.stringify({ workspaces: [1] }));
    expect(() => listWorkspaces(root)).toThrow('Unexpected shape in package.json');
  });

  it('isRecord rejects null and arrays', () => {
    expect(isRecord(null)).toBe(false);
    expect(isRecord([])).toBe(false);
    expect(isRecord({})).toBe(true);
  });
});
