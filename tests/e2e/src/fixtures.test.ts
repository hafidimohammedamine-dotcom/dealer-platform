import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

interface Dealer {
  id: string;
  staff: { id: string; email: string }[];
  inventory: { id: string; vin: string; priceCents: number }[];
  customers: { id: string; phone: string; ssn: string; assignedStaffId: string }[];
}

const parsed: { dealers: Dealer[] } = JSON.parse(
  readFileSync(new URL('../../../fixtures/dealers.json', import.meta.url), 'utf8'),
);
const { dealers } = parsed;

function ids(d: Dealer): string[] {
  return [
    d.id,
    ...d.staff.map((s) => s.id),
    ...d.inventory.map((v) => v.id),
    ...d.customers.map((c) => c.id),
  ];
}

describe('fixtures/dealers.json', () => {
  it('has two dealers, each with staff, inventory and customers', () => {
    expect(dealers).toHaveLength(2);
    for (const d of dealers) {
      expect(d.staff.length).toBeGreaterThan(0);
      expect(d.inventory.length).toBeGreaterThan(0);
      expect(d.customers.length).toBeGreaterThan(0);
    }
  });

  it('shares no id between the two dealers', () => {
    const all = dealers.flatMap(ids);
    expect(new Set(all).size).toBe(all.length);
  });

  it('uses only fake SSNs (900-xx-xxxx) and example.test emails', () => {
    for (const d of dealers) {
      for (const c of d.customers) expect(c.ssn).toMatch(/^900-\d{2}-\d{4}$/);
      for (const s of d.staff) expect(s.email).toMatch(/@[a-z0-9-]+\.example\.test$/);
    }
  });

  it('keeps every customer on a rep of the same dealer, with a valid phone and a whole-cent price', () => {
    for (const d of dealers) {
      const staffIds = d.staff.map((s) => s.id);
      for (const c of d.customers) {
        expect(staffIds).toContain(c.assignedStaffId);
        expect(c.phone).toMatch(/^\+1\d{10}$/);
      }
      for (const v of d.inventory) {
        expect(Number.isInteger(v.priceCents)).toBe(true);
        expect(v.vin).toMatch(/^[A-Z0-9]{17}$/);
      }
    }
  });
});
