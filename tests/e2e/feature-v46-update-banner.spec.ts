import { test, expect, openAppLoggedIn, DEMO_PASSWORD } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v46: Auto-Versionsprüfung. Die echte Netz-Prüfung läuft nur im Produktiv-Modus;
 * hier wird das Banner über den Test-Hook window.__krsSimulateUpdate() ausgelöst.
 */
test.describe('v46: Update-Banner (Admin)', () => {
  test('Banner erscheint bei neuer Version und lässt sich schließen', async ({ page }) => {
    await openAppLoggedIn(page);
    await page.waitForFunction(() => typeof (window as any).__krsSimulateUpdate === 'function');
    await page.evaluate(() => (window as any).__krsSimulateUpdate('v999'));

    const banner = page.getByTestId('update-banner');
    await expect(banner).toBeVisible();
    await expect(banner).toContainText('v999');
    await expect(page.getByTestId('update-reload')).toBeVisible();

    await page.getByTestId('update-later').click();
    await expect(banner).toHaveCount(0);
  });
});

test.describe('v46: Update-Banner (Schüler-App)', () => {
  test('Banner erscheint auch im Schüler-Frontend', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).__krsSimulateUpdate === 'function');
    await page.evaluate(() => (window as any).__krsSimulateUpdate('v999'));

    const banner = page.getByTestId('update-banner');
    await expect(banner).toBeVisible();
    await expect(banner).toContainText('v999');
    await page.getByTestId('update-later').click();
    await expect(banner).toHaveCount(0);
  });
});
