import { PGlite } from '@electric-sql/pglite';
import { PgDialect } from 'drizzle-orm/pg-core';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { down, up } from '../../migrations/20261013_062316_initial.js';
import { migrations } from '../../migrations/index.js';

// The migration runs for real against Postgres 17 (PGlite: the real Postgres engine compiled to WebAssembly), not as text.
let pg: PGlite;
const dialect = new PgDialect();

// What Payload hands the migration: `db.execute(sql...)`. Here the SQL is turned into text and run on PGlite.
const args = () => {
  const db = {
    execute: async (query: Parameters<PgDialect['sqlToQuery']>[0]) => {
      await pg.exec(dialect.sqlToQuery(query).sql);
    },
  };
  return { db, payload: {}, req: {} };
};

async function names(sql: string): Promise<string[]> {
  const result = await pg.query<{ name: string }>(sql);
  return result.rows.map((row) => row.name);
}
const tables = () =>
  names(
    `SELECT table_name AS name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY 1`,
  );

beforeAll(async () => {
  pg = new PGlite();
  await pg.waitReady;
});
afterAll(async () => {
  await pg.close();
});

describe('the initial migration on real Postgres', () => {
  it('goes up: creates the tables, and the dealer column leads an index on users_tenants', async () => {
    // @ts-expect-error the test passes only what the migration reads (db)
    await up(args());
    expect(await tables()).toEqual([
      'dealers',
      'payload_kv',
      'payload_migrations',
      'payload_preferences',
      'payload_preferences_rels',
      'users',
      'users_sessions',
      'users_tenants',
    ]);
    const indexes = await names(
      `SELECT indexdef AS name FROM pg_indexes WHERE tablename = 'users_tenants'`,
    );
    expect(indexes.some((def) => /\(tenant_id, _parent_id\)/.test(def))).toBe(true);
  });

  it('keeps an email to one user, and ends a user together with their dealer rows and sessions', async () => {
    await pg.exec(`INSERT INTO dealers (id, name, slug) VALUES
      ('00000000-0000-0000-0000-00000000000a', 'Dealer A', 'a'),
      ('00000000-0000-0000-0000-00000000000b', 'Dealer B', 'b')`);
    await pg.exec(
      `INSERT INTO users (id, email) VALUES ('00000000-0000-0000-0000-000000000001', 'rep@a.example')`,
    );
    await expect(pg.exec(`INSERT INTO users (email) VALUES ('rep@a.example')`)).rejects.toThrow(
      /duplicate key/,
    );
    await expect(pg.exec(`INSERT INTO dealers (name, slug) VALUES ('Again', 'a')`)).rejects.toThrow(
      /duplicate key/,
    );
    await pg.exec(`INSERT INTO users_tenants (_order, _parent_id, id, tenant_id) VALUES
      (1, '00000000-0000-0000-0000-000000000001', 'row1', '00000000-0000-0000-0000-00000000000a')`);
    await pg.exec(`DELETE FROM users WHERE email = 'rep@a.example'`);
    const left = await pg.query(`SELECT 1 FROM users_tenants`);
    expect(left.rows).toHaveLength(0);
    await expect(
      pg.exec(`INSERT INTO users_tenants (_order, _parent_id, id, tenant_id) VALUES
        (1, '00000000-0000-0000-0000-0000000000ff', 'row2', '00000000-0000-0000-0000-00000000000a')`),
    ).rejects.toThrow(/foreign key/);
  });

  it('refuses to delete a dealer that still has staff (the NOT NULL dealer column is never set to null)', async () => {
    await pg.exec(
      `INSERT INTO users (id, email) VALUES ('00000000-0000-0000-0000-000000000002', 'bdc@b.example')`,
    );
    await pg.exec(`INSERT INTO users_tenants (_order, _parent_id, id, tenant_id) VALUES
      (1, '00000000-0000-0000-0000-000000000002', 'row3', '00000000-0000-0000-0000-00000000000b')`);
    await expect(
      pg.exec(`DELETE FROM dealers WHERE id = '00000000-0000-0000-0000-00000000000b'`),
    ).rejects.toThrow(/foreign key/);
    const kept = await pg.query(`SELECT tenant_id FROM users_tenants WHERE id = 'row3'`);
    expect(kept.rows).toEqual([{ tenant_id: '00000000-0000-0000-0000-00000000000b' }]);
    // A dealer with no staff left can go.
    await pg.exec(`DELETE FROM users WHERE id = '00000000-0000-0000-0000-000000000002'`);
    await pg.exec(`DELETE FROM dealers WHERE id = '00000000-0000-0000-0000-00000000000b'`);
    expect((await pg.query(`SELECT 1 FROM dealers WHERE slug = 'b'`)).rows).toHaveLength(0);
  });

  it('rejects a role that is not one of the four', async () => {
    await expect(
      pg.exec(`INSERT INTO users (email, role) VALUES ('x@a.example', 'root')`),
    ).rejects.toThrow(/invalid input value for enum/);
  });

  it('goes down: leaves no table and no type behind, and can go up again', async () => {
    // @ts-expect-error the test passes only what the migration reads (db)
    await down(args());
    expect(await tables()).toEqual([]);
    expect(
      await names(`SELECT typname AS name FROM pg_type WHERE typname = 'enum_users_role'`),
    ).toEqual([]);
    // @ts-expect-error the test passes only what the migration reads (db)
    await up(args());
    expect(await tables()).toHaveLength(8);
  });
});

describe('the migration list Payload runs', () => {
  it('holds the initial migration, in order', () => {
    expect(migrations.map((m) => m.name)).toEqual(['20261013_062316_initial']);
    expect(migrations[0]?.up).toBe(up);
    expect(migrations[0]?.down).toBe(down);
  });
});
