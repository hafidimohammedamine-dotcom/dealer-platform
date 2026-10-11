import { parse } from 'yaml';
import { isMap, toMaps } from './repo.js';

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
  const doc = toMaps(manifest);
  if (!isMap(doc)) return [`${where}: not a JSON object`];
  const meta = doc.get('dependenciesMeta');
  if (meta === undefined) return [];
  if (!isMap(meta)) return [`${where}: dependenciesMeta must be an object`];
  const problems: string[] = [];
  for (const [name, settings] of meta) {
    if (isMap(settings) && settings.get('built') === true) {
      problems.push(`${where}: dependenciesMeta.${String(name)}.built must not be true`);
    }
  }
  return problems;
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
  const doc = toMaps(manifest);
  if (!isMap(doc)) return [`${where}: not a JSON object`];
  const scripts = doc.get('scripts');
  if (scripts === undefined) return [];
  if (!isMap(scripts)) return [`${where}: scripts must be an object`];
  return lifecycleScripts
    .filter((name) => scripts.has(name))
    .map((name) => `${where}: scripts.${name} must not exist (lifecycle scripts stay off)`);
}

/** Problems with one URL value of an env template. Never repeats the value itself. */
function urlProblems(key: string, value: string): string[] {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return [`${key}: invalid URL`];
  }
  const problems: string[] = [];
  if (url.hostname.toLowerCase() !== 'localhost') problems.push(`${key}: host must be localhost`);
  if (url.password !== '' && url.password !== 'change-me') {
    problems.push(`${key}: password must be empty or change-me`);
  }
  return problems;
}

/** A value that starts with a URL scheme and `//`, in any case (`postgres://`, `POSTGRES://`, `redis+tls://`). */
const urlScheme = /^[a-z][a-z0-9+.-]*:\/\//i;

/**
 * Problems found in the values of an env template. Only localhost URLs with a
 * placeholder password are allowed, plus APP_ENV=dev. Keys, tokens and secrets stay empty,
 * even when the value looks like a URL. Never repeats a value.
 */
export function envValueProblems(vars: ReadonlyMap<string, string>): string[] {
  const problems: string[] = [];
  for (const [key, value] of vars) {
    if (value === '') continue;
    if (/(SECRET|KEY|TOKEN)/.test(key)) {
      problems.push(`${key}: must be empty`);
    } else if (urlScheme.test(value)) {
      problems.push(...urlProblems(key, value));
    } else if (key !== 'APP_ENV' || value !== 'dev') {
      problems.push(`${key}: unexpected value (only APP_ENV=dev or a localhost URL)`);
    }
  }
  return problems;
}
