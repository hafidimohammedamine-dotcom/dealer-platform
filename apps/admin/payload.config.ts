import { buildConfig } from 'payload';
import { buildAppConfig } from './src/tenants/config.js';
import { readAppEnv } from './src/tenants/env.js';

// Thin entry point: all settings live in src/tenants/config.ts (tested). Values come from environment variables only.
export default buildConfig(buildAppConfig({ env: readAppEnv(process.env) }));
