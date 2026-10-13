import { describe, expect, it } from 'vitest';
import { createRefusalLimiter, MAX_REFUSALS, WINDOW_MS } from './refusal-limit.js';

describe('createRefusalLimiter', () => {
  it('blocks an actor after the allowed refusals, and only that actor', () => {
    let time = 1_000;
    const limiter = createRefusalLimiter(() => time);
    for (let i = 0; i < MAX_REFUSALS - 1; i += 1) limiter.record('a');
    expect(limiter.blocked('a')).toBe(false);
    limiter.record('a');
    expect(limiter.blocked('a')).toBe(true);
    expect(limiter.blocked('b')).toBe(false);
    time += 1;
    expect(limiter.blocked('a')).toBe(true);
  });

  it('forgets refusals once the window has passed', () => {
    let time = 1_000;
    const limiter = createRefusalLimiter(() => time);
    for (let i = 0; i < MAX_REFUSALS; i += 1) limiter.record('a');
    time += WINDOW_MS;
    expect(limiter.blocked('a')).toBe(false);
    limiter.record('a');
    expect(limiter.blocked('a')).toBe(false);
  });

  it('keeps the table bounded', () => {
    const limiter = createRefusalLimiter(() => 5, 1);
    for (let i = 0; i < 10_050; i += 1) limiter.record(`actor${i}`);
    expect(limiter.blocked('actor0')).toBe(false);
    expect(limiter.blocked('actor10049')).toBe(true);
  });
});
