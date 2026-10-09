import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { findRepoRoot, listWorkspaces, packageName, parseEnvTemplate, readJson } from './repo.js';

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
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/infra-checks');
  });

  it('finds the repo root from this folder', () => {
    expect(readJson<{ name: string }>(findRepoRoot(), 'package.json').name).toBe('dealer-platform');
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

  it('parses env templates and skips comments and blank lines', () => {
    const vars = parseEnvTemplate('# note\n\nA=1\nB=\nC=x=y\n');
    expect([...vars]).toEqual([
      ['A', '1'],
      ['B', ''],
      ['C', 'x=y'],
    ]);
  });

  it('rejects malformed env lines', () => {
    expect(() => parseEnvTemplate('not a variable')).toThrow('Bad env line');
  });
});
