import { describe, expect, it } from 'vitest';
import {
  colors,
  fontSizes,
  breakpoints,
  focusRing,
  cssVariables,
  buttonStyles,
  inputStyles,
  tableStyles,
  badgeTones,
} from './index.js';
import { contrast } from './test-helpers/contrast.js';

describe('tokens', () => {
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
    for (const bg of [colors.surface, colors.surfaceAlt]) {
      expect(contrast(buttonStyles.primary.disabled.border, bg)).toBeGreaterThanOrEqual(3);
    }
    expect(contrast(colors.border, colors.surface)).toBeGreaterThanOrEqual(3);
    expect(inputStyles.border).toBe(`1px solid ${colors.border}`);
    expect(inputStyles.invalid.border).toBe(`3px solid ${colors.danger}`);
    expect(contrast(colors.danger, colors.surface)).toBeGreaterThanOrEqual(3);
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
});
