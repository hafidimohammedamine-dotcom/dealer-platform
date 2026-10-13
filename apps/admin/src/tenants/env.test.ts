import { describe, expect, it } from 'vitest';
import { readAppEnv } from './env.js';

const dev = {
  APP_ENV: 'dev',
  PAYLOAD_SECRET: 'y'.repeat(32),
  DATABASE_URL: 'postgres://u:p@h/db',
  PAYLOAD_PUBLIC_SERVER_URL: 'http://localhost:3000',
};
const live = {
  ...dev,
  APP_ENV: 'production',
  PAYLOAD_PUBLIC_SERVER_URL: 'https://admin.example.test',
  RESEND_API_KEY: 're_fake',
  EMAIL_FROM: 'noreply@example.test',
};

describe('readAppEnv', () => {
  it('reads dev settings without email', () => {
    expect(readAppEnv(dev)).toEqual({
      stage: 'dev',
      production: false,
      secret: dev.PAYLOAD_SECRET,
      databaseUrl: dev.DATABASE_URL,
      serverURL: 'http://localhost:3000',
    });
  });

  it('reads staging and production settings with email', () => {
    expect(readAppEnv(live)).toMatchObject({
      stage: 'production',
      production: true,
      email: { apiKey: 're_fake', from: 'noreply@example.test' },
    });
    expect(readAppEnv({ ...live, APP_ENV: 'staging' }).production).toBe(true);
  });

  it('fails closed: APP_ENV has no default', () => {
    expect(() => readAppEnv({ ...dev, APP_ENV: undefined })).toThrow('APP_ENV');
    expect(() => readAppEnv({ ...dev, APP_ENV: '' })).toThrow('APP_ENV');
    expect(() => readAppEnv({ ...dev, APP_ENV: 'prod' })).toThrow('dev, staging or production');
  });

  it('fails loudly on a missing, empty, blank or weak setting', () => {
    expect(() => readAppEnv({ ...dev, DATABASE_URL: undefined })).toThrow('DATABASE_URL');
    expect(() => readAppEnv({ ...dev, DATABASE_URL: '' })).toThrow('DATABASE_URL');
    expect(() => readAppEnv({ ...dev, DATABASE_URL: '   ' })).toThrow('DATABASE_URL');
    expect(() => readAppEnv({ ...dev, PAYLOAD_SECRET: '' })).toThrow('PAYLOAD_SECRET');
    expect(() => readAppEnv({ ...dev, PAYLOAD_SECRET: 'y'.repeat(31) })).toThrow('32');
    expect(readAppEnv({ ...dev, PAYLOAD_SECRET: 'y'.repeat(32) }).secret).toHaveLength(32);
    expect(() => readAppEnv({ ...dev, PAYLOAD_PUBLIC_SERVER_URL: undefined })).toThrow(
      'PAYLOAD_PUBLIC_SERVER_URL',
    );
  });

  it('needs a real URL, and https outside dev', () => {
    expect(() => readAppEnv({ ...dev, PAYLOAD_PUBLIC_SERVER_URL: 'not a url' })).toThrow(
      'full URL',
    );
    expect(() =>
      readAppEnv({ ...live, PAYLOAD_PUBLIC_SERVER_URL: 'http://admin.example.test' }),
    ).toThrow('https');
    expect(
      readAppEnv({ ...dev, PAYLOAD_PUBLIC_SERVER_URL: 'http://localhost:3000/path' }).serverURL,
    ).toBe('http://localhost:3000');
  });

  it('needs the email settings outside dev', () => {
    expect(() => readAppEnv({ ...live, RESEND_API_KEY: undefined })).toThrow('RESEND_API_KEY');
    expect(() => readAppEnv({ ...live, EMAIL_FROM: '' })).toThrow('EMAIL_FROM');
  });
});
