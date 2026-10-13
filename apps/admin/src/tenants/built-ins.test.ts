import { describe, expect, it } from 'vitest';
import { denyAll } from '../access/roles.js';
import { lockBuiltInCollections, MIGRATIONS_SLUG } from './built-ins.js';

const open = () => true;

describe('lockBuiltInCollections', () => {
  it('closes payload-migrations and touches nothing else', () => {
    const migrations = {
      slug: MIGRATIONS_SLUG,
      access: { create: open, read: open, update: open, delete: open, unlock: open },
    };
    const other = { slug: 'users', access: { read: open } };
    lockBuiltInCollections({ collections: [other, migrations] });
    expect(migrations.access).toEqual({
      create: denyAll,
      read: denyAll,
      update: denyAll,
      delete: denyAll,
      unlock: open,
    });
    expect(other.access).toEqual({ read: open });
  });

  it('does nothing when the collection is not there', () => {
    const list = [{ slug: 'users', access: {} }];
    lockBuiltInCollections({ collections: list });
    expect(list).toEqual([{ slug: 'users', access: {} }]);
  });
});
