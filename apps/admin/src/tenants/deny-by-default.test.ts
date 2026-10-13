import { buildConfig } from 'payload';
import { beforeAll, describe, expect, it } from 'vitest';
import { buildAppConfig } from './config.js';
import {
  denyByDefaultProblems,
  LOCKED_DOCUMENTS_SLUG,
  PAYLOAD_BUILT_IN,
  sanitizedConfigProblems,
} from './deny-by-default.js';
import { devEnv } from '../test-helpers/fixtures.js';

const env = devEnv;

type Built = Awaited<ReturnType<typeof buildConfig>>;
let config: Built;
beforeAll(async () => {
  config = await buildConfig(buildAppConfig({ env }));
});
// Runs the access function `op` of the collection `slug` (undefined when the collection does not set one).
const accessOf = (slug: string): Record<string, (args: unknown) => unknown> =>
  new Proxy(
    {},
    {
      get: (_target, op: string) => (args: unknown) => {
        const fn: unknown = Reflect.get(
          config.collections.find((c) => c.slug === slug)?.access ?? {},
          op,
        );
        return typeof fn === 'function' ? Reflect.apply(fn, undefined, [args]) : undefined;
      },
    },
  );
const as = (user: unknown) => ({ req: { user } });
const staff = { id: 'u1', collection: 'users', role: 'sales_rep', tenants: [{ tenant: 'A' }] };

describe('Payload built-in collections, as they are in the final config', () => {
  it('are exactly the reviewed ones, and the locked-documents collection is not there', () => {
    const slugs = config.collections.map((c) => c.slug);
    expect(PAYLOAD_BUILT_IN.every((slug) => slugs.includes(slug))).toBe(true);
    expect(slugs).not.toContain(LOCKED_DOCUMENTS_SLUG);
  });

  it('payload-migrations: open to every logged-in user by default, closed once onInit has run', async () => {
    // Break it on purpose: before the lock, Payload's own default lets any logged-in user in.
    for (const op of ['create', 'read', 'update', 'delete']) {
      expect(await accessOf('payload-migrations')[op]?.(as(staff))).toBe(true);
    }
    await Reflect.apply(config.onInit ?? (() => undefined), undefined, [{ config }]);
    for (const op of ['create', 'read', 'update', 'delete']) {
      for (const user of [staff, undefined]) {
        expect(await accessOf('payload-migrations')[op]?.(as(user)), op).toBe(false);
      }
    }
  });

  it('payload-preferences: a user reaches only their own preferences, and nobody anonymous any', async () => {
    for (const op of ['read', 'update', 'delete']) {
      expect(await accessOf('payload-preferences')[op]?.(as(undefined))).toBe(false);
      expect(await accessOf('payload-preferences')[op]?.(as(staff))).toEqual({
        and: [{ 'user.value': { equals: 'u1' } }, { 'user.relationTo': { equals: 'users' } }],
      });
    }
  });

  it('payload-kv: every operation is closed', async () => {
    const kv = accessOf('payload-kv');
    for (const op of ['create', 'read', 'update', 'delete']) {
      // `undefined` means this collection sets no function for the operation (Payload's own source sets all four to false).
      expect([false, undefined], op).toContain(await kv[op]?.(as(staff)));
    }
  });
});

describe('denyByDefaultProblems on the real raw list', () => {
  it('has no problems', () => {
    expect(
      denyByDefaultProblems({
        collections: buildAppConfig({ env }).collections ?? [],
        pluginSlugs: [],
        coreSlugs: ['dealers', 'users'],
        allowlist: [],
      }),
    ).toEqual([]);
  });

  it('the final config check reports an unreviewed slug and the locked-documents collection', () => {
    expect(
      sanitizedConfigProblems(['dealers', LOCKED_DOCUMENTS_SLUG, 'sneaky'], ['dealers']),
    ).toEqual([
      `${LOCKED_DOCUMENTS_SLUG} exists`,
      'sneaky: in the final config but not on the reviewed list',
    ]);
  });
});
