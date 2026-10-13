import { describe, expect, it } from 'vitest';
import { formatMoney, formatPhone, formatDate, maskLast4, maskDob, maskIncome } from './index.js';

describe('formatters', () => {
  it('formats money from cents', () => {
    expect(formatMoney(0)).toBe('$0.00');
    expect(formatMoney(-0)).toBe('$0.00');
    expect(formatMoney(5)).toBe('$0.05');
    expect(formatMoney(-5)).toBe('-$0.05');
    expect(formatMoney(123456)).toBe('$1,234.56');
    expect(formatMoney(-2500000)).toBe('-$25,000.00');
    expect(formatMoney(Number.MAX_SAFE_INTEGER)).toBe('$90,071,992,547,409.91');
    expect(() => formatMoney(10.5)).toThrow(RangeError);
    expect(() => formatMoney(NaN)).toThrow(RangeError);
    expect(() => formatMoney(Infinity)).toThrow(RangeError);
    expect(() => formatMoney(-Infinity)).toThrow(RangeError);
    expect(() => formatMoney(Number.MAX_SAFE_INTEGER + 2)).toThrow(RangeError);
  });

  it('formats phones', () => {
    expect(formatPhone('5552345678')).toBe('(555) 234-5678');
    expect(formatPhone('+1 555-234-5678')).toBe('(555) 234-5678');
    expect(formatPhone('(555) 234-5678')).toBe('(555) 234-5678');
    expect(formatPhone('5552345678abc')).toBe('(555) 234-5678');
    expect(formatPhone('123')).toBe('Phone not valid');
  });

  it('rejects phones that are not real US numbers', () => {
    const bad = [
      '',
      '   ',
      'call me',
      '555-CALL-NOW',
      '25552345678', // 11 digits, not starting with 1
      '0551234567', // area code starts with 0
      '1551234567', // area code starts with 1
      '5550234567', // exchange starts with 0
      '5551034567', // exchange starts with 1
      '5552345678 ext 89', // extension
      '555234567889', // 12 digits
      '55523456788901234567890',
      '５５５１２３４５６７', // full-width digits
      '😀'.repeat(50),
    ];
    for (const b of bad) expect(formatPhone(b)).toBe('Phone not valid');
    expect(formatPhone('1' + '5552345678')).toBe('(555) 234-5678');
  });

  it('formats dates in the dealer time zone', () => {
    expect(formatDate('2026-10-12T02:00:00Z', 'America/Chicago')).toBe('Oct 11, 2026');
    expect(formatDate(new Date('2026-10-12T15:00:00Z'), 'America/Chicago')).toBe('Oct 12, 2026');
    expect(formatDate('nope', 'America/Chicago')).toBe('Date not valid');
    expect(formatDate('2026-10-12T02:00:00-05:00', 'America/Chicago')).toBe('Oct 12, 2026');
    expect(formatDate('2026-10-12T02:00:00+0000', 'UTC')).toBe('Oct 12, 2026');
  });

  it('shows a date with no time as the same calendar day in every time zone', () => {
    for (const zone of ['America/Chicago', 'Pacific/Honolulu', 'Pacific/Kiritimati', 'UTC']) {
      expect(formatDate('2026-10-12', zone)).toBe('Oct 12, 2026');
    }
    expect(formatDate('2026-02-31', 'UTC')).toBe('Date not valid');
    expect(formatDate('2026-13-01', 'UTC')).toBe('Date not valid');
  });

  it('does not break the screen on a bad time zone', () => {
    expect(formatDate('2026-10-12T15:00:00Z', '')).toBe('Date not valid');
    expect(formatDate('2026-10-12T15:00:00Z', 'Not/AZone')).toBe('Date not valid');
    expect(formatDate(new Date('2026-10-12T15:00:00Z'), 'nonsense')).toBe('Date not valid');
    expect(formatDate(new Date(NaN), 'UTC')).toBe('Date not valid');
    expect(formatDate('', 'UTC')).toBe('Date not valid');
  });

  it('refuses a time with no zone, because each machine would read it differently', () => {
    expect(formatDate('2026-10-12T02:00:00', 'America/Chicago')).toBe('Date not valid');
    expect(formatDate('2026-10-12T02:00', 'UTC')).toBe('Date not valid');
    expect(formatDate('Oct-12-2026', 'UTC')).toBe('Date not valid');
  });

  it('reads every accepted form of a moment in time', () => {
    const ok = [
      '2026-10-12T15:00Z',
      '2026-10-12T15:00:59Z',
      '2026-10-12T15:00:00.1Z',
      '2026-10-12T15:00:00.123456789Z',
      '2026-10-12T10:00+05:00',
      '2026-10-12T10:00:00-0500',
      '2026-10-12T00:00+00:00',
      '2026-10-12T23:59:59.999+23:59',
      '2026-10-12T15:00:00.123456789+05:00', // 35 characters, the longest form
    ];
    for (const s of ok) expect(formatDate(s, 'UTC')).toBe('Oct 12, 2026');
  });

  it('refuses any other text, a day not on the calendar and an hour past 23', () => {
    const bad = [
      'Oct-12-2026T02:00Z',
      'x2026-10-12T02:00Z',
      '2026-10-12T02:00Zx',
      '2026-10-12 02:00Z', // space instead of T
      '2026-10-12t02:00z', // lower case
      '2026-10-12T02:00+05', // offset without minutes
      '2026-10-12T2:00Z',
      '2026-10-12T02:00:00.1234567890Z', // more than 9 fraction digits
      '2026-02-31T00:00Z', // not a day, would roll into March
      '2026-13-01T00:00Z',
      '2026-10-12T24:00Z', // would roll into the next day
      '2026-10-12T02:60Z',
      '2026-10-12T02:00:60Z',
      '2026-10-12T02:00+24:00',
      '+002026-10-12T02:00Z',
      '２０２６-10-12T02:00Z', // full-width digits
    ];
    for (const s of bad) expect(formatDate(s, 'UTC')).toBe('Date not valid');
  });

  it('refuses long text without reading it, so a crafted value cannot stall the server', () => {
    const started = Date.now();
    expect(formatDate('T00:00'.repeat(10000), 'UTC')).toBe('Date not valid');
    expect(formatDate(`2026-10-12T02:00${'0'.repeat(10000)}Z`, 'UTC')).toBe('Date not valid');
    expect(formatDate('2026-10-12'.repeat(5000), 'UTC')).toBe('Date not valid');
    expect(formatDate(`2026-10-12T02:00:00.123456789+05:00${' '.repeat(6)}`, 'UTC')).toBe(
      'Date not valid',
    );
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it('checks the time zone even for a date with no time', () => {
    expect(formatDate('2026-10-12', 'Not/AZone')).toBe('Date not valid');
    expect(formatDate('2026-10-12', '')).toBe('Date not valid');
  });

  it('masks the last 4 digits only', () => {
    expect(maskLast4('6789')).toBe('•••• 6789');
    expect(maskLast4('0000')).toBe('•••• 0000');
  });

  it('refuses anything that is not exactly 4 digits', () => {
    const bad = [
      '',
      '    ',
      '12',
      '123',
      '12345',
      '900-12-6789', // a full SSN must never be passed
      '900126789',
      '----',
      '12 4',
      'abcd',
      '１２３４', // full-width digits
      '🙂🙂🙂🙂',
      '1234\n',
      '9'.repeat(500),
    ];
    for (const b of bad) expect(() => maskLast4(b)).toThrow(RangeError);
  });

  it('shows nothing for date of birth and income', () => {
    expect(maskDob()).toBe('••••');
    expect(maskIncome()).toBe('••••');
    expect(maskDob()).not.toMatch(/\d/);
    expect(maskIncome()).not.toMatch(/\d/);
  });
});
