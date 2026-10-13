import { colors } from './tokens.js';

// Lender answers and deal states. Every status has a word AND a symbol, never color alone.
export const statuses = {
  approved: { label: 'Approved', symbol: '✓', color: colors.success, background: colors.successBg },
  countered: {
    label: 'Countered',
    symbol: '↔',
    color: colors.warning,
    background: colors.warningBg,
  },
  declined: { label: 'Declined', symbol: '✕', color: colors.danger, background: colors.dangerBg },
  waiting: { label: 'Waiting', symbol: '…', color: colors.info, background: colors.infoBg },
} as const;

export type Status = keyof typeof statuses;

export function statusBadge(status: Status): { text: string; color: string; background: string } {
  const s = statuses[status];
  return { text: `${s.symbol} ${s.label}`, color: s.color, background: s.background };
}
