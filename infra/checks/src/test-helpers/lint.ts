import { join } from 'node:path';
import { ESLint, type Linter } from 'eslint';
import { findRepoRoot, isRecord, listWorkspaces } from '../repo.js';

export const root = findRepoRoot();

const isFlatConfig = (value: unknown): value is Linter.Config[] =>
  Array.isArray(value) && value.every(isRecord);

/** The default export of a loaded `eslint.config.mjs`, checked to be a flat config array. */
export function flatConfigOf(module: unknown): Linter.Config[] {
  const config = isRecord(module) ? module['default'] : undefined;
  if (!isFlatConfig(config)) throw new Error('eslint.config.mjs must export a flat config array');
  return config;
}

const repoConfig = flatConfigOf(await import('../../../../eslint.config.mjs'));

/**
 * ESLint with the repo's own `eslint.config.mjs`, imported through Vitest instead of loaded by ESLint
 * from disk, so the rules count toward the coverage gate. (A copy that Node loads natively in this
 * process would be mixed into the coverage with the wrong line numbers.) A config test checks, in a
 * separate process, that ESLint loading the file from disk, as `yarn lint` does, gives the same result.
 */
export const eslint = new ESLint({
  cwd: root,
  overrideConfigFile: true,
  overrideConfig: repoConfig,
});

/** Like `eslint`, with extra flat-config blocks added after the repo's own (for allow-list tests). */
export const eslintWith = (extra: unknown): ESLint =>
  new ESLint({
    cwd: root,
    overrideConfigFile: true,
    overrideConfig: [...repoConfig, ...flatConfigOf({ default: extra })],
  });

/** Like `eslint`, but run from another folder (`cwd`), as an editor or `yarn eslint` in a subfolder would. */
export const eslintFrom = (cwd: string): ESLint =>
  new ESLint({ cwd, overrideConfigFile: true, overrideConfig: repoConfig });

/** Error rule ids of the bans for `code` linted as `file` with a given ESLint instance. */
export async function errorsWith(linter: ESLint, code: string, file: string): Promise<string[]> {
  const results = await linter.lintText(code, { filePath: join(root, file) });
  return results
    .flatMap((result) => result.messages)
    .filter((message) => message.severity === 2)
    .map((message) => message.ruleId ?? 'parse-error')
    .filter((id) => id === 'parse-error' || ours.has(id));
}

export const ACCESS = 'local/no-payload-instance-access';
export const MODULES = 'local/no-restricted-modules';
export const OVERRIDE = 'local/no-override-access';
export const CODE = 'local/no-code-constructors';
export const CASTS = '@typescript-eslint/consistent-type-assertions';

const ours = new Set([
  ACCESS,
  MODULES,
  OVERRIDE,
  CODE,
  'no-eval',
  'no-implied-eval',
  'no-new-func',
  'no-with',
]);

/** Path of a file outside packages/data, and one inside it. */
export const outside = 'services/intake/src/example.ts';
export const inside = 'packages/data/src/example.ts';

/** Message ids of local/no-payload-instance-access for `code` linted as `file`, in order. */
export async function messageIds(code: string, file: string): Promise<string[]> {
  const results = await eslint.lintText(code, { filePath: join(root, file) });
  return results
    .flatMap((result) => result.messages)
    .filter((message) => message.ruleId === ACCESS)
    .map((message) => String(message.messageId));
}

/** All error rule ids, including rules that are not ours (warnings are not counted). */
export async function allErrors(code: string, file: string): Promise<string[]> {
  const results = await eslint.lintText(code, { filePath: join(root, file) });
  return results
    .flatMap((result) => result.messages)
    .filter((message) => message.severity === 2)
    .map((message) => message.ruleId ?? 'parse-error');
}

/** Error rule ids of the bans only, plus parse errors, with the repo's own config. */
export const errors = (code: string, file: string): Promise<string[]> =>
  errorsWith(eslint, code, file);

/** Every workspace except packages/data, the only full exemption. */
export const listOutside = (): string[] =>
  listWorkspaces(root).filter((workspace) => workspace !== 'packages/data');
