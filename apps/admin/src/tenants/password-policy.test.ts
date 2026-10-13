import { describe, expect, it } from 'vitest';
import { MAX_PASSWORD_LENGTH, MIN_PASSWORD_LENGTH, passwordProblem } from './password-policy.js';

describe('passwordProblem', () => {
  it('accepts a long, uncommon password', () => {
    expect(passwordProblem('correct horse battery staple')).toBeNull();
    expect(passwordProblem('x'.repeat(5) + 'Kq7!vR2#mZ9p')).toBeNull();
  });

  it('refuses anything that is not a string', () => {
    for (const bad of [undefined, null, 12345678901234, {}]) {
      expect(passwordProblem(bad)).toBe('A password is required.');
    }
  });

  it('refuses a short password and an over-long one', () => {
    expect(passwordProblem('a'.repeat(MIN_PASSWORD_LENGTH - 1))).toContain('at least 12');
    expect(passwordProblem('a'.repeat(MIN_PASSWORD_LENGTH))).not.toContain('at least');
    expect(passwordProblem('Kq7!' + 'v'.repeat(MAX_PASSWORD_LENGTH))).toContain('at most 128');
  });

  it('refuses common passwords, also with digits and symbols on the ends and in capitals', () => {
    for (const bad of ['passwordpassword', 'Password12345!!', '2026qwertyuiop', 'LETMEIN123456']) {
      expect(passwordProblem(bad)).toContain('too common');
    }
  });

  it('refuses a password that only repeats one short piece', () => {
    expect(passwordProblem('abcabcabcabc')).toContain('too common');
    expect(passwordProblem('111111111111')).toContain('too common');
  });

  it('refuses a password that contains the name part of the email', () => {
    expect(passwordProblem('jane.doe-2026-ok!', 'Jane.Doe@dealer.example')).toContain('email name');
    expect(passwordProblem('Kq7!vR2#mZ9p', 'jane.doe@dealer.example')).toBeNull();
    expect(passwordProblem('abcdefghi-ab-xyz', 'ab@dealer.example')).toBeNull();
    expect(passwordProblem('Kq7!vR2#mZ9p', 42)).toBeNull();
  });

  it('handles unicode passwords by length in characters', () => {
    expect(passwordProblem('Ünïcödé-pässwörd-Ωmega')).toBeNull();
  });
});
