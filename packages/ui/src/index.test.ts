import { describe, expect, it } from 'vitest';
import {
  packageName,
  colors,
  cssVariables,
  formatMoney,
  formatPhone,
  formatDate,
  maskSensitive,
  statuses,
  statusBadge,
  buttonStyles,
  inputAttributes,
  emptyState,
  errorState,
  loadingState,
  tableModel,
} from './index.js';

function lum(hex: string): number {
  const c = [1, 3, 5].map((i) => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * c[0]! + 0.7152 * c[1]! + 0.0722 * c[2]!;
}
function contrast(a: string, b: string): number {
  const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x);
  return (hi! + 0.05) / (lo! + 0.05);
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
      [colors.onBrand, colors.brand],
      [colors.onBrand, colors.brandHover],
      [colors.onBrand, colors.danger],
      [colors.brand, colors.surface],
    ];
    for (const s of Object.values(statuses)) pairs.push([s.color, s.background]);
    for (const [fg, bg] of pairs) expect(contrast(fg, bg)).toBeGreaterThanOrEqual(4.5);
    // Borders and focus ring need 3:1.
    expect(contrast(colors.border, colors.surface)).toBeGreaterThanOrEqual(3);
    expect(contrast(colors.focus, colors.surface)).toBeGreaterThanOrEqual(3);
  });

  it('builds css variables', () => {
    const v = cssVariables();
    expect(v['--color-brand-hover']).toBe(colors.brandHover);
    expect(v['--space-md']).toBe('16px');
    expect(v['--tap-target']).toBe('44px');
    expect(v['--font-size-md']).toBe('16px');
    expect(v['--font-body']).toContain('system-ui');
  });

  it('formats money from cents', () => {
    expect(formatMoney(0)).toBe('$0.00');
    expect(formatMoney(5)).toBe('$0.05');
    expect(formatMoney(123456)).toBe('$1,234.56');
    expect(formatMoney(-2500000)).toBe('-$25,000.00');
    expect(() => formatMoney(10.5)).toThrow(RangeError);
  });

  it('formats phones', () => {
    expect(formatPhone('5551234567')).toBe('(555) 123-4567');
    expect(formatPhone('+1 555-123-4567')).toBe('(555) 123-4567');
    expect(formatPhone('123')).toBe('Phone not valid');
  });

  it('formats dates in the dealer time zone', () => {
    expect(formatDate('2026-10-12T02:00:00Z', 'America/Chicago')).toBe('Oct 11, 2026');
    expect(formatDate(new Date('2026-10-12T15:00:00Z'), 'America/Chicago')).toBe('Oct 12, 2026');
    expect(formatDate('nope', 'America/Chicago')).toBe('Date not valid');
  });

  it('masks sensitive values', () => {
    expect(maskSensitive('900-12-6789')).toBe('•••• 6789');
    expect(maskSensitive('12')).toBe('••••');
  });

  it('marks every status with a word and a symbol', () => {
    expect(Object.keys(statuses)).toEqual(['approved', 'countered', 'declined', 'waiting']);
    expect(statusBadge('declined').text).toBe('✕ Declined');
    expect(statusBadge('waiting').background).toBe(colors.infoBg);
  });

  it('keeps buttons tappable', () => {
    for (const b of Object.values(buttonStyles)) expect(b.minHeight).toBeGreaterThanOrEqual(44);
  });

  it('requires input labels', () => {
    expect(inputAttributes({ id: 'a', label: 'Name' })).toMatchObject({
      labelFor: 'a',
      invalid: false,
      describedBy: undefined,
    });
    expect(inputAttributes({ id: 'a', label: 'Name', error: 'Enter a name' })).toMatchObject({
      invalid: true,
      describedBy: 'a-message',
      message: 'Enter a name',
    });
    expect(inputAttributes({ id: 'a', label: 'Name', hint: 'As on license' }).message).toBe(
      'As on license',
    );
    expect(() => inputAttributes({ id: 'a', label: ' ' })).toThrow();
  });

  it('writes plain empty, error and loading states', () => {
    expect(emptyState('leads', 'Add a lead').action).toBe('Add a lead');
    expect(errorState('deals').action).toBe('Try again');
    expect(loadingState('deals').title).toBe('Loading deals');
  });

  it('builds tables', () => {
    const t = tableModel('Deals', [{ key: 'a', label: 'A' }], []);
    expect(t.empty).toBe(true);
    expect(tableModel('Deals', [{ key: 'a', label: 'A' }], [{ a: '1' }]).empty).toBe(false);
    expect(() => tableModel('', [], [])).toThrow();
  });
});
