import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Verteilung', () => {
  test('Pre-Flight-Button startet Pre-Flight-Check', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'verteilung');

    // Pre-Flight-Button klicken
    const preflightBtn = page.locator('button').filter({ hasText: /Pre.?Flight|Vorprüfung|Prüfung starten/i }).first();
    await expect(preflightBtn).toBeVisible({ timeout: 5_000 });
    await preflightBtn.click();
    await page.waitForTimeout(400);

    // Nach dem Click sollte ein Ergebnis (ok oder fehler) sichtbar sein
    const result = page.locator('.alert-success, .alert-error').first();
    await expect(result).toBeVisible({ timeout: 5_000 });
  });

  test('Pre-Flight wirft Fehler wenn Schüler-Array leer', async ({ page }) => {
    await openAppLoggedIn(page);

    // Schüler-Array leeren
    await page.evaluate(() => {
      const win = window as any;
      if (win.mockSchueler) win.mockSchueler.length = 0;
    });

    await goToSection(page, 'verteilung');

    const preflightBtn = page.locator('button').filter({ hasText: /Pre.?Flight|Vorprüfung|Prüfung starten/i }).first();
    if (await preflightBtn.count() === 0) {
      test.skip(true, 'Pre-Flight-Button nicht gefunden');
      return;
    }
    await preflightBtn.click();
    await page.waitForTimeout(600);

    // Fehler oder Warnung sollte sichtbar sein
    const errorEl = page.locator('.alert-error, .alert-warning').first();
    await expect(errorEl).toBeVisible({ timeout: 5_000 });
  });
});
