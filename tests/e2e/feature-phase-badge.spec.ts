import { test, expect, openAppLoggedIn } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('Feature: Phase-Badge', () => {
  test('Phase-Badge ist im main-Bereich sichtbar', async ({ page }) => {
    await openAppLoggedIn(page);

    // PhaseBadge ist position:absolute oben rechts im main
    // Zeigt "📅 <Phase-Label>"
    const badge = page.locator('span').filter({ hasText: /📅/ }).first();
    await expect(badge).toBeVisible({ timeout: 5_000 });
  });

  test('Klick auf Phase-Badge navigiert zur Phase-View', async ({ page }) => {
    await openAppLoggedIn(page);

    const badge = page.locator('span').filter({ hasText: /📅/ }).first();
    if (await badge.count() === 0) {
      test.skip(true, 'Phase-Badge nicht gefunden');
      return;
    }
    await badge.click();
    await page.waitForTimeout(300);

    // Nach Klick: Phase-View sollte aktiv sein
    await expect(page.locator('h1').filter({ hasText: /Phase/i })).toBeVisible({ timeout: 3_000 });
  });
});
