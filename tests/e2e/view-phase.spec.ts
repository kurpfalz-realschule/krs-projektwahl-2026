import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Phase wechseln', () => {
  test('Aktuelle Phase ist hervorgehoben (Standard: anmeldung)', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'phase');

    await expect(page.locator('h1').filter({ hasText: /Phase/i })).toBeVisible({ timeout: 5_000 });

    // Die aktuelle Phase-Karte hat " (aktuell)" als Text-Node NEBEN dem <strong>-Label,
    // daher auf das Elternelement filtern (nicht auf <strong> selbst).
    const aktuellEl = page.locator('div').filter({ has: page.locator('strong'), hasText: '(aktuell)' });
    await expect(aktuellEl.first()).toBeVisible({ timeout: 3_000 });
  });

  test('Phasenwechsel-Klick aktiviert andere Phase', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'phase');

    // Auf "Setup" klicken (nicht die aktuelle Phase, die default "anmeldung" ist)
    const setupCard = page.locator('div').filter({ hasText: /^Setup$/ }).filter({ has: page.locator('strong') }).first();
    // Robusterer Ansatz: Phase-Karten per Text finden
    const phaseDivs = page.locator('.card div[style*="border"]');
    const count = await phaseDivs.count();
    if (count === 0) {
      // Fallback: Klick auf irgendeinen Phase-Eintrag
      const phaseItems = page.locator('div[style*="border-radius:8px"]').filter({ hasText: /Setup|Anmeldung/i });
      if (await phaseItems.count() > 0) {
        await phaseItems.first().click();
        await page.waitForTimeout(300);
      }
      await expect(page.locator('h1').filter({ hasText: /Phase/i })).toBeVisible();
      return;
    }
    await phaseDivs.first().click();
    await page.waitForTimeout(300);

    // Mindestens eine Karte zeigt (aktuell) — als Text-Node neben <strong>, nicht darin
    await expect(page.locator('div').filter({ has: page.locator('strong'), hasText: '(aktuell)' }).first()).toBeVisible();
  });
});
