import { test as base, expect, Page } from '@playwright/test';

/**
 * Base-Fixture für alle KRS-E2E-Tests.
 *
 * Gibt eine `page` zurück, die bereits:
 *  1. admin-dashboard-v2.html?forceMode=demo geladen hat
 *  2. sich im Demo-Modus mit dem Standard-Passwort 'Krs26PW' eingeloggt hat
 *  3. auf `#appContent` sichtbar gewartet hat
 *
 * Warum forceMode=demo?
 *  - Schützt Produktiv-Supabase vor Test-Mutationen
 *  - Tests sind hermetisch (frische Mock-Daten bei jedem Page-Load)
 *  - Test-Code und Produktiv-Code durchlaufen die gleichen UI-Pfade
 */

export const DEMO_PASSWORD = 'Krs26PW';

export type Rolle = 'super_admin' | 'projektleitung' | 'projektlehrer' | 'klassenlehrer';

export async function openAppLoggedIn(page: Page) {
  await page.goto('/admin-dashboard-v2.html?forceMode=demo');

  // Version-Marker in der Console prüfen — fängt Deploy-Stale-Bugs
  await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');
  const version = await page.evaluate(() => (window as any).KRS_VERSION);
  const mode = await page.evaluate(() => (window as any).KRS_MODE);
  expect.soft(mode, 'forceMode=demo sollte Demo-Modus erzwingen').toBe('demo');
  expect.soft(version, 'KRS_VERSION sollte v22+ sein').toMatch(/^v(2[2-9]|3[0-9])/);

  // Demo-Login-Form abwarten und absenden
  await page.locator('#gateFormDemo').waitFor({ state: 'visible', timeout: 5_000 });
  await page.locator('#pwInput').fill(DEMO_PASSWORD);
  await page.locator('#gateBtnDemo').click();

  // App-Content sichtbar → Login erfolgreich
  await page.locator('#appContent').waitFor({ state: 'visible', timeout: 5_000 });
}

/**
 * loginAs — navigiert zur App mit forceMode=demo&forceRolle=<rolle> und loggt ein.
 *
 * Setzt den URL-Override ?forceRolle=<rolle>, damit die App nach dem Login
 * automatisch die richtige Rolle und Default-Section lädt (v25 / Sprint-D-2).
 *
 * Beispiel:
 *   await loginAs(page, 'projektlehrer');
 *   // App ist eingeloggt, activeSection = 'mein-projekt'
 */
export async function loginAs(page: Page, rolle: Rolle) {
  await page.goto(`/admin-dashboard-v2.html?forceMode=demo&forceRolle=${rolle}`);

  await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');
  const mode = await page.evaluate(() => (window as any).KRS_MODE);
  expect.soft(mode, 'forceMode=demo sollte Demo-Modus erzwingen').toBe('demo');

  await page.locator('#gateFormDemo').waitFor({ state: 'visible', timeout: 5_000 });
  await page.locator('#pwInput').fill(DEMO_PASSWORD);
  await page.locator('#gateBtnDemo').click();

  await page.locator('#appContent').waitFor({ state: 'visible', timeout: 5_000 });
  // kurze Pause damit der forceRolle-useEffect gefeuert hat (Preact re-render)
  await page.waitForTimeout(200);
}

/**
 * resetMockState — reloaded die Seite und setzt alle Mock-Arrays auf Initial-Werte zurück.
 * Nützlich nach Tests die Mock-Arrays mutiert haben.
 */
export async function resetMockState(page: Page) {
  await page.reload();
  await page.locator('#gateFormDemo').waitFor({ state: 'visible', timeout: 5_000 });
  await page.locator('#pwInput').fill(DEMO_PASSWORD);
  await page.locator('#gateBtnDemo').click();
  await page.locator('#appContent').waitFor({ state: 'visible', timeout: 5_000 });
}

