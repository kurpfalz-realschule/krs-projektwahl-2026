import { test, expect } from '@playwright/test';

test.describe.configure({ mode: 'serial' });

/**
 * Smoke-Tests für schueler-frontend-v3.html (Sprint v30 / E2)
 *
 * Lädt das Schüler-Frontend mit ?forceMode=demo (v30/E2-Override) und prüft,
 * dass Demo-Mode-Badge + Version-Marker + Mock-Daten verfügbar sind.
 */
test.describe('Schüler-Frontend: Smoke', () => {
  test('?forceMode=demo erzwingt Demo-Mode + setzt KRS_VERSION', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    const mode = await page.evaluate(() => (window as any).KRS_MODE);
    const version = await page.evaluate(() => (window as any).KRS_VERSION);
    expect(mode, 'forceMode=demo sollte Demo-Modus erzwingen').toBe('demo');
    expect(version, 'KRS_VERSION sollte v30+ sein').toMatch(/^v(3[0-9])/);

    // Demo-Badge sichtbar
    await expect(page.locator('.mode-badge.demo')).toBeVisible({ timeout: 3_000 });
  });

  test('Mock-Daten exposed: window.MOCK_PROJEKTE + window.MOCK_SCHUELER', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    const counts = await page.evaluate(() => ({
      projekte: ((window as any).MOCK_PROJEKTE || []).length,
      schueler: Object.keys((window as any).MOCK_SCHUELER || {}).length,
    }));
    expect(counts.projekte, 'mind. 4 Demo-Projekte erwartet').toBeGreaterThan(3);
    expect(counts.schueler, 'mind. 4 Demo-Schüler erwartet').toBeGreaterThan(3);
  });

  test('Logo-Bild lädt im Schüler-Frontend', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    const logo = page.locator('.logo-wrapper img');
    await expect(logo).toBeVisible();
    await expect.poll(() => logo.evaluate(img => (img as HTMLImageElement).naturalWidth)).toBeGreaterThan(0);
  });

  test('URL-Param ?code=… submitet automatisch', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo&code=8A-T4P1');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    // 8A-T4P1 = Anna Schmidt, hat_gewaehlt=false → landet im Bestätigungs-Screen.
    // h2 ist "Bist du das? 🤔", die Schüler-Daten stehen in .bestaetigung-box.
    await expect(page.locator('h2').filter({ hasText: /Bist du das/i })).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('.bestaetigung-box')).toContainText('Anna Schmidt');
  });

  test('Projektbilder werden in der Wahlliste angezeigt', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo&code=8A-T4P1');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');
    await page.locator('button').filter({ hasText: /Ja, das bin ich/ }).click();

    const cardImage = page
      .locator('.projekt-card')
      .filter({ hasText: 'Fotografie & Bildbearbeitung' })
      .locator('img.projekt-image');
    await expect(cardImage).toBeVisible();
    await expect.poll(() => cardImage.evaluate(img => (img as HTMLImageElement).naturalWidth)).toBeGreaterThan(0);
  });
});
