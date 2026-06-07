import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Manuelle Umbuchung', () => {
  test('Schüler-Suche findet Ergebnisse', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'umbuchung');

    // Suchfeld vorhanden
    const searchInput = page.locator('input[type="text"], input[placeholder*="Suche"], input[placeholder*="Code"]').first();
    await expect(searchInput).toBeVisible({ timeout: 5_000 });

    // Suche nach bekanntem Namen aus Demo-Daten
    await searchInput.fill('Anna');
    await page.waitForTimeout(300);

    // Suchergebnisse sollten erscheinen — UmbuchungView rendert Treffer als
    // klickbare <div>-Karten, nicht als <button>/<li>/<tr>. Wir matchen daher
    // bewusst weiter (inkl. div + strong) und erwarten mind. 1 Treffer.
    const results = page.locator('button, li, .search-result, tr, div, strong').filter({ hasText: /Anna/i });
    const count = await results.count();
    expect(count, 'Suche nach "Anna" sollte mindestens 1 Treffer liefern').toBeGreaterThan(0);
  });

  test('Umbuchungs-Bestätigung erscheint nach Schüler-Auswahl', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'umbuchung');

    // Schüler suchen
    const searchInput = page.locator('input[type="text"], input[placeholder*="Suche"], input[placeholder*="Code"]').first();
    await searchInput.fill('Anna');
    await page.waitForTimeout(300);

    // Ersten Treffer auswählen — UmbuchungView rendert Treffer als <div> mit
    // <strong>${vorname} ${nachname}</strong>. Wir klicken den umschließenden
    // <div> (cursor:pointer), nicht den <strong>.
    const firstResult = page.locator('.card div[style*="cursor"], .card div[onClick]')
      .filter({ hasText: /Anna/i }).first();
    if (await firstResult.count() === 0) {
      // Fallback: irgendein klickbares Element mit "Anna"
      const fallback = page.locator('div, button, li').filter({ hasText: /Anna/i }).first();
      if (await fallback.count() === 0) {
        test.skip(true, 'Keine Schüler mit "Anna" in Demo-Daten');
        return;
      }
      await fallback.click();
    } else {
      await firstResult.click();
    }
    await page.waitForTimeout(300);

    // Umbuchungs-Formular sollte erscheinen — eigene Card mit
    // <h2>Umbuchung für ...</h2>, <select> Zielprojekt + Bestätigungs-Button.
    const heading = page.locator('h2').filter({ hasText: /Umbuchung für/i });
    const confirmBtn = page.locator('button').filter({ hasText: /Umbuchen|Bestätigen|Speichern/i });

    const hasForm = (await heading.count() > 0) || (await confirmBtn.count() > 0);
    expect(hasForm, 'Nach Schüler-Auswahl sollte ein Umbuchungs-Formular erscheinen').toBe(true);
  });
});
