import { describe, expect, it } from 'vitest';
import {
  colors,
  buttonStyles,
  inputStyles,
  inputAttributes,
  emptyState,
  errorState,
  loadingState,
  tableModel,
  tableStyles,
  missingValue,
  breakpoints,
  columnStyle,
  spacing,
} from './index.js';
import { contrast } from './test-helpers/contrast.js';

describe('components', () => {
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
    const blankHint = inputAttributes({ id: 'a', label: 'Name', hint: '   ' });
    expect(blankHint.message).toBeUndefined();
    expect(blankHint.describedBy).toBeUndefined();
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
    const empty = emptyState('leads', 'Add a lead');
    expect(empty.action).toBe('Add a lead');
    expect(empty.message).toBe('There are no leads to show. To start, press "Add a lead".');
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

  it('shows a dash, not a built-in function, for a missing cell', () => {
    const cols = [
      { key: 'toString', label: 'T' },
      { key: 'hasOwnProperty', label: 'H' },
    ];
    const t = tableModel('Deals', cols, [{}]);
    expect(t.rows[0]?.toString).toBe(missingValue);
    expect(t.rows[0]?.hasOwnProperty).toBe(missingValue);
  });

  it('refuses column keys that could change the prototype', () => {
    for (const key of ['__proto__', 'constructor', 'prototype']) {
      expect(() => tableModel('Deals', [{ key, label: 'X' }], [])).toThrow(/cannot be used/);
    }
  });

  it('ignores a __proto__ key in a row', () => {
    const row = { ['__proto__']: 'x', a: 'ok' };
    expect(Object.hasOwn(row, '__proto__')).toBe(true);
    const t = tableModel(
      'Deals',
      [
        { key: 'a', label: 'A' },
        { key: 'b', label: 'B' },
      ],
      [row],
    );
    expect(t.rows[0]).toEqual({ a: 'ok', b: missingValue });
    expect(Object.getPrototypeOf(t.rows[0])).toBe(Object.prototype);
    expect(Object.hasOwn(t.rows[0] ?? {}, '__proto__')).toBe(false);
  });

  it('shows a dash for an empty, blank or undefined cell, and keeps real text as it is', () => {
    const cols = [
      { key: 'a', label: 'A' },
      { key: 'b', label: 'B' },
      { key: 'c', label: 'C' },
      { key: 'd', label: 'D', numeric: true },
    ];
    const t = tableModel('Deals', cols, [{ a: '', b: '  \t\n', c: undefined, d: ' $0.00 ' }]);
    expect(t.rows).toEqual([{ a: missingValue, b: missingValue, c: missingValue, d: ' $0.00 ' }]);
    expect(tableModel('Deals', cols, [{ a: '0', b: 'No', c: 'x', d: '$1.00' }]).rows[0]).toEqual({
      a: '0',
      b: 'No',
      c: 'x',
      d: '$1.00',
    });
  });

  it('lays tables out with padding, right-aligned numbers, row lines and phone cards', () => {
    expect(tableStyles.cellPadding).toBe(`${spacing.sm}px ${spacing.md}px`);
    expect(tableStyles.rowBorder).toBe(`1px solid ${colors.border}`);
    expect(tableStyles.numeric).toEqual({ textAlign: 'right', fontVariantNumeric: 'tabular-nums' });
    expect(columnStyle({ key: 'a', label: 'A', numeric: true })).toBe(tableStyles.numeric);
    expect(columnStyle({ key: 'a', label: 'A' })).toBe(tableStyles.text);
    expect(columnStyle({ key: 'a', label: 'A', numeric: false })).toBe(tableStyles.text);
    expect(tableStyles.card.padding).toBe(`${spacing.md}px`);
    expect(tableStyles.card.border).toBe(`1px solid ${colors.border}`);
    expect(contrast(tableStyles.headerColor, tableStyles.headerBackground)).toBeGreaterThanOrEqual(
      4.5,
    );
  });
});
