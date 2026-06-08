import 'dotenv/config';
import { config } from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const envPath = resolve(__dirname, '../../fixtures/.env.test');

const result = config({ path: envPath });
if (result.error) {
  console.error(`Failed to load .env.test at ${envPath}`);
  console.error(`Create it from .env.test.example first.`);
  process.exit(1);
}

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing required env var: ${name}`);
    console.error(`Check _tests/fixtures/.env.test`);
    process.exit(1);
  }
  return value;
}

function optional(name: string): string | undefined {
  const value = process.env[name];
  return value && value.length > 0 ? value : undefined;
}

export const env = {
  stagingFrontend: required('STAGING_FRONTEND_URL'),
  stagingBackend: required('STAGING_BACKEND_URL'),
  stagingScraper: required('STAGING_SCRAPER_URL'),
  supabaseUrl: required('SUPABASE_URL'),
  supabaseAnonKey: required('SUPABASE_ANON_KEY'),
  testHostEmail: required('TEST_HOST_EMAIL'),
  testHostPassword: required('TEST_HOST_PASSWORD'),
  geminiApiKey: required('GEMINI_API_TEST_KEY'),
  vercelBypassToken: optional('VERCEL_BYPASS_TOKEN'),
};

// Returns the staging frontend URL with Vercel Protection Bypass query params
// appended when a token is configured. `set-bypass-cookie=true` means Vercel
// sets a cookie on first response so subsequent navigations in the same
// browser context bypass automatically without needing to rewrite every URL.
export function stagingUrlWithBypass(path = ''): string {
  const base = env.stagingFrontend.replace(/\/$/, '') + path;
  if (!env.vercelBypassToken) return base;
  const separator = base.includes('?') ? '&' : '?';
  return `${base}${separator}x-vercel-protection-bypass=${env.vercelBypassToken}&x-vercel-set-bypass-cookie=true`;
}
