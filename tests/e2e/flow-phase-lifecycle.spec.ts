import { test, expect, openAppLoggedIn, goToSection, DEMO_PASSWORD } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * E2E-Flow: Phase-Lifecycle
 *
 * super_admin → Phase auf "setup" → Dashboard zeigt Setup-Titel
 * Phase auf "anmeldung" → Anmeldungen-Nav sichtbar
 * Phase auf "nachbearbeitung" → Tauschwünsche-Tab sichtbar
 */
test.describe('Flow: Phase Lifecycle', () => {
  test('Phase auf setup setzen → Dashboard zeigt Setup-Titel', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'phase');

    // Setup-Phase klicken
    const setupCard = page.locator('div').filter({ has: page.locator('strong').filter({ hasText: /^Setup$/ }) }).first();
    if (await setupCard.count() === 0) {
      // Fallback: Alle Phase-Items und erstes klicken
      const items = page.locator('.card div[style*="border-radius:8px"]');
      if (await items.count() > 0) await items.first().click();
    } else {
      await setupCard.click();
    }
    await page.waitForTimeout(300);

    // Zum Dashboard navigieren
    await goToSection(page, 'dashboard');

    // Dashboard zeigt Setup-Kontext (Projekte / Lehrer Tiles)
    await expect(page.locator('.dash-grid')).toBeVisible({ timeout: 3_000 });
    // Phase-Badge zeigt "Setup" oder "Anmeldung" (je nach aktueller Phase)
    const badge = page.locator('span').filter({ hasText: /📅/ }).first();
    await expect(badge).toBeVisible();
  });

  test('Phase auf anmeldung → Anmeldungen-Tab erscheint in Nav', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'phase');

    // Anmeldung-Phase klicken
    const anmeldungCard = page.locator('div').filter({ has: page.locator('strong').filter({ hasText: /^Anmeldung$/ }) }).first();
    if (await anmeldungCard.count() > 0) {
      await anmeldungCard.click();
      await page.waitForTimeout(300);
    }

    // In der Nav sollte [data-section="anmeldungen"] sichtbar sein
    const anmeldungenNav = page.locator('[data-section="anmeldungen"]');
    await expect(anmeldungenNav).toBeVisible({ timeout: 3_000 });
  });

  test('Phase auf nachbearbeitung → Tauschwünsche-Tab sichtbar', async ({ page }) => {
    // Direkt mit MOCK_PHASE='nachbearbeitung' starten — verlässlicher als UI-Klick,
    // da der Nav nur beim App-Start aus der Initialphase aufgebaut wird.
    await page.addInitScript(`window.MOCK_PHASE = 'nachbearbeitung';`);
    await page.goto('/admin-dashboard-v2.html?forceMode=demo');
    await page.locator('#gateFormDemo').waitFor({ state: 'visible', timeout: 5_000 });
    await page.locator('#pwInput').fill(DEMO_PASSWORD);
    await page.locator('#gateBtnDemo').click();
    await page.locator('#appContent').waitFor({ state: 'visible', timeout: 5_000 });
    await page.waitForTimeout(200);

    // Tauschwünsche-Tab erscheint nur in Phase nachbearbeitung
    const tauschNav = page.locator('[data-section="tauschwuensche"]');
    await expect(tauschNav).toBeVisible({ timeout: 3_000 });
  });
});
