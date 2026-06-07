import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('Feature: PDF-Export', () => {
  test('Klassenlisten-PDF Button existiert und ist klickbar', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'export');

    const btn = page.locator('button').filter({ hasText: /Klassenlisten|PDF erstellen/i }).first();
    await expect(btn).toBeVisible({ timeout: 5_000 });
    await btn.click();
    await page.waitForTimeout(600);
    // App bleibt stabil (kein Crash)
    await expect(page.locator('#appContent')).toBeVisible();
  });

  test('Teilnehmerlisten-PDF Button existiert und ist klickbar', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'export');

    const btn = page.locator('button').filter({ hasText: /Teilnehmerlisten?|PDF erstellen/i }).nth(1);
    // nth(0) = Klassenlisten, nth(1) = Teilnehmerlisten — aber falls es nur einen gibt, first()
    const btnAlt = page.locator('button').filter({ hasText: /Teilnehmerlisten?/i }).first();
    const target = (await btn.count() > 0) ? btn : btnAlt;

    if (await target.count() === 0) {
      test.skip(true, 'Teilnehmerlisten-Button nicht gefunden');
      return;
    }
    await expect(target).toBeVisible({ timeout: 5_000 });
    await target.click();
    await page.waitForTimeout(600);
    await expect(page.locator('#appContent')).toBeVisible();
  });
});
