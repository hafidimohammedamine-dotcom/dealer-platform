import { colors, minTapTarget } from './tokens.js';

// Style and wording rules shared by buttons, inputs, tables and screens.

export type ButtonKind = 'primary' | 'secondary' | 'danger';

/** Only one primary button per view. Every button is at least 44px tall. */
export const buttonStyles: Record<
  ButtonKind,
  { color: string; background: string; border: string; minHeight: number }
> = {
  primary: {
    color: colors.onBrand,
    background: colors.brand,
    border: colors.brand,
    minHeight: minTapTarget,
  },
  secondary: {
    color: colors.brand,
    background: colors.surface,
    border: colors.brand,
    minHeight: minTapTarget,
  },
  danger: {
    color: colors.onBrand,
    background: colors.danger,
    border: colors.danger,
    minHeight: minTapTarget,
  },
};

export interface InputProps {
  id: string;
  label: string;
  error?: string;
  hint?: string;
}

/** Every input needs a visible label. Errors say what to do. Returns the attributes for the field. */
export function inputAttributes(p: InputProps): {
  id: string;
  labelFor: string;
  label: string;
  describedBy: string | undefined;
  invalid: boolean;
  message: string | undefined;
} {
  if (p.label.trim() === '') throw new Error('Every input needs a label');
  const message = p.error ?? p.hint;
  return {
    id: p.id,
    labelFor: p.id,
    label: p.label,
    describedBy: message === undefined ? undefined : `${p.id}-message`,
    invalid: p.error !== undefined,
    message,
  };
}

export interface ScreenState {
  title: string;
  message: string;
  action: string;
}

/** Empty state: say what is missing and what to do next. */
export function emptyState(thing: string, action: string): ScreenState {
  return { title: `No ${thing} yet`, message: `There are no ${thing} to show.`, action };
}

/** Error state: plain words, never error codes. */
export function errorState(what: string): ScreenState {
  return {
    title: `We could not load ${what}`,
    message: 'Your work is safe. Check your connection and try again.',
    action: 'Try again',
  };
}

/** Loading state. */
export function loadingState(what: string): ScreenState {
  return { title: `Loading ${what}`, message: 'One moment.', action: '' };
}

export interface TableColumn {
  key: string;
  label: string;
  /** Right-align numbers and money. */
  numeric?: boolean;
}

/** Tables need a caption and column labels. On a phone each row becomes a card with the label beside each value. */
export function tableModel(
  caption: string,
  columns: TableColumn[],
  rows: Record<string, string>[],
): { caption: string; columns: TableColumn[]; rows: Record<string, string>[]; empty: boolean } {
  if (caption.trim() === '') throw new Error('Every table needs a caption');
  return { caption, columns, rows, empty: rows.length === 0 };
}
