import { describe, expect, it } from 'vitest';
import { badgeTones, badge, colors } from './index.js';

describe('status badges', () => {
  it('marks every badge with a word and a symbol', () => {
    expect(Object.keys(badgeTones)).toEqual(['success', 'warning', 'danger', 'info']);
    expect(badge('danger', 'Declined', '✕').text).toBe('✕ Declined');
    expect(badge('info', 'Waiting', '…').background).toBe(colors.infoBg);
    expect(badge('success', 'Done', '✓').color).toBe(colors.success);
    expect(() => badge('success', '', '✓')).toThrow();
    expect(() => badge('success', 'Done', ' ')).toThrow();
  });

  it('rejects a blank word or symbol with a plain message', () => {
    expect(() => badge('info', '   ', '…')).toThrow('Every badge needs a word and a symbol');
  });
});