/**
 * seedMockData — befüllt Mock-Arrays per page.evaluate() nach dem Login.
 * Für Spezial-Tests die bestimmte Daten-Konstellationen benötigen.
 */
export async function seedMockData(page: Page, options: {
  projekte?: any[];
  lehrer?: any[];
  schueler?: any[];
} = {}) {
  await page.evaluate((opts) => {
    const win = window as any;
    if (opts.projekte !== undefined && win.mockProjekteData) {
      win.mockProjekteData.length = 0;
      opts.projekte.forEach((p: any) => win.mockProjekteData.push(p));
    }
    if (opts.lehrer !== undefined && win.mockLehrerData) {
      win.mockLehrerData.length = 0;
      opts.lehrer.forEach((l: any) => win.mockLehrerData.push(l));
    }
    if (opts.schueler !== undefined && win.mockSchueler) {
      win.mockSchueler.length = 0;
      opts.schueler.forEach((s: any) => win.mockSchueler.push(s));
    }
    // v27/E1: signalisiert App-Komponente → bumpt refreshKey → Views rendern neu
    win.dispatchEvent(new Event('krs:mock-seeded'));
  }, options);
  // kleines Timeout damit Preact re-rendert
  await page.waitForTimeout(150);
}

/**
 * Mapping: Section → Phase, die diesen Tab sichtbar macht.
 * Phasenabhängige Sections erscheinen nur bei bestimmten Phasen im Nav.
 * Default-Phase der App ist 'anmeldung' — diese Sections sind dann versteckt.
 */
const SECTION_REQUIRES_PHASE: Record<string, string> = {
  verteilung:     'nachbearbeitung',
  zuteilungen:    'nachbearbeitung',
  umbuchung:      'nachbearbeitung',
  tauschwuensche: 'nachbearbeitung',
  export:         'nachbearbeitung',
};

/**
 * Navigiert zu einer Section in der Sidebar (z.B. 'projekte', 'lehrer').
 * Verwendet data-section als Anker (robuster als Text-Matching).
 *
 * Für phasenabhängige Sections (verteilung, zuteilungen, …) die im Default
 * 'anmeldung' nicht sichtbar sind: setzt MOCK_PHASE via addInitScript und
 * lädt die App neu, damit der Nav-Eintrag erscheint.
 */
export async function goToSection(page: Page, section: string) {
  const navItem = page.locator(`[data-section="${section}"]`).first();

  // Prüfe ob der Nav-Eintrag sichtbar ist
  const isVisible = await navItem.isVisible().catch(() => false);

  if (!isVisible && SECTION_REQUIRES_PHASE[section]) {
    // Phase-abhängige Section: MOCK_PHASE via addInitScript setzen (läuft vor
    // App-Initialisierung) und dann App neu laden + einloggen.
    const targetPhase = SECTION_REQUIRES_PHASE[section];
    await page.addInitScript(`window.MOCK_PHASE = '${targetPhase}';`);
    const currentUrl = page.url();
    await page.goto(currentUrl);
    // Demo-Session kann in sessionStorage persistieren → Gate-Form erscheint nicht mehr.
    // Wenn Gate binnen 1,5 s nicht sichtbar → App bereits eingeloggt → überspringen.
    try {
      await page.locator('#gateFormDemo').waitFor({ state: 'visible', timeout: 1_500 });
      await page.locator('#pwInput').fill(DEMO_PASSWORD);
      await page.locator('#gateBtnDemo').click();
    } catch { /* bereits eingeloggt — sessionStorage-Session noch gültig */ }
    await page.locator('#appContent').waitFor({ state: 'visible', timeout: 5_000 });
    await page.waitForTimeout(200);
  }

  await navItem.click();
  // kurzer Idle-Wait, damit der neue View gerendert ist
  await page.waitForTimeout(150);
}

export const test = base.extend<{ appPage: Page }>({
  appPage: async ({ page }, use) => {
    await openAppLoggedIn(page);
    await use(page);
  },
});

export { expect };
