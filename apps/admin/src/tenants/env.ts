// Reads the app settings from environment variables (never from code). Fails at start-up, loudly, when one is missing.
export interface AppEnv {
  secret: string;
  databaseUrl: string;
  serverURL: string;
  production: boolean;
}

type Env = Record<string, string | undefined>;

export function readAppEnv(env: Env): AppEnv {
  const need = (name: string): string => {
    const value = env[name];
    if (value === undefined || value === '')
      throw new Error(`Missing environment variable ${name}.`);
    return value;
  };
  const secret = need('PAYLOAD_SECRET');
  if (secret.length < 32) throw new Error('PAYLOAD_SECRET must be at least 32 characters.');
  const appEnv = env['APP_ENV'] ?? 'dev';
  if (!['dev', 'staging', 'production'].includes(appEnv))
    throw new Error('APP_ENV must be dev, staging or production.');
  return {
    secret,
    databaseUrl: need('DATABASE_URL'),
    serverURL: need('PAYLOAD_PUBLIC_SERVER_URL'),
    production: appEnv !== 'dev',
  };
}
