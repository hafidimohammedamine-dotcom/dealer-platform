// A small limit on refused user creates per admin (security review round 2, finding 5). Emails are unique across all
// dealers, so a create that fails because the email exists would let an admin test which addresses other dealers use.
// After MAX_REFUSALS refused creates inside the window, that admin cannot create users until the window passes.
//
// The count lives in this process only (the app is one always-on container). Redis-backed limits per address and per
// email are issue #73; this class gets a Redis store then.
export interface RefusalLimiter {
  /** Note one refused create by `actorId`. */
  record(actorId: string): void;
  /** True when `actorId` has used up the refusals allowed in the window. */
  blocked(actorId: string): boolean;
}

export const MAX_REFUSALS = 5;
export const WINDOW_MS = 60 * 60 * 1000;
// Distinct actors tracked at once; the oldest is dropped beyond this, so the map cannot grow without bound.
const MAX_ACTORS = 10_000;

export function createRefusalLimiter(
  now: () => number = Date.now,
  max: number = MAX_REFUSALS,
  windowMs: number = WINDOW_MS,
): RefusalLimiter {
  const seen = new Map<string, number[]>();
  const recent = (actorId: string): number[] => {
    const cutoff = now() - windowMs;
    const times = (seen.get(actorId) ?? []).filter((time) => time > cutoff);
    if (times.length === 0) seen.delete(actorId);
    else seen.set(actorId, times);
    return times;
  };
  return {
    record(actorId) {
      const times = recent(actorId);
      times.push(now());
      seen.delete(actorId);
      seen.set(actorId, times);
      if (seen.size > MAX_ACTORS) {
        const oldest = seen.keys().next();
        if (!oldest.done) seen.delete(oldest.value);
      }
    },
    blocked: (actorId) => recent(actorId).length >= max,
  };
}
