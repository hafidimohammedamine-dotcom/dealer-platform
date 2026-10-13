import { USERS_COLLECTION } from '@dealer/data';
import { DEALERS_SLUG } from './dealers.js';
import { PAYLOAD_BUILT_IN } from './deny-by-default.js';

// Security gates (CLAUDE.md Payload rules 2, 3, 9, 13, 14). All four are false today. Whoever builds a gate flips its flag
// in the same pull request, with the proof (tests) the reviewers ask for.
//  - While twoFactorRequired, rowLevelSecurity or auditStore is false, the config test FAILS if any collection other
//    than the dealers, the users and Payload's own bookkeeping collections is registered, whichever way it got in.
//  - While twoFactorRequired or loginSurface is false, the exposure test FAILS if the admin app has any HTTP entry point.
export const securityGates = {
  /** Issue #57: TOTP second factor required at login for every dealer user (rule 9, 16 CFR 314.4(c)(5)). */
  twoFactorRequired: false,
  /** Issue #58: Postgres row-level security with FORCE, a non-owner app role, dealer set per transaction (rule 2). */
  rowLevelSecurity: false,
  /**
   * Issue #71: the access audit log goes to a durable, append-only database table with its own retention
   * (16 CFR 314.4(c)(8)). Today it goes to stdout only (Railway keeps the log stream).
   */
  auditStore: false,
  /**
   * Issue #73: Redis-backed login limits, a trusted client IP, login and logout audit, and the password-reset flow.
   * Until then forgot-password and reset-password are refused (users.ts).
   */
  loginSurface: false,
} as const;

/** Collections that hold no customer information and exist before the gates are met. */
export const GATE_FREE_COLLECTIONS: readonly string[] = [
  DEALERS_SLUG,
  USERS_COLLECTION,
  ...PAYLOAD_BUILT_IN,
];

export interface GateInput {
  twoFactorRequired: boolean;
  rowLevelSecurity: boolean;
  auditStore: boolean;
  /** Slugs of the sanitized config. */
  collectionSlugs: readonly string[];
}

/** Problems that stop the build: a collection with customer data exists while a gate is open. */
export function gateProblems(input: GateInput): string[] {
  const extra = input.collectionSlugs.filter((slug) => !GATE_FREE_COLLECTIONS.includes(slug));
  if (extra.length === 0) return [];
  const problems: string[] = [];
  if (!input.twoFactorRequired)
    problems.push(`${extra.join(', ')}: registered before 2FA (issue #57) is enforced`);
  if (!input.rowLevelSecurity)
    problems.push(
      `${extra.join(', ')}: registered before row-level security (issue #58) is in place`,
    );
  if (!input.auditStore)
    problems.push(
      `${extra.join(', ')}: registered before the durable audit table (issue #71) is in place`,
    );
  return problems;
}

export interface SourceFile {
  /** Path inside `apps/admin`, forward slashes (no node_modules or build output). */
  path: string;
  /** The file's text (only read for code files). */
  text: string;
}
export interface ExposureGates {
  twoFactorRequired: boolean;
  loginSurface: boolean;
}

const CODE = /\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;
// Next.js routes: anything under an `app/` or `pages/` folder at the app root or in `src/` (fail closed: helpers too).
const ROUTER_DIR = /^(src\/)?(app|pages)\//;
// Next.js and server files that answer requests or run at start, wherever they are.
const SERVER_FILE =
  /(^|\/)(middleware|proxy|server|instrumentation|instrumentation-client|next\.config)\.(ts|tsx|mts|cts|js|jsx|mjs|cjs)$/;
// Importing Payload's Next.js integration, or Next.js itself, is how routes get mounted.
const NEXT_IMPORT =
  /(from\s*|import\s*\(\s*|require\s*\(\s*|import\s+)['"](@payloadcms\/next|next)(\/[^'"]*)?['"]/;

/**
 * Payload rules 9 and 14: until 2FA (#57) and the login surface (#73) exist, the admin app must not be reachable at all.
 * This lists every HTTP entry point: a Next.js route folder, a middleware/proxy/server/instrumentation/next.config file,
 * or code that imports `@payloadcms/next` or `next`. Test files are checked by path only.
 */
export function exposureProblems(gates: ExposureGates, files: readonly SourceFile[]): string[] {
  if (gates.twoFactorRequired && gates.loginSurface) return [];
  const why = 'an HTTP entry point exists before 2FA (issue #57) and the login surface (issue #73)';
  return files
    .filter(
      ({ path, text }) =>
        CODE.test(path) &&
        (ROUTER_DIR.test(path) ||
          SERVER_FILE.test(path) ||
          (!/\.test\.[a-z]+$/.test(path) && NEXT_IMPORT.test(text))),
    )
    .map(({ path }) => `${path}: ${why}`);
}

// A table name as Postgres sees it: `"Quoted"` keeps its case, unquoted folds to lower case; an optional schema.
const NAME =
  '((?:"[^"]+"|[A-Za-z_][A-Za-z0-9_$]*)(?:\\s*\\.\\s*(?:"[^"]+"|[A-Za-z_][A-Za-z0-9_$]*))?)';
const STATEMENT = new RegExp(
  [
    `CREATE\\s+(?:UNLOGGED\\s+)?TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?${NAME}`,
    `ALTER\\s+TABLE\\s+(?:IF\\s+EXISTS\\s+)?(?:ONLY\\s+)?${NAME}\\s+(ENABLE|FORCE|DISABLE|NO\\s+FORCE)\\s+ROW\\s+LEVEL\\s+SECURITY`,
  ].join('|'),
  'gi',
);

function tableKey(name: string): string {
  const parts = (name.match(/"[^"]+"|[^."\s]+/g) ?? []).map((part) =>
    part.startsWith('"') ? part.slice(1, -1) : part.toLowerCase(),
  );
  const [schema, table] = parts.length === 2 ? parts : ['public', parts[0]];
  return schema === 'public' ? `${table}` : `${schema}.${table}`;
}

/**
 * Payload rule 2: every table a migration creates needs `ENABLE` and `FORCE ROW LEVEL SECURITY` once the gate is on.
 * Returns the tables created in `sql` that lack either (statements are read in order, so a later `DISABLE` or
 * `NO FORCE` undoes them). Names are compared as Postgres does: case-folded unless quoted, `public` by default.
 * Payload's migration bookkeeping table is exempt: it holds no dealer data and the migration job needs it.
 */
export function tablesWithoutRls(sql: string): string[] {
  const created: string[] = [];
  const enabled = new Set<string>();
  const forced = new Set<string>();
  for (const match of sql.matchAll(STATEMENT)) {
    const [, createName, alterName, action = ''] = match;
    if (createName !== undefined) {
      created.push(tableKey(createName));
      continue;
    }
    const table = tableKey(alterName ?? '');
    const verb = action.toUpperCase().replace(/\s+/g, ' ');
    if (verb === 'ENABLE') enabled.add(table);
    if (verb === 'FORCE') forced.add(table);
    if (verb === 'DISABLE') enabled.delete(table);
    if (verb === 'NO FORCE') forced.delete(table);
  }
  return created.filter(
    (table) => table !== 'payload_migrations' && !(enabled.has(table) && forced.has(table)),
  );
}
