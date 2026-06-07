import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Anmeldungen', () => {
  test('Anmeldungs-View lädt Klassen-Übersicht', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'anmeldungen');

    // Header "Anmelde-Status" muss sichtbar sein
    await expect(page.locator('h1').filter({ hasText: /Anmelde/i })).toBeVisible({ timeout: 5_000 });
    // Stat-Rows oder Empty-State (kein Schüler-Import im Demo → empty-state möglich)
    const rows = await page.locator('.stat-row, table tbody tr, .klassen-row').count();
    const emptyState = await page.locator('.empty-state').count();
    expect(rows + emptyState, 'View muss Klassen-Zeilen ODER Empty-State zeigen').toBeGreaterThan(0);
  });

  test('Prozent-Anzeige ist sichtbar', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'anmeldungen');

    // .main-subtitle zeigt "X von Y Schülern (Z%)" — immer sichtbar
    const subtitle = page.locator('.main-subtitle').first();
    await expect(subtitle).toBeVisible({ timeout: 5_000 });
    // Text enthält Zahl (auch wenn 0 von 0 Schülern (0%))
    const text = await subtitle.textContent();
    expect(text).toMatch(/\d+/);
  });
});
