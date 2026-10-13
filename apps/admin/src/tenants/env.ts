// Reads the app settings from environment variables (never from code). Fails at start-up, loudly, when one is missing.
// Nothing has a default: a missing APP_ENV is an error, not "dev" (fail closed).
export type AppStage = 'dev' | 'staging' | 'production';

export interface AppEmail {
  apiKey: string;
  from: string;
}

export interface AppEnv {
  stage: AppStage;
  /** True for staging and production: secure cookies, https only, real email. */
  production: boolean;
  secret: string;
  databaseUrl: string;
  serverURL: string;
  /** Resend settings. Required outside dev; in dev Payload prints emails to the console instead. */
  email?: AppEmail;
}

type Env = Record<string, string | undefined>;

const STAGES: readonly AppStage[] = ['dev', 'staging', 'production'];

function isStage(value: string): value is AppStage {
  return STAGES.some((stage) => stage === value);
}

/** True when the connection string forces TLS (`sslmode=require` or `verify-full`, the last `sslmode` wins). */
export function databaseUrlUsesTls(databaseUrl: string): boolean {
  try {
    const modes = new URL(databaseUrl).searchParams.getAll('sslmode');
    const mode = modes[modes.length - 1];
    return mode === 'require' || mode === 'verify-full';
  } catch {
    return false;
  }
}

export function readAppEnv(env: Env): AppEnv {
  const need = (name: string): string => {
    const value = env[name];
    if (value === undefined || value.trim() === '')
      throw new Error(`Missing environment variable ${name}.`);
    return value;
  };
  const stage = need('APP_ENV');
  if (!isStage(stage)) throw new Error('APP_ENV must be dev, staging or production.');
  const production = stage !== 'dev';
  const secret = need('PAYLOAD_SECRET');
  if (secret.length < 32) throw new Error('PAYLOAD_SECRET must be at least 32 characters.');
  const serverURL = need('PAYLOAD_PUBLIC_SERVER_URL');
  let url: URL;
  try {
    url = new URL(serverURL);
  } catch {
    throw new Error('PAYLOAD_PUBLIC_SERVER_URL must be a full URL.');
  }
  if (production && url.protocol !== 'https:')
    throw new Error('PAYLOAD_PUBLIC_SERVER_URL must use https outside dev.');
  const databaseUrl = need('DATABASE_URL');
  if (production && !databaseUrlUsesTls(databaseUrl))
    throw new Error('DATABASE_URL must set sslmode=require or sslmode=verify-full outside dev.');
  const result: AppEnv = {
    stage,
    production,
    secret,
    databaseUrl,
    serverURL: url.origin,
  };
  if (production) result.email = { apiKey: need('RESEND_API_KEY'), from: need('EMAIL_FROM') };
  return result;
}
