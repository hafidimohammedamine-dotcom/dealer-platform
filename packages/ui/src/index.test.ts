import { describe, expect, it } from 'vitest';
import {
  packageName,
  colors,
  fontSizes,
  breakpoints,
  focusRing,
  cssVariables,
  formatMoney,
  formatPhone,
  formatDate,
  maskLast4,
  maskDob,
  maskIncome,
  badgeTones,
  badge,
  buttonStyles,
  inputStyles,
  inputAttributes,
  emptyState,
  errorState,
  loadingState,
  tableModel,
  tableStyles,
  missingValue,
} from './index.js';

function lum(hex: string): number {
  const [r = 0, g = 0, b = 0] = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a: string, b: string): number {
  const [hi = 0, lo = 0] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

describe('@dealer/ui', () => {
  it('exposes its package name', () => {
    expect(packageName).toBe('@dealer/ui');
  });

  it('meets AA contrast for text pairs', () => {
    const pairs: [string, string][] = [
      [colors.text, colors.surface],
      [colors.textMuted, colors.surface],
      [colors.textMuted, colors.surfaceAlt],
      [colors.danger, colors.surface],
      [colors.danger, colors.surfaceAlt],
    ];
    for (const b of Object.values(buttonStyles)) {
      for (const look of [b, b.hover, b.disabled]) pairs.push([look.color, look.background]);
    }
    for (const t of Object.values(badgeTones)) pairs.push([t.color, t.background]);
    for (const [fg, bg] of pairs) expect(contrast(fg, bg)).toBeGreaterThanOrEqual(4.5);
  });

  it('meets 3:1 for borders and focus ring on every surface', () => {
    for (const bg of [colors.surface, colors.surfaceAlt]) {
      expect(contrast(colors.border, bg)).toBeGreaterThanOrEqual(3);
      expect(contrast(colors.focus, bg)).toBeGreaterThanOrEqual(3);
    }
    for (const b of Object.values(buttonStyles)) {
      expect(contrast(b.border, colors.surface)).toBeGreaterThanOrEqual(3);
      expect(contrast(b.hover.border, colors.surface)).toBeGreaterThanOrEqual(3);
    }
  });

  it('builds css variables with kebab-case names for every token', () => {
    const v = cssVariables();
    expect(v['--color-brand-hover']).toBe(colors.brandHover);
    expect(v['--color-surface-alt']).toBe(colors.surfaceAlt);
    expect(v['--color-danger-bg']).toBe(colors.dangerBg);
    for (const [k, value] of Object.entries(colors)) {
      const name = `--color-${k.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`)}`;
      expect(v[name]).toBe(value);
    }
    expect(v['--space-md']).toBe('16px');
    expect(v['--tap-target']).toBe('44px');
    expect(v['--font-body']).toContain('system-ui');
    expect(v['--focus-ring']).toBe(focusRing.outline);
    expect(v['--focus-ring-offset']).toBe('2px');
  });

  it('keeps font sizes and breakpoints phone first', () => {
    expect(fontSizes.md).toBe(16);
    expect(fontSizes.sm).toBeLessThan(fontSizes.md);
    expect(fontSizes.lg).toBeGreaterThan(fontSizes.md);
    expect(fontSizes.xl).toBeGreaterThan(fontSizes.lg);
    expect(breakpoints.phone).toBe(375);
    expect(breakpoints.phone).toBeLessThan(breakpoints.tablet);
    expect(breakpoints.tablet).toBeLessThan(breakpoints.desktop);
    const v = cssVariables();
    expect(v['--font-size-xl']).toBe('28px');
    expect(v['--breakpoint-tablet']).toBe('768px');
  });

  it('has a visible focus ring', () => {
    expect(focusRing.outline).toBe(`3px solid ${colors.focus}`);
    expect(focusRing.outlineOffset).toBe('2px');
    for (const b of Object.values(buttonStyles)) expect(b.focus).toBe(focusRing);
    expect(inputStyles.focus).toBe(focusRing);
    expect(tableStyles.focus).toBe(focusRing);
  });

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
    expect(formatPhone('5551234567')).toBe('(555) 123-4567');
    expect(formatPhone('+1 555-123-4567')).toBe('(555) 123-4567');
    expect(formatPhone('(555) 123-4567')).toBe('(555) 123-4567');
    expect(formatPhone('123')).toBe('Phone not valid');
  });

  it('rejects phones that are not real US numbers', () => {
    const bad = [
      '',
      '   ',
      'call me',
      '555-CALL-NOW',
      '25551234567', // 11 digits, not starting with 1
      '0551234567', // area code starts with 0
      '1551234567', // area code starts with 1
      '5551234567 ext 89', // extension
      '555123456789', // 12 digits
      '55512345678901234567890',
      '５５５１２３４５６７', // full-width digits
      '😀'.repeat(50),
    ];
    for (const b of bad) expect(formatPhone(b)).toBe('Phone not valid');
    expect(formatPhone('1' + '5551234567')).toBe('(555) 123-4567');
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

  it('marks every badge with a word and a symbol', () => {
    expect(Object.keys(badgeTones)).toEqual(['success', 'warning', 'danger', 'info']);
    expect(badge('danger', 'Declined', '✕').text).toBe('✕ Declined');
    expect(badge('info', 'Waiting', '…').background).toBe(colors.infoBg);
    expect(badge('success', 'Done', '✓').color).toBe(colors.success);
    expect(() => badge('success', '', '✓')).toThrow();
    expect(() => badge('success', 'Done', ' ')).toThrow();
  });

  it('keeps buttons tappable and shows all their states', () => {
    for (const b of Object.values(buttonStyles)) expect(b.minHeight).toBeGreaterThanOrEqual(44);
    expect(buttonStyles.secondary.background).toBe(colors.surface);
    expect(buttonStyles.secondary.hover.background).toBe(colors.surfaceAlt);
    expect(buttonStyles.danger.background).toBe(colors.danger);
    expect(buttonStyles.danger.hover.background).toBe(colors.dangerHover);
    expect(buttonStyles.primary.hover.background).toBe(colors.brandHover);
    expect(buttonStyles.danger.disabled.color).toBe(colors.textMuted);
  });

  it('requires input labels and ids', () => {
    expect(inputAttributes({ id: 'a', label: 'Name' })).toMatchObject({
      labelFor: 'a',
      invalid: false,
      describedBy: undefined,
      messagePrefix: '',
    });
    expect(inputAttributes({ id: 'a', label: 'Name', error: 'Enter a name' })).toMatchObject({
      invalid: true,
      describedBy: 'a-message',
      message: 'Enter a name',
      messagePrefix: '⚠ ',
    });
    expect(inputAttributes({ id: 'a', label: 'Name', hint: 'As on license' }).message).toBe(
      'As on license',
    );
    expect(() => inputAttributes({ id: 'a', label: ' ' })).toThrow();
    expect(() => inputAttributes({ id: '', label: 'Name' })).toThrow();
    expect(() => inputAttributes({ id: '  ', label: 'Name' })).toThrow();
  });

  it('lets an error win over a hint and ignores an empty error', () => {
    const both = inputAttributes({ id: 'a', label: 'Name', error: 'Enter a name', hint: 'Hint' });
    expect(both.message).toBe('Enter a name');
    expect(both.invalid).toBe(true);
    const empty = inputAttributes({ id: 'a', label: 'Name', error: '', hint: 'Hint' });
    expect(empty.invalid).toBe(false);
    expect(empty.message).toBe('Hint');
    const blank = inputAttributes({ id: 'a', label: 'Name', error: '   ' });
    expect(blank.invalid).toBe(false);
    expect(blank.describedBy).toBeUndefined();
  });

  it('marks invalid inputs by more than color', () => {
    expect(inputStyles.invalid.border).toContain('3px');
    expect(inputStyles.border).toContain('1px');
    expect(contrast(inputStyles.invalid.messageColor, colors.surface)).toBeGreaterThanOrEqual(4.5);
  });

  it('writes plain empty, error and loading states', () => {
    expect(emptyState('leads', 'Add a lead').action).toBe('Add a lead');
    expect(errorState('deals').action).toBe('Try again');
    expect(loadingState('deals').title).toBe('Loading deals');
  });

  it('has no button on the loading state', () => {
    const s = loadingState('deals');
    expect('action' in s).toBe(false);
    expect(s.action).toBeUndefined();
  });

  it('does not say work is safe when a save fails', () => {
    const load = errorState('deals');
    expect(load.title).toBe('We could not load deals');
    expect(load.message).toBe('Check your connection and try again.');
    const save = errorState('this deal', 'save');
    expect(save.title).toBe('We could not save this deal');
    expect(save.message).toBe(
      'Your changes were not saved. Try again before you leave this screen.',
    );
    expect(save.message).not.toMatch(/safe/i);
    expect(load.message).not.toMatch(/safe/i);
  });

  it('rejects empty words and copes with long or unicode ones', () => {
    expect(() => emptyState('', 'Add')).toThrow();
    expect(() => emptyState('leads', '  ')).toThrow();
    expect(() => errorState('')).toThrow();
    expect(() => loadingState(' ')).toThrow();
    const long = 'x'.repeat(5000);
    expect(emptyState(long, 'Add').title).toBe(`No ${long} yet`);
    expect(errorState(long).title).toBe(`We could not load ${long}`);
    expect(loadingState('clients 🚗').title).toBe('Loading clients 🚗');
    expect(emptyState('véhicules', 'Ajouter').action).toBe('Ajouter');
  });

  it('builds tables', () => {
    const t = tableModel('Deals', [{ key: 'a', label: 'A' }], []);
    expect(t.empty).toBe(true);
    expect(tableModel('Deals', [{ key: 'a', label: 'A' }], [{ a: '1' }]).empty).toBe(false);
    expect(() => tableModel('', [], [])).toThrow();
    expect(() => tableModel('  ', [], [])).toThrow();
  });

  it('fills gaps in rows and rejects duplicate column keys', () => {
    const cols = [
      { key: 'a', label: 'A' },
      { key: 'b', label: 'B', numeric: true },
    ];
    const t = tableModel('Deals', cols, [{ a: '1' }, { b: '2', extra: 'x' }]);
    expect(t.rows).toEqual([
      { a: '1', b: missingValue },
      { a: missingValue, b: '2' },
    ]);
    expect(() => tableModel('Deals', [...cols, { key: 'a', label: 'Again' }], [])).toThrow(
      /share the key/,
    );
    expect(tableStyles.cardsBelow).toBe(breakpoints.tablet);
  });
});
