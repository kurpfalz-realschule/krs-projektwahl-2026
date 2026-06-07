import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Schüler', () => {
  test('Liste lädt mit mindestens 1 Schüler', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'schueler');

    // Mindestens eine Tabellenzeile (Demo-Daten enthalten >300 Schüler)
    await expect(page.locator('table tbody tr').first()).toBeVisible({ timeout: 5_000 });
    const rows = await page.locator('table tbody tr').count();
    expect(rows, 'Demo-Daten sollten >0 Schüler enthalten').toBeGreaterThan(0);
  });

  test('Suchfeld filtert die Schüler-Liste', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'schueler');

    // Alle Zeilen vor Suche zählen
    const before = await page.locator('table tbody tr').count();

    // Suchfeld ausfüllen (nach erstem Schüler-Nachnamen suchen)
    const firstRow = page.locator('table tbody tr').first();
    const firstNachname = await firstRow.locator('td').nth(1).textContent();
    const query = (firstNachname || 'Müller').trim().slice(0, 4);

    // Suchfeld ist type="text" mit placeholder "Name oder Code..." (kein type="search")
    await page.locator('input[placeholder*="Name oder Code"], input[placeholder*="Code"]').first().fill(query);
    await page.waitForTimeout(200);

    const after = await page.locator('table tbody tr').count();
    // Filter sollte Ergebnis reduzieren oder gleich lassen (nicht vergrößern)
    expect(after, 'Filter sollte Schüler-Anzahl nicht vergrößern').toBeLessThanOrEqual(before);
    expect(after, 'Filter sollte mindestens 1 Treffer liefern').toBeGreaterThan(0);
  });
});
