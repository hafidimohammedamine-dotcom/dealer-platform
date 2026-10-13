import { describe, expect, it } from 'vitest';
import { badge, badgeTones, colors, isBadgeTone } from './index.js';

describe('status badges', () => {
  it('marks every badge with a word and a symbol', () => {
    expect(Object.keys(badgeTones)).toEqual(['success', 'warning', 'danger', 'info']);
    expect(badge('danger', 'Declined', '✕').text).toBe('✕ Declined');
    expect(badge('info', 'Waiting', '…').background).toBe(colors.infoBg);
    expect(badge('success', 'Done', '✓').color).toBe(colors.success);
    expect(() => badge('success', '', '✓')).toThrow();
    expect(() => badge('success', 'Done', ' ')).toThrow();
  });

  it('tells a real tone from any other text', () => {
    for (const tone of Object.keys(badgeTones)) expect(isBadgeTone(tone)).toBe(true);
    expect(isBadgeTone('info')).toBe(true);
    expect(isBadgeTone('purple')).toBe(false);
    expect(isBadgeTone('toString')).toBe(false);
    expect(isBadgeTone('__proto__')).toBe(false);
    expect(isBadgeTone('')).toBe(false);
    expect(isBadgeTone('Info')).toBe(false);
  });
});
