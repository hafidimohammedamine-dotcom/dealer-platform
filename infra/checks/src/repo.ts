import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const packageName = '@dealer/infra-checks';

/** Repo root, found by walking up from this file to the folder with `.yarnrc.yml`. */
export function findRepoRoot(start: string = dirname(fileURLToPath(import.meta.url))): string {
  let dir = resolve(start);
  for (;;) {
    if (existsSync(join(dir, '.yarnrc.yml'))) return dir;
    const parent = dirname(dir);
    if (parent === dir) throw new Error('Repo root not found');
    dir = parent;
  }
}

export function readText(root: string, relativePath: string): string {
  return readFileSync(join(root, relativePath), 'utf8');
}

export function readJson<T = Record<string, unknown>>(root: string, relativePath: string): T {
  return JSON.parse(readText(root, relativePath)) as T;
}

/** Expands the root package.json `workspaces` globs ("dir/*") to workspace folders. */
export function listWorkspaces(root: string): string[] {
  const { workspaces } = readJson<{ workspaces: string[] }>(root, 'package.json');
  const folders: string[] = [];
  for (const pattern of workspaces) {
    if (!pattern.endsWith('/*')) throw new Error(`Unsupported workspace pattern: ${pattern}`);
    const base = pattern.slice(0, -2);
    for (const entry of readdirSync(join(root, base), { withFileTypes: true })) {
      if (entry.isDirectory() && existsSync(join(root, base, entry.name, 'package.json'))) {
        folders.push(`${base}/${entry.name}`);
      }
    }
  }
  return folders.sort();
}

/** Parses KEY=value lines of an env template. Comments and blank lines are skipped. */
export function parseEnvTemplate(text: string): Map<string, string> {
  const vars = new Map<string, string>();
  for (const line of text.split('\n')) {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq < 1) throw new Error(`Bad env line: ${trimmed}`);
    vars.set(trimmed.slice(0, eq), trimmed.slice(eq + 1));
  }
  return vars;
}
