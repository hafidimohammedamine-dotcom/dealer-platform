import { present, requireText } from './text.js';
import { breakpoints, colors, focusRing, minTapTarget, radii, spacing } from './tokens.js';

// Style and wording rules shared by buttons, inputs, tables and screens.

export type ButtonKind = 'primary' | 'secondary' | 'danger';

interface ButtonLook {
  color: string;
  background: string;
  border: string;
}

export interface ButtonStyle extends ButtonLook {
  minHeight: number;
  hover: ButtonLook;
  /** Disabled buttons stay readable and say why in text next to them. */
  disabled: ButtonLook;
  focus: typeof focusRing;
}

const disabledLook: ButtonLook = {
  color: colors.textMuted,
  background: colors.surfaceAlt,
  border: colors.textMuted,
};

/** Only one primary button per view. Every button is at least 44px tall. */
export const buttonStyles: Record<ButtonKind, ButtonStyle> = {
  primary: {
    color: colors.onBrand,
    background: colors.brand,
    border: colors.brand,
    minHeight: minTapTarget,
    hover: { color: colors.onBrand, background: colors.brandHover, border: colors.brandHover },
    disabled: disabledLook,
    focus: focusRing,
  },
  secondary: {
    color: colors.brand,
    background: colors.surface,
    border: colors.brand,
    minHeight: minTapTarget,
    hover: { color: colors.brandHover, background: colors.surfaceAlt, border: colors.brandHover },
    disabled: disabledLook,
    focus: focusRing,
  },
  danger: {
    color: colors.onBrand,
    background: colors.danger,
    border: colors.danger,
    minHeight: minTapTarget,
    hover: { color: colors.onBrand, background: colors.dangerHover, border: colors.dangerHover },
    disabled: disabledLook,
    focus: focusRing,
  },
};

/** Inputs: a clear focus ring, and an error shows a thick border AND a warning mark with words, not color alone. */
export const inputStyles = {
  color: colors.text,
  background: colors.surface,
  border: `1px solid ${colors.border}`,
  minHeight: minTapTarget,
  focus: focusRing,
  invalid: { border: `3px solid ${colors.danger}`, messageColor: colors.danger },
} as const;

export interface InputProps {
  id: string;
  label: string;
  error?: string;
  hint?: string;
}

/** Every input needs a visible label. Errors say what to do and win over hints. Returns the attributes for the field. */
export function inputAttributes(p: InputProps): {
  id: string;
  labelFor: string;
  label: string;
  describedBy: string | undefined;
  invalid: boolean;
  message: string | undefined;
  messagePrefix: string;
} {
  requireText(p.id, 'Every input needs an id, and it');
  requireText(p.label, 'Every input needs a label, and it');
  const error = present(p.error);
  const message = error ?? present(p.hint);
  return {
    id: p.id,
    labelFor: p.id,
    label: p.label,
    describedBy: message === undefined ? undefined : `${p.id}-message`,
    invalid: error !== undefined,
    message,
    messagePrefix: error === undefined ? '' : '⚠ ',
  };
}

export interface ScreenState {
  title: string;
  message: string;
  /** Button text. Left out when there is nothing to press. */
  action?: string;
}

/** Empty state: say what is missing and what to do next. */
export function emptyState(thing: string, action: string): ScreenState {
  requireText(thing, 'What is missing');
  requireText(action, 'The next step');
  return {
    title: `No ${thing} yet`,
    message: `There are no ${thing} to show. To start, press "${action}".`,
    action,
  };
}

/** Error state: plain words, never error codes. A failed save must not claim the work is safe. */
export function errorState(what: string, kind: 'load' | 'save' = 'load'): ScreenState {
  requireText(what, 'What failed');
  if (kind === 'save') {
    return {
      title: `We could not save ${what}`,
      message: 'Your changes were not saved. Try again before you leave this screen.',
      action: 'Try again',
    };
  }
  return {
    title: `We could not load ${what}`,
    message: 'Check your connection and try again.',
    action: 'Try again',
  };
}

/** Loading state. Nothing to press. */
export function loadingState(what: string): ScreenState {
  requireText(what, 'What is loading');
  return { title: `Loading ${what}`, message: 'One moment.' };
}

export interface TableColumn {
  key: string;
  label: string;
  /** Right-align numbers and money. */
  numeric?: boolean;
}

/** Tables scroll inside their own box on a phone only if they must, show a focus ring, and become cards below the tablet width. */
export const tableStyles = {
  headerColor: colors.text,
  headerBackground: colors.surfaceAlt,
  borderColor: colors.border,
  /** Every row has a line under it. */
  rowBorder: `1px solid ${colors.border}`,
  cellPadding: `${spacing.sm}px ${spacing.md}px`,
  /** Numbers and money line up on the right, with equal-width digits. */
  numeric: { textAlign: 'right', fontVariantNumeric: 'tabular-nums' },
  text: { textAlign: 'left', fontVariantNumeric: 'normal' },
  /** Below this width each row is a card, with the column label beside each value. */
  cardsBelow: breakpoints.tablet,
  card: {
    padding: `${spacing.md}px`,
    gap: `${spacing.sm}px`,
    radius: `${radii.md}px`,
    border: `1px solid ${colors.border}`,
    background: colors.surface,
  },
  focus: focusRing,
} as const;

/** The alignment for one column: numbers and money on the right, everything else on the left. */
export function columnStyle(
  column: TableColumn,
): typeof tableStyles.numeric | typeof tableStyles.text {
  return column.numeric === true ? tableStyles.numeric : tableStyles.text;
}

/** Shown for a value a row does not have, or has as empty or blank text, so a gap is never blank. */
export const missingValue = '—';

/** Keys that could change an object's prototype instead of making a cell. */
const unsafeKeys = new Set(['__proto__', 'constructor', 'prototype']);

/**
 * Tables need a caption and column labels. On a phone each row becomes a card with the label beside each value.
 * Cells are text the caller has already formatted (for example with formatMoney or formatDate).
 */
export function tableModel(
  caption: string,
  columns: TableColumn[],
  rows: readonly Readonly<Record<string, string | undefined>>[],
): { caption: string; columns: TableColumn[]; rows: Record<string, string>[]; empty: boolean } {
  requireText(caption, 'Every table needs a caption, and it');
  const keys = new Set<string>();
  for (const c of columns) {
    if (unsafeKeys.has(c.key)) throw new Error(`"${c.key}" cannot be used as a column key`);
    if (keys.has(c.key)) throw new Error(`Two columns share the key "${c.key}"`);
    keys.add(c.key);
  }
  const filled = rows.map((row) =>
    Object.fromEntries(
      columns.map((c) => {
        const cell = Object.hasOwn(row, c.key) ? row[c.key] : undefined;
        return [c.key, present(cell) ?? missingValue];
      }),
    ),
  );
  return { caption, columns, rows: filled, empty: rows.length === 0 };
}
