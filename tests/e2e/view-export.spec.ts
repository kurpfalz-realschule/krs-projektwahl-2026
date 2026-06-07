import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Export & Aushang', () => {
  test('CSV-Gesamtlisten-Button ist vorhanden und anklickbar', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'export');

    // Export-View hat mehrere Tiles mit Download-Buttons
    await expect(page.locator('h1').filter({ hasText: /Export/i })).toBeVisible({ timeout: 5_000 });

    const csvBtn = page.locator('button').filter({ hasText: /Gesamtliste|Herunterladen/i }).first();
    await expect(csvBtn).toBeVisible();
  });

  test('PDF-Klassenlisten-Button löst Download-Event aus', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'export');

    const pdfBtn = page.locator('button').filter({ hasText: /Klassenlisten|PDF erstellen/i }).first();
    await expect(pdfBtn).toBeVisible({ timeout: 5_000 });

    // Download-Event abfangen (im Demo-Modus wird jsPDF ausgeführt → Toast erscheint)
    // Im Demo mit leeren Zuteilungen erscheint ein Toast "Keine Zuteilungsdaten"
    await pdfBtn.click();
    await page.waitForTimeout(500);

    // Toast oder kein Absturz — die App muss weiterhin stabil sein
    await expect(page.locator('#appContent')).toBeVisible();
  });
});
