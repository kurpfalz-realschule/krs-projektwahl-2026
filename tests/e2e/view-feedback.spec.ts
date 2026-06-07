import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Feedback-Übersicht', () => {
  test('Feedback-View lädt mit Demo-Hinweis', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'feedback');

    await expect(page.locator('h1').filter({ hasText: /Feedback/i })).toBeVisible({ timeout: 5_000 });
    // Im Demo-Modus erscheint ein Alert-Info-Hinweis (keine echten Daten)
    await expect(page.locator('.alert-warning, .alert-info').first()).toBeVisible({ timeout: 3_000 });
  });

  test('Filter-Buttons (Offen / Alle) sind sichtbar und schaltbar', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'feedback');

    const offenBtn = page.locator('button').filter({ hasText: /Offen/i }).first();
    const alleBtn  = page.locator('button').filter({ hasText: /^Alle/i }).first();

    await expect(offenBtn).toBeVisible({ timeout: 5_000 });
    await expect(alleBtn).toBeVisible();

    // Filter wechseln
    await alleBtn.click();
    await page.waitForTimeout(150);
    // Kein Absturz
    await expect(page.locator('h1').filter({ hasText: /Feedback/i })).toBeVisible();
  });
});
