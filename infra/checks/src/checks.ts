import { parse } from 'yaml';
import { isRecord } from './repo.js';

/**
 * The only settings `.yarnrc.yml` may hold, with their required values. Anything else (a registry,
 * scope, proxy, SSL or auth setting, or scripts turned back on) fails the check.
 */
export const requiredYarnrc: Readonly<Record<string, unknown>> = {
  nodeLinker: 'node-modules',
  enableTelemetry: false,
  enableScripts: false,
};

/** Problems with the text of `.yarnrc.yml`. Empty when it matches `requiredYarnrc` exactly. */
export function yarnrcProblems(text: string): string[] {
  let doc: unknown;
  try {
    // Duplicate keys are an error, so a later `enableScripts: true` cannot hide behind an earlier line.
    doc = parse(text, { uniqueKeys: true });
  } catch {
    return ['.yarnrc.yml: not valid YAML (or a key appears twice)'];
  }
  if (!isRecord(doc)) return ['.yarnrc.yml: must be a mapping of settings'];
  const problems: string[] = [];
  for (const key of Object.keys(doc)) {
    if (!(key in requiredYarnrc)) problems.push(`.yarnrc.yml: setting not allowed: ${key}`);
  }
  for (const [key, value] of Object.entries(requiredYarnrc)) {
    if (doc[key] !== value) problems.push(`.yarnrc.yml: ${key} must be ${String(value)}`);
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
  const problems: string[] = [];
  for (const [name, settings] of Object.entries(meta)) {
    if (isRecord(settings) && settings['built'] === true) {
      problems.push(`${where}: dependenciesMeta.${name}.built must not be true`);
    }
  }
  return problems;
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
