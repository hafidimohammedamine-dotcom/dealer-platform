// Append-only audit log writer (FTC Safeguards Rule, 16 CFR 314.4(c)(8): who changed access, to what, and when).
//
// The writer can only add entries. The sink it writes to has one method, `append`, and no way to read, change or
// remove an entry. Every entry is frozen before it reaches the sink. Secrets and sensitive values are removed from the
// before/after snapshots by key name, so a caller that passes a whole record by mistake still cannot log a password.
// If the sink fails, `record` rejects: the caller must stop the change (fail closed).

export type AuditId = string | number;

export interface AuditEntry {
  /** ISO 8601, UTC. */
  readonly at: string;
  readonly action: string;
  /** Who did it. `null` for a reviewed system job. */
  readonly actorId: AuditId | null;
  readonly target: { readonly collection: string; readonly id: AuditId | null };
  /** The dealers the change belongs to (`dealer_id` of the record, or the dealers of a user). */
  readonly dealerIds: readonly string[];
  readonly before?: Readonly<Record<string, unknown>>;
  readonly after?: Readonly<Record<string, unknown>>;
}

export interface AuditInput {
  action: string;
  actorId: AuditId | null;
  target: { collection: string; id: AuditId | null };
  dealerIds: readonly AuditId[];
  before?: Record<string, unknown> | undefined;
  after?: Record<string, unknown> | undefined;
}

/** Where entries go. Append only: there is deliberately no read, update or delete here. */
export interface AuditSink {
  append(entry: AuditEntry): void | Promise<void>;
}

export interface AuditLog {
  record(input: AuditInput): Promise<AuditEntry>;
}

// Key names that never reach the log, whatever the value (secrets, credentials, sensitive customer fields).
const SECRET_KEY =
  /pass|secret|token|hash|salt|key|cookie|session|otp|totp|ssn|social|dob|birth|income|bank|account|routing|card/i;
const MAX_DEPTH = 4;
const REDACTED = '[removed]';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function redactValue(value: unknown, depth: number): unknown {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (depth >= MAX_DEPTH) return REDACTED;
  if (Array.isArray(value)) return value.map((item) => redactValue(item, depth + 1));
  if (isRecord(value)) return redact(value, depth + 1);
  return REDACTED;
}

/** A copy of `record` with every secret-looking key replaced and only plain JSON values kept. */
export function redact(record: Record<string, unknown>, depth = 0): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(record)) {
    out[key] = SECRET_KEY.test(key) ? REDACTED : redactValue(value, depth);
  }
  return out;
}

function deepFreeze<T>(value: T): T {
  if (typeof value === 'object' && value !== null && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const inner of Object.values(value)) deepFreeze(inner);
  }
  return value;
}

export function createAuditLog(sink: AuditSink, now: () => Date = () => new Date()): AuditLog {
  return {
    async record(input) {
      const entry: AuditEntry = deepFreeze({
        at: now().toISOString(),
        action: input.action,
        actorId: input.actorId,
        target: { collection: input.target.collection, id: input.target.id },
        dealerIds: input.dealerIds.map(String),
        ...(input.before === undefined ? {} : { before: redact(input.before) }),
        ...(input.after === undefined ? {} : { after: redact(input.after) }),
      });
      await sink.append(entry);
      return entry;
    },
  };
}

/** One JSON line per entry on the given writer (stdout in the app; Railway keeps the log stream). */
export function lineSink(write: (line: string) => void): AuditSink {
  return { append: (entry) => write(`${JSON.stringify({ audit: entry })}\n`) };
}
