import { parse } from 'yaml';
import { isMap, isRecord } from './repo.js';

/**
 * The settings `.yarnrc.yml` must hold, with their required values. The file is founder-owned and pinned
 * (`.github/pins.txt`), so this check follows it, not the other way round.
 */
const requiredEntries: readonly (readonly [string, unknown])[] = [
  ['nodeLinker', 'node-modules'],
  ['enableScripts', false],
];
const optionalEntries: readonly (readonly [string, unknown])[] = [['enableTelemetry', false]];
export const requiredYarnrc: Readonly<Record<string, unknown>> =
  Object.fromEntries(requiredEntries);

/** Settings `.yarnrc.yml` may hold, with the only value allowed for each. */
export const optionalYarnrc: Readonly<Record<string, unknown>> =
  Object.fromEntries(optionalEntries);

/** `dependenciesMeta` keys: one exact package version (`name@1.2.3`, scoped or not). */
const builtEntryKey = /^(@[^@/\s]+\/)?[^@/\s]+@\d+\.\d+\.\d+$/;

/**
 * Problems with `dependenciesMeta` in `.yarnrc.yml`. A founder may allow one package its build script
 * there (CLAUDE.md, `.yarnrc.yml` header): each entry is an exact version mapped to exactly `{ built: true }`.
 * Anything else (a range, another key, `built: false` as noise) fails.
 */
function yarnrcDependenciesMetaProblems(meta: unknown): string[] {
  if (!isMap(meta)) return ['.yarnrc.yml: dependenciesMeta must be an object'];
  const problems: string[] = [];
  for (const [key, value] of meta) {
    const name = String(key);
    if (!builtEntryKey.test(name)) {
      problems.push(`.yarnrc.yml: dependenciesMeta key must be an exact package version: ${name}`);
      continue;
    }
    if (!isMap(value) || value.size !== 1 || value.get('built') !== true) {
      problems.push(`.yarnrc.yml: dependenciesMeta entry must be exactly { built: true }: ${name}`);
    }
  }
  return problems;
}

/** Problems with the text of `.yarnrc.yml`. Empty when it holds `requiredYarnrc`, at most `optionalYarnrc` and a valid `dependenciesMeta`. */
export function yarnrcProblems(text: string): string[] {
  let doc: unknown;
  try {
    // Duplicate keys are an error, so a later `enableScripts: true` cannot hide behind an earlier line.
    doc = parse(text, { uniqueKeys: true, mapAsMap: true });
  } catch {
    return ['.yarnrc.yml: not valid YAML (or a key appears twice)'];
  }
  if (!isMap(doc)) return ['.yarnrc.yml: must be a mapping of settings'];
  const problems: string[] = [];
  const required = new Map(requiredEntries);
  const optional = new Map(optionalEntries);
  for (const key of doc.keys()) {
    if (key === 'dependenciesMeta') problems.push(...yarnrcDependenciesMetaProblems(doc.get(key)));
    else if (!required.has(String(key)) && !optional.has(String(key))) {
      problems.push(`.yarnrc.yml: setting not allowed: ${String(key)}`);
    }
  }
  for (const [key, value] of required) {
    if (doc.get(key) !== value) problems.push(`.yarnrc.yml: ${key} must be ${String(value)}`);
  }
  for (const [key, value] of optional) {
    if (doc.has(key) && doc.get(key) !== value) {
      problems.push(`.yarnrc.yml: ${key} must be ${String(value)}`);
    }
  }
  return problems;
}

/**
 * Problems with `dependenciesMeta` in one package.json: no dependency may be marked `built: true`
 * (that would let its install scripts run).
 */
export function dependenciesMetaProblems(manifest: unknown, where: string): string[] {
  if (!isRecord(manifest)) return [`${where}: not a JSON object`];
  const meta = manifest['dependenciesMeta'];
  if (meta === undefined) return [];
  if (!isRecord(meta)) return [`${where}: dependenciesMeta must be an object`];
  return Object.entries(meta)
    .filter(([, settings]) => isRecord(settings) && settings['built'] === true)
    .map(([name]) => `${where}: dependenciesMeta.${name}.built must not be true`);
}

/** Script names that run on their own during install or pack. A workspace's own are not stopped by `enableScripts: false`. */
export const lifecycleScripts: readonly string[] = [
  'preinstall',
  'install',
  'postinstall',
  'prepare',
  'prepack',
  'postpack',
];

