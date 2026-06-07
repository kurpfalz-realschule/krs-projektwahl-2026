import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Einstellungen', () => {
  test('Settings-Form lädt mit Termin-Feldern', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'einstellungen');

    await expect(page.locator('h1').filter({ hasText: /Einstellungen/i })).toBeVisible({ timeout: 5_000 });

    // Datum-Eingabefelder vorhanden
    const inputs = page.locator('input[type="text"]');
    const count = await inputs.count();
    expect(count, 'Mindestens 2 Termin-Felder erwartet').toBeGreaterThanOrEqual(2);
  });

  test('Speichern-Button ist sichtbar', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'einstellungen');

    const saveBtn = page.locator('button').filter({ hasText: /Speichern/i }).first();
    await expect(saveBtn).toBeVisible({ timeout: 5_000 });

    // Im Demo-Modus: Klick auf Save soll keinen Absturz produzieren
    await saveBtn.click();
    await page.waitForTimeout(300);
    await expect(page.locator('#appContent')).toBeVisible();
  });
});
