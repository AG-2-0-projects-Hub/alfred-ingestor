import { type Page } from 'playwright';
import { mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { env, stagingUrlWithBypass } from './env.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
export const REPORTS_DIR = resolve(__dirname, '../../reports');

// Fixed viewport all Layer 2 scenarios use. Coordinate fractions below are
// calibrated for this size — change them together if the viewport changes.
export const VP = { width: 1440, height: 900 } as const;

// Auth screen — right-column form layout
export const AUTH = {
  x:          0.75,
  emailY:     0.46,
  passwordY:  0.515,
  submitY:    0.60,
} as const;

// Dashboard — AppBar trailing area (wide viewport, TextButton.icon "Logout")
export const DASHBOARD = {
  logoutX:       0.93,
  logoutY:       0.035,
  // Empty-state "Add Your First Property" FilledButton (centred in body)
  addPropertyX:  0.5,
  addPropertyY:  0.58,
} as const;

// Add-property screen — single-column centred form (maxWidth 760px)
export const ADD_PROPERTY = {
  x:          0.5,
  urlY:       0.23,   // Airbnb URL TextField
  dropZoneY:  0.39,   // DropZone widget centre
  ingestY:    0.59,   // INGEST NOW button
} as const;

// Opens the staging URL (with Vercel bypass if configured) and waits for Flutter
// web hydration. Call this once per test before any interaction.
export async function hydratePage(page: Page, path = ''): Promise<void> {
  const url = stagingUrlWithBypass(path);
  await page.goto(url, { waitUntil: 'networkidle', timeout: 60_000 });
  await page.waitForTimeout(6_000);
}

// Fills in email + password on the auth screen and clicks Sign In.
// Assumes the page is already on the auth screen (call hydratePage first).
export async function loginAs(
  page: Page,
  email: string = env.testHostEmail,
  password: string = env.testHostPassword,
): Promise<void> {
  const vp = page.viewportSize() ?? VP;
  const x = vp.width * AUTH.x;

  await page.mouse.click(x, vp.height * AUTH.emailY);
  await page.waitForTimeout(400);
  await page.keyboard.type(email, { delay: 30 });

  await page.mouse.click(x, vp.height * AUTH.passwordY);
  await page.waitForTimeout(400);
  await page.keyboard.type(password, { delay: 30 });

  await page.mouse.click(x, vp.height * AUTH.submitY);
  await page.waitForTimeout(6_000); // wait for dashboard to hydrate
}

// Saves a full-page screenshot to the reports dir and returns its path.
export async function saveScreenshot(page: Page, label: string): Promise<string> {
  await mkdir(REPORTS_DIR, { recursive: true });
  const path = resolve(REPORTS_DIR, `${label}-${Date.now()}.png`);
  await page.screenshot({ path, fullPage: true });
  return path;
}
