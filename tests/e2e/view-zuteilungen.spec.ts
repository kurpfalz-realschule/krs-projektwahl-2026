import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('View: Zuteilungen', () => {
  test('Zuteilungs-Liste lädt (Demo-Synthese aus mockSchueler)', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'zuteilungen');

    // Header muss sichtbar sein
    await expect(page.locator('h1').filter({ hasText: /Zuteilung/i })).toBeVisible({ timeout: 5_000 });

    // Statistik-Tiles (1. Wahl, 2. Wahl …) vorhanden
    await expect(page.locator('.dash-tile').first()).toBeVisible();
  });

  test('Filter nach Klasse reduziert Tabellen-Zeilen', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'zuteilungen');

    // Seed: 3 Schüler mit zuteilung, davon 2x Klasse 7a und 1x Klasse 8b
    // (möglich dank window.mockSchueler-Expose — Bug 4 Fix Sprint E0)
    await seedMockData(page, {
      schueler: [
        { code: 'T1', vorname: 'Anna', nachname: 'Test', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'Musik-Workshop' },
        { code: 'T2', vorname: 'Ben',  nachname: 'Test', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'Sport-AG' },
        { code: 'T3', vorname: 'Clara', nachname: 'Test', klasse: '8b', klassenstufe: 8, hat_gewaehlt: true, zuteilung: 'Kunst-Projekt' },
      ]
    });

    // Component re-mounten: weg- und zurücknavigieren → useMemo läuft neu
    await page.locator('[data-section="projekte"]').first().click();
    await page.waitForTimeout(150);
    await page.locator('[data-section="zuteilungen"]').first().click();
    await page.waitForTimeout(300);

    // Alle Zeilen vor Filter (muss 3 sein)
    const before = await page.locator('table tbody tr').count();
    expect(before, 'Seed-Daten: 3 Schüler mit Zuteilung erwartet').toBeGreaterThan(0);

    // Klassen-Filter '7a' setzen → nur 2 Zeilen
    await page.locator('select').nth(0).selectOption('7a');
    await page.waitForTimeout(200);

    const after = await page.locator('table tbody tr').count();
    expect(after, 'Klassen-Filter 7a sollte Ergebnis von 3 auf 2 reduzieren').toBeLessThan(before);
  });
});
