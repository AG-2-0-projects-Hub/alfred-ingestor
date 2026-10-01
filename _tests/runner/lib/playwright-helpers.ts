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
  // Top-bar "Settings" gear icon (2026-09-19) -- sits between Profile and
  // the "?" host-guide icon. Measured from a real 1440x900 screenshot.
  settingsIconX: 0.830,
  settingsIconY: 0.031,
} as const;

// First property card in the grid (top-left slot), wide viewport. Measured
// from a real 1440x900 screenshot with a single card present.
export const CARD1 = {
  // Anywhere on the photo/body -- not the action buttons below.
  bodyX:     0.110,
  bodyY:     0.267,
  guestX:    0.057,
  detailsX:  0.117,
  actionsY:  0.601,
} as const;

// Standard Material AppBar back-arrow (top-left leading icon) -- same
// position on every screen that uses a plain AppBar(leading: BackButton()).
export const APPBAR = {
  backX: 0.0194,
  backY: 0.0311,
} as const;

// Add-property screen — single-column centred form (maxWidth 760px)
export const ADD_PROPERTY = {
  x:          0.5,
  urlY:       0.23,   // Airbnb URL TextField
  dropZoneY:  0.875,  // DropZone widget centre, unscrolled (was 0.39 before the Gold/Also-helps tips cards pushed it down; re-measured 2026-10-01)
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

// Clicks the dashboard's "+ Add Property" tile. It sits right after the last
// real (non-deleted) property card, so its x is computed from the live count --
// the empty-state button DASHBOARD.addPropertyX/Y only exists on an account
// with zero properties, which the QA account no longer is (it owns the isolated
// QA property several scenarios depend on).
export async function openAddPropertyFromDashboard(page: Page): Promise<void> {
  const authRes = await fetch(`${env.supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: env.supabaseAnonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: env.testHostEmail, password: env.testHostPassword }),
  });
  const { access_token } = (await authRes.json()) as { access_token: string };
  const countRes = await fetch(`${env.supabaseUrl}/rest/v1/properties?select=id&deleted_at=is.null`, {
    headers: { apikey: env.supabaseAnonKey, Authorization: `Bearer ${access_token}` },
  });
  const activeCount = ((await countRes.json()) as unknown[]).length;
  const vp = page.viewportSize() ?? VP;
  await page.mouse.click(vp.width * (0.11 + activeCount * 0.194), vp.height * 0.367);
  await page.waitForTimeout(2_000);
}

// Saves a full-page screenshot to the reports dir and returns its path.
export async function saveScreenshot(page: Page, label: string): Promise<string> {
  await mkdir(REPORTS_DIR, { recursive: true });
  const path = resolve(REPORTS_DIR, `${label}-${Date.now()}.png`);
  await page.screenshot({ path, fullPage: true });
  return path;
}
