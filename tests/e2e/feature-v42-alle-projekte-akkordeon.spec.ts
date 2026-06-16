import { test, expect, loginAs } from '../fixtures/app';

/**
 * v42-Feature (Demo-Modus, hermetisch):
 * Aufklappbare Projektbeschreibung in der Lehrer-Leseansicht "📖 Alle Projekte".
 *
 * Jede Projektzeile hat ein Chevron (▸/▾). Klick klappt eine Detailzeile
 * (kurz- + langbeschreibung, td[colspan=5]) auf bzw. wieder zu (Akkordeon,
 * default zu). Mehrere Zeilen können gleichzeitig offen sein.
 */

test.describe('v42: Alle Projekte — aufklappbare Beschreibung', () => {
  test('Chevron-Klick klappt Beschreibung auf und wieder zu', async ({ page }) => {
    await loginAs(page, 'projektlehrer');

    const nav = page.locator('[data-section="alle-projekte"]').first();
    await expect(nav).toBeVisible({ timeout: 10_000 });
    await nav.click();
    await page.waitForTimeout(200);

    await expect(page.locator('.main-title', { hasText: 'Alle Projekte' })).toBeVisible();

    const table = page.locator('table');
    const firstToggle = table.locator('tbody tr button[aria-expanded]').first();
    await expect(firstToggle).toBeVisible();

    // Default: zugeklappt — keine Detailzeile sichtbar, Chevron zeigt ▸
    await expect(firstToggle).toContainText('▸');
    await expect(table.locator('td[colspan="5"]')).toHaveCount(0);

    // Aufklappen → Detailzeile mit Beschreibung erscheint, Chevron zeigt ▾
    await firstToggle.click();
    await page.waitForTimeout(150);
    await expect(firstToggle).toHaveAttribute('aria-expanded', 'true');
    await expect(firstToggle).toContainText('▾');
    await expect(table.locator('td[colspan="5"]').first()).toBeVisible();

    // Wieder zuklappen → Detailzeile verschwindet
    await firstToggle.click();
    await page.waitForTimeout(150);
    await expect(firstToggle).toContainText('▸');
    await expect(table.locator('td[colspan="5"]')).toHaveCount(0);
  });

  test('Akkordeon: mehrere Zeilen gleichzeitig offen', async ({ page }) => {
    await loginAs(page, 'projektlehrer');

    const nav = page.locator('[data-section="alle-projekte"]').first();
    await nav.click();
    await page.waitForTimeout(200);

    const table = page.locator('table');
    const toggles = table.locator('tbody tr button[aria-expanded]');
    const count = await toggles.count();
    expect(count, 'Demo sollte mehrere Projekte zeigen').toBeGreaterThan(1);

    // Zwei Zeilen öffnen — beide bleiben offen (kein Single-Open-Akkordeon)
    await toggles.nth(0).click();
    await page.waitForTimeout(100);
    await toggles.nth(1).click();
    await page.waitForTimeout(150);

    await expect(table.locator('td[colspan="5"]')).toHaveCount(2);
  });
});
