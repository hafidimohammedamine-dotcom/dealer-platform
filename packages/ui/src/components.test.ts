import { describe, expect, it } from 'vitest';
import {
  colors,
  breakpoints,
  buttonStyles,
  inputStyles,
  inputAttributes,
  emptyState,
  errorState,
  loadingState,
  tableModel,
  tableStyles,
  missingValue,
} from './index.js';

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
  });

  it('writes plain empty, error and loading states', () => {
    expect(emptyState('leads', 'Add a lead').action).toBe('Add a lead');
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

  it('never reads inherited values or lets a key change a row', () => {
    const cols = [
      { key: 'toString', label: 'A' },
      { key: 'hasOwnProperty', label: 'C' },
    ];
    const t = tableModel('Deals', cols, [{}]);
    expect(t.rows).toEqual([{ toString: missingValue, hasOwnProperty: missingValue }]);
    expect(Object.getPrototypeOf(t.rows[0])).toBeNull();
  });

  it('ignores a row that carries its own __proto__ key and refuses it as a column', () => {
    const evil: Record<string, string> = JSON.parse('{"__proto__":{"x":"1"},"a":"ok"}');
    const t = tableModel(
      'Deals',
      [
        { key: 'a', label: 'A' },
        { key: 'x', label: 'X' },
      ],
      [evil],
    );
    expect(t.rows).toEqual([{ a: 'ok', x: missingValue }]);
    expect(Object.getPrototypeOf(t.rows[0])).toBeNull();
    for (const key of ['__proto__', 'constructor', 'prototype']) {
      expect(() => tableModel('Deals', [{ key, label: 'Bad' }], [evil])).toThrow(/cannot be used/);
    }
  });

  it('shows the missing mark for a cell that is not text', () => {
    const odd: Record<string, string> = JSON.parse('{"a":5}');
    expect(tableModel('Deals', [{ key: 'a', label: 'A' }], [odd]).rows).toEqual([
      { a: missingValue },
    ]);
  });
});
