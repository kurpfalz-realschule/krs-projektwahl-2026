import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * E2E-Flow: UmbuchungView Title→ID Cleanup (Sprint v29 / E1.7)
 *
 * Vor v29 schrieb UmbuchungView den Projekt-Titel in mockSchueler.zuteilung
 * (während KlassenlehrerView seit E1.5 die ID schrieb). v29 vereinheitlicht das
 * auf ID; resolveProjektTitel-Helper bleibt defensiv für Legacy-Title-Daten.
 */
test.describe('Flow: UmbuchungView Title→ID Cleanup (E1.7)', () => {
  test('Demo-Umbuchung speichert mockSchueler.zuteilung als Projekt-ID', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'umbuchung');

    // Seed: 1 veröffentlichtes Projekt + 1 Schüler ohne Zuteilung
    await seedMockData(page, {
      projekte: [
        { id: 'p-umb-1', titel: 'Umbuchungs-Ziel', kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
      ],
      schueler: [
        { code: '7A-UMB1', vorname: 'Uma', nachname: 'Bucher', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
      ],
    });

    // Suche → Treffer-Card auswählen
    const searchInput = page.locator('input[type="text"]').first();
    await searchInput.fill('Uma');
    await page.waitForTimeout(250);
    await page.locator('.card div[style*="cursor"]').filter({ hasText: /Uma/i }).first().click();
    await page.waitForTimeout(200);

    // Projekt im Dropdown auswählen (value = ID)
    const select = page.locator('select').filter({ hasText: 'Umbuchungs-Ziel' }).first();
    await select.selectOption('p-umb-1');

    // Grund eingeben (mind. 10 Zeichen)
    await page.locator('textarea').fill('Test-Umbuchung für E1.7 Cleanup');

    // Bestätigen
    await page.locator('button').filter({ hasText: /Umbuchen/i }).last().click();
    await page.waitForTimeout(400);

    // mockSchueler.zuteilung muss die Projekt-ID sein, nicht der Titel
    const stored = await page.evaluate(() => {
      const s = (window as any).mockSchueler.find((x: any) => x.code === '7A-UMB1');
      return { zuteilung: s?.zuteilung, hat_gewaehlt: s?.hat_gewaehlt };
    });
    expect(stored.zuteilung, 'UmbuchungView muss ab v29 die ID schreiben').toBe('p-umb-1');
    expect(stored.hat_gewaehlt).toBe(true);
  });

  test('UmbuchungView History zeigt Titel (nicht ID) für altes/neues Projekt', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'umbuchung');

    await seedMockData(page, {
      projekte: [
        { id: 'p-alt', titel: 'Altes Projekt',  kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
        { id: 'p-neu', titel: 'Neues Projekt',  kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
      ],
      schueler: [
        // Schüler war schon in 'p-alt' (ID gespeichert) — wird auf 'p-neu' umgebucht.
        { code: '7A-UMB2', vorname: 'Uta', nachname: 'Wechsel', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'p-alt' },
      ],
    });

    const searchInput = page.locator('input[type="text"]').first();
    await searchInput.fill('Uta');
    await page.waitForTimeout(250);
    await page.locator('.card div[style*="cursor"]').filter({ hasText: /Uta/i }).first().click();
    await page.waitForTimeout(200);

    // Bestätigt: aktuelle Zuteilung im UI zeigt Titel (über resolveProjektTitel),
    // nicht die rohe ID 'p-alt'.
    await expect(page.locator('strong').filter({ hasText: 'Altes Projekt' })).toBeVisible();

    await page.locator('select').filter({ hasText: 'Neues Projekt' }).first().selectOption('p-neu');
    await page.locator('textarea').fill('Wechsel auf Neues Projekt für Test');
    await page.locator('button').filter({ hasText: /Umbuchen/i }).last().click();
    await page.waitForTimeout(400);

    // History-Eintrag in mockUmbuchungen: altes_projekt = 'Altes Projekt' (Titel),
    // neues_projekt = 'Neues Projekt' (Titel). Beide aufgelöst trotz ID-Speicherung.
    const lastEntry = await page.evaluate(() => {
      const log = (window as any).mockUmbuchungen || [];
      return log[log.length - 1] || null;
    });
    expect(lastEntry?.altes_projekt).toBe('Altes Projekt');
    expect(lastEntry?.neues_projekt).toBe('Neues Projekt');
  });

  test('ZuteilungenView Demo-Synthese resolvt sowohl ID als auch Legacy-Titel', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'zuteilungen');

    await seedMockData(page, {
      projekte: [
        { id: 'p-id1', titel: 'ID-Projekt',     kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
        { id: 'p-id2', titel: 'Titel-Projekt',  kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
      ],
      schueler: [
        // Schüler A hat ID-Zuteilung (v29-Stil)
        { code: 'TX-A', vorname: 'Adam',  nachname: 'Test', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'p-id1' },
        // Schüler B hat Legacy-Title-Zuteilung (pre-v29-Stil)
        { code: 'TX-B', vorname: 'Berta', nachname: 'Test', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'Titel-Projekt' },
      ],
    });

    // Re-mount: weg- und zurücknavigieren → useMemo läuft neu
    await page.locator('[data-section="projekte"]').first().click();
    await page.waitForTimeout(150);
    await page.locator('[data-section="zuteilungen"]').first().click();
    await page.waitForTimeout(300);

    // Beide Schüler erscheinen mit ihren Projekt-Titeln (nicht roh-IDs)
    const adamRow = page.locator('table tbody tr').filter({ hasText: 'Adam' });
    const bertaRow = page.locator('table tbody tr').filter({ hasText: 'Berta' });
    await expect(adamRow).toContainText('ID-Projekt');
    await expect(bertaRow).toContainText('Titel-Projekt');
    // Roh-ID darf NICHT angezeigt werden
    await expect(adamRow).not.toContainText('p-id1');
  });
});
