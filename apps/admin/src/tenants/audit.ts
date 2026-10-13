import { createAuditLog, lineSink } from '@dealer/platform';
import type { AuditLog } from '@dealer/platform';

// The access audit log for users and dealers (16 CFR 314.4(c)(8)). Entries are JSON lines on stdout today (Railway keeps
// the log stream). A database table with its own retention is a follow-up; the retention period is waiting on the
// lawyer's answer (see docs/api/dealers-and-users.md).
export const writeToStdout = (line: string): void => {
  process.stdout.write(line);
};

export const accessAudit: AuditLog = createAuditLog(lineSink(writeToStdout));

export type { AuditLog };