/** Problems with one package.json: it must not define an install or pack lifecycle script. */
export function lifecycleScriptProblems(manifest: unknown, where: string): string[] {
  if (!isRecord(manifest)) return [`${where}: not a JSON object`];
  const scripts = manifest['scripts'];
  if (scripts === undefined) return [];
  if (!isRecord(scripts)) return [`${where}: scripts must be an object`];
  return lifecycleScripts
    .filter((name) => Object.hasOwn(scripts, name))
    .map((name) => `${where}: scripts.${name} must not exist (lifecycle scripts stay off)`);
}

/**
 * The only non-empty values `.env.example` may hold: local placeholders, each reviewed as an exact string. A value
 * that differs in any part (user name, password, host, port, path, query or fragment) fails, so nothing real can hide
 * in a field the check does not look at.
 */
export const envPlaceholders: ReadonlyMap<string, string> = new Map([
  ['APP_ENV', 'dev'],
  ['DATABASE_URL', 'postgres://app_user:change-me@localhost:5432/dealer'],
  ['MIGRATION_DATABASE_URL', 'postgres://owner_user:change-me@localhost:5432/dealer'],
  ['DESKING_DATABASE_URL', 'postgres://desking_user:change-me@localhost:5432/dealer'],
  ['REDIS_URL', 'redis://localhost:6379'],
  ['PAYLOAD_PUBLIC_SERVER_URL', 'http://localhost:3000'],
]);

/**
 * Problems found in the values of an env template: every value is empty or exactly its entry in `envPlaceholders`.
 * Never repeats a value.
 */
export function envValueProblems(vars: ReadonlyMap<string, string>): string[] {
  const problems: string[] = [];
  for (const [key, value] of vars) {
    if (value !== '' && envPlaceholders.get(key) !== value) {
      problems.push(`${key}: must be empty or exactly its placeholder in envPlaceholders`);
    }
  }
  return problems;
}

/**
 * Top-level folders that hold workspaces (`<folder>/<workspace>/`): those in the root `package.json`, plus `tests` for
 * the Playwright e2e workspace.
 */
const workspaceFolders: readonly string[] = ['apps', 'services', 'packages', 'infra', 'tests'];

/**
 * Playwright output folders. They can hold traces with cookies, auth headers and credit-app fields, so they are never
 * committed, at any depth.
 */
const playwrightOutputFolders: readonly string[] = [
  'test-results',
  'playwright-report',
  'blob-report',
];

/** Is this path under `playwright/.auth` (saved login state), at any depth? */
function inPlaywrightAuth(folders: readonly string[]): boolean {
  return folders.some((folder, i) => folder === 'playwright' && folders[i + 1] === '.auth');
}

/**
 * Is this path in a folder lint never looks at (the ignores in `eslint.config.mjs`): `node_modules` at any depth, the
 * root `.nx` and `.yarn`, `<workspace>/dist` and `<workspace>/coverage`, or Playwright output (`test-results`, `playwright-report`, `blob-report`) at any depth.
 * The founder-owned `.yarn/releases/` and `.yarn/plugins/` at the root are allowed.
 */
function inUnlintedFolder(path: string): boolean {
  const folders = path.split('/').slice(0, -1);
  if (folders.includes('node_modules')) return true;
  if (folders.some((folder) => playwrightOutputFolders.includes(folder))) return true;
  const [top = '', second = '', third = ''] = folders;
  if (top === '.nx') return true;
  if (top === '.yarn') return second !== 'releases' && second !== 'plugins';
  return workspaceFolders.includes(top) && (third === 'dist' || third === 'coverage');
}

/** An ESLint config file name: flat (`eslint.config.js`, `.mjs`, `.cjs`, `.ts`, `.mts`, `.cts`) or legacy (`.eslintrc*`). */
const eslintConfigName = /^(?:eslint\.config\.[cm]?[jt]s|\.eslintrc(?:\..+)?)$/;

/**
 * Problems with the list of files git tracks (repo-relative, `/`-separated). Nothing may be committed where lint
 * never looks, and the root `eslint.config.mjs` is the only ESLint config.
 */
export function trackedFileProblems(paths: readonly string[]): string[] {
  const problems: string[] = [];
  for (const path of paths) {
    if (inUnlintedFolder(path)) problems.push(`${path}: committed in a folder lint skips`);
    else if (inPlaywrightAuth(path.split('/').slice(0, -1))) {
      problems.push(`${path}: Saved Playwright login state must not be committed`);
    }
    const name = path.slice(path.lastIndexOf('/') + 1);
    if (eslintConfigName.test(name) && path !== 'eslint.config.mjs') {
      problems.push(`${path}: ESLint config outside the repo root`);
    }
  }
  return problems;
}
