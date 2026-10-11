import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

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

/** Reads a JSON file and checks its shape with a type guard. Throws on a bad shape. */
export function readJson<T>(
  root: string,
  relativePath: string,
  guard: (value: unknown) => value is T,
): T {
  const value: unknown = JSON.parse(readText(root, relativePath));
  if (!guard(value)) throw new Error(`Unexpected shape in ${relativePath}`);
  return value;
}

export const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const isMap = (value: unknown): value is Map<unknown, unknown> => value instanceof Map;

/**
 * Copies a JSON-like value with every plain object turned into a Map (a round trip through the YAML parser, which
 * reads JSON and can return Maps), so it can be read with `.get()` and iterated without a dynamic key.
 */
export function toMaps(value: unknown): unknown {
  const text = JSON.stringify(value);
  return text === undefined ? undefined : parse(text, { mapAsMap: true });
}

const isStringArray = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every((item) => typeof item === 'string');

const hasWorkspaces = (value: unknown): value is { workspaces: string[] } =>
  isRecord(value) && isStringArray(value['workspaces']);

/** Expands the root package.json `workspaces` globs ("dir/*") to workspace folders. */
export function listWorkspaces(root: string): string[] {
  const { workspaces } = readJson(root, 'package.json', hasWorkspaces);
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

/** Folders a repo walk never enters: installs, git data, caches, build output and worktrees. */
export const walkSkip: ReadonlySet<string> = new Set([
  'node_modules',
  '.git',
  '.yarn',
  '.nx',
  'dist',
  'coverage',
  '.worktrees',
]);

/**
 * Repo-relative paths (with `/`) of every file under `root` whose name matches, skipping the
 * folders in `walkSkip`. Sorted.
 */
export function findFiles(root: string, match: (name: string) => boolean): string[] {
  const found: string[] = [];
  const walk = (dir: string): void => {
    for (const entry of readdirSync(join(root, dir), { withFileTypes: true })) {
      const relative = dir === '' ? entry.name : `${dir}/${entry.name}`;
      if (entry.isDirectory()) {
        if (!walkSkip.has(entry.name)) walk(relative);
      } else if (match(entry.name)) {
        found.push(relative);
      }
    }
  };
  walk('');
  return found.sort();
}

/** Parses KEY=value lines of an env template. Comments and blank lines are skipped. */
export function parseEnvTemplate(text: string): Map<string, string> {
  const vars = new Map<string, string>();
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq < 1) throw new Error(`Bad env line: ${trimmed}`);
    const key = trimmed.slice(0, eq);
    if (vars.has(key)) throw new Error(`Duplicate env key: ${key}`);
    vars.set(key, trimmed.slice(eq + 1));
  }
  return vars;
}
