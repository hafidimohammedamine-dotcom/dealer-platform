import { describe, expect, it } from 'vitest';
import { trackedFileProblems } from './checks.js';

const message = (path: string): string =>
  `${path}: saved Playwright login state, HAR or trace must not be committed`;

describe('trackedFileProblems: Playwright login state, HAR and traces', () => {
  it.each([
    'playwright/.auth/user.json',
    'tests/e2e/playwright/.auth/user.json',
    'tests/e2e/.auth/user.json',
    '.auth/admin.json',
    'tests/e2e/.auth/deep/admin.json',
    'tests/e2e/net.har',
    'tests/e2e/NET.HAR',
    'recording.har',
    'tests/e2e/out/trace.zip',
    'trace.zip',
    'tests/e2e/storageState.json',
    'tests/e2e/storage-state.json',
    'tests/e2e/fixtures/Storage-State-admin.json',
    'storagestate.json',
  ])('flags %s', (path) => {
    expect(trackedFileProblems([path])).toEqual([message(path)]);
  });

  it('accepts files named like them that are not', () => {
    expect(
      trackedFileProblems([
        'src/auth/x.ts',
        'docs/har.md',
        'tests/e2e/src/test-results.ts',
        'tests/e2e/playwright/config.ts',
        'tests/e2e/auth/user.json',
        'tests/e2e/.authors/x.json',
        'tests/e2e/my-trace.zip.md',
        'tests/e2e/trace.zip.ts',
        'tests/e2e/storage.json',
        'tests/e2e/state.json',
        'docs/dev/storage-state.md',
        'tests/e2e/.auth',
      ]),
    ).toEqual([]);
  });

  it('keeps the skipped-folder message for output folders', () => {
    expect(trackedFileProblems(['tests/e2e/test-results/trace.zip'])).toEqual([
      'tests/e2e/test-results/trace.zip: committed in a folder lint skips',
    ]);
  });
});
