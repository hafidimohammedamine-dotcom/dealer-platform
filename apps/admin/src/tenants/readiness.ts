import { PAYLOAD_BUILT_IN } from './deny-by-default.js';

// Security gates that must be true before any customer data can be stored (CLAUDE.md Payload rules 2, 3, 9, 13).
//
// Both are false today. While one is false, the config test (config.test.ts) FAILS if any collection other than the
// dealers, the users and Payload's own bookkeeping collections is registered, whichever way it got in. Whoever builds
// the gate flips its flag in the same pull request, with the proof (tests) the reviewers ask for.
export const securityGates = {
  /** Issue #57: TOTP second factor required at login for every dealer user (rule 9, 16 CFR 314.4(c)(5)). */
  twoFactorRequired: false,
  /** Issue #58: Postgres row-level security with FORCE, a non-owner app role, dealer set per transaction (rule 2). */
  rowLevelSecurity: false,
} as const;

/** Collections that hold no customer information and exist before the gates are met. */
export const GATE_FREE_COLLECTIONS: readonly string[] = ['dealers', 'users', ...PAYLOAD_BUILT_IN];

export interface GateInput {
  twoFactorRequired: boolean;
  rowLevelSecurity: boolean;
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
  return problems;
}
