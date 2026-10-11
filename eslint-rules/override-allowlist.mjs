// @ts-check
// Reads the founder-only list of system jobs that may use `overrideAccess: true`
// (CLAUDE.md, Payload rule 1). The list is a file, not code, so an agent cannot widen it in a normal PR:
// the guards only accept `packages/data/override-allowlist.txt` from a founder's PR.
//
// Format: one exact repo-relative file path per line. Blank lines and lines that start with `#` are skipped.
// No globs, no trailing comments. A missing file means nothing is allowed. A malformed line, or a listed
// file that does not exist, is an error: ESLint cannot load its config, so lint fails.

import { readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { repoRoot } from './ast.mjs';

/** Repo-relative path of the list. */
export const overrideAllowlistFile = 'packages/data/override-allowlist.txt';

/** Letters, digits and `_ @ . -` in each segment, separated by single slashes. No globs, no spaces. */
const exactPath = /^[A-Za-z0-9_@.-]+(?:\/[A-Za-z0-9_@.-]+)*$/;

/**
 * @param {string} text
 * @returns {{ paths: string[], problems: string[] }}
 */
export function parseOverrideAllowlist(text) {
  /** @type {string[]} */
  const paths = [];
  /** @type {string[]} */
  const problems = [];
  text.split(/\r?\n/).forEach((raw, index) => {
    const line = raw.trim();
    if (line === '' || line.startsWith('#')) return;
    const segments = line.split('/');
    if (!exactPath.test(line) || segments.some((part) => part === '.' || part === '..')) {
      problems.push(`line ${index + 1}: not an exact repo-relative file path (no globs): ${line}`);
      return;
    }
    paths.push(line);
  });
  return { paths, problems };
}

/** @param {string} path */
function isFile(path) {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

/**
 * The exact file paths listed in the allow-list. Throws when a line is malformed or a listed file
 * does not exist. A missing allow-list file gives an empty list.
 * @param {{ file?: string, root?: string }} [where] `file` is the list (absolute), `root` is what its paths are relative to. Tests pass temporary ones.
 * @returns {string[]}
 */
export function readOverrideAllowlist({ root = repoRoot, file } = {}) {
  const listFile = file ?? join(root, overrideAllowlistFile);
  /** @type {string} */
  let text;
  try {
    text = readFileSync(listFile, 'utf8');
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'ENOENT') return [];
    throw error;
  }
  const { paths, problems } = parseOverrideAllowlist(text);
  for (const path of paths) {
    if (!isFile(join(root, path))) problems.push(`listed file does not exist: ${path}`);
  }
  if (problems.length > 0) {
    throw new Error(`${overrideAllowlistFile} is invalid:\n${problems.join('\n')}`);
  }
  return paths;
}
