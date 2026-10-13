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
