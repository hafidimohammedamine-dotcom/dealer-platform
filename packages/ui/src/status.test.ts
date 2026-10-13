import { describe, expect, it } from 'vitest';
import { badge, badgeTones, colors, type BadgeTone } from './index.js';

describe('status badges', () => {
  it('marks every badge with a word and a symbol', () => {
    expect(Object.keys(badgeTones)).toEqual(['success', 'warning', 'danger', 'info']);
    expect(badge('danger', 'Declined', '✕').text).toBe('✕ Declined');
    expect(badge('info', 'Waiting', '…').background).toBe(colors.infoBg);
    expect(badge('success', 'Done', '✓').color).toBe(colors.success);
    expect(() => badge('success', '', '✓')).toThrow();
    expect(() => badge('success', 'Done', ' ')).toThrow();
  });

  it('says in plain words when the color is not one we have', () => {
    const bad: BadgeTone = JSON.parse('"purple"');
    const badTone: BadgeTone = JSON.parse('"toString"');
    expect(() => badge(bad, 'Done', '✓')).toThrow(/not a badge color/);
    expect(() => badge(badTone, 'Done', '✓')).toThrow(/not a badge color/);
  });
});
