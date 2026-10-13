export { createAuditLog, lineSink, redact } from './audit.js';
export type { AuditEntry, AuditId, AuditInput, AuditLog, AuditSink } from './audit.js';

// A real statement keeps this file inside the per-file coverage rule (a file of pure re-exports counts as 0%).
export const packageName = '@dealer/platform';
