import { join } from 'node:path';
import { ESLint } from 'eslint';
import { findRepoRoot, listWorkspaces } from '../repo.js';

export const root = findRepoRoot();
export const eslint = new ESLint({ cwd: root });

export const ACCESS = 'local/no-payload-instance-access';
export const MODULES = 'local/no-restricted-modules';
export const OVERRIDE = 'local/no-override-access';
export const CASTS = '@typescript-eslint/consistent-type-assertions';

const ours = new Set([
  ACCESS,
  MODULES,
  OVERRIDE,
  'no-eval',
  'no-implied-eval',
  'no-new-func',
  'no-with',
]);

/** Path of a file outside packages/data, and one inside it. */
export const outside = 'services/intake/src/example.ts';
export const inside = 'packages/data/src/example.ts';

/** Error rule ids of the bans only (warnings such as "inline config ignored" are not counted). */
export async function errors(code: string, file: string): Promise<string[]> {
  const [result] = await eslint.lintText(code, { filePath: join(root, file) });
  return (result?.messages ?? [])
    .filter((message) => message.severity === 2)
    .map((message) => message.ruleId ?? 'parse-error')
    .filter((id) => id === 'parse-error' || ours.has(id));
}

/** All error rule ids, including rules that are not ours. */
export async function allErrors(code: string, file: string): Promise<string[]> {
  const [result] = await eslint.lintText(code, { filePath: join(root, file) });
  return (result?.messages ?? [])
    .filter((message) => message.severity === 2)
    .map((message) => message.ruleId ?? 'parse-error');
}

/** Every workspace except packages/data, the only full exemption. */
export const listOutside = (): string[] =>
  listWorkspaces(root).filter((workspace) => workspace !== 'packages/data');
