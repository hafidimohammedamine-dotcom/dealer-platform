import { colors } from './tokens.js';

// Badge tones are generic. Mapping a real lender answer or deal state to a tone
// waits for packages/contracts (LenderDecision), so no business states are invented here.
export const badgeTones = {
  success: { color: colors.success, background: colors.successBg },
  warning: { color: colors.warning, background: colors.warningBg },
  danger: { color: colors.danger, background: colors.dangerBg },
  info: { color: colors.info, background: colors.infoBg },
} as const;

export type BadgeTone = keyof typeof badgeTones;

/** A badge always has a word AND a symbol, never color alone. */
export function badge(
  tone: BadgeTone,
  label: string,
  symbol: string,
): { text: string; color: string; background: string } {
  if (label.trim() === '' || symbol.trim() === '') {
    throw new Error('Every badge needs a word and a symbol');
  }
  const t = badgeTones[tone];
  return { text: `${symbol} ${label}`, color: t.color, background: t.background };
}
