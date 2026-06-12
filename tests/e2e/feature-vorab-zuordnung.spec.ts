import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v38: Vorab-Zuordnung — ganze Klassen / Gruppen vor der Verlosung
 * fest einem Projekt zuordnen.
 *
 * Abgedeckt:
 *  1. Mehrfach-Klassenfilter (z.B. 7a UND 7d gleichzeitig)
 *  2. Bulk-Zuordnung über Checkbox-Auswahl → Modal → Projekt
 *  3. Bulk-Aufheben
 *  4. Demo-Verlosung überspringt fixierte Schüler + rechnet Plätze an
 *  5. CSV-Export der Schülerliste
 *  6. Schüler-App: vorab zugeordneter Schüler sieht sein Projekt,
 *     kein Wahlformular, kein Tauschwunsch (Phase anmeldung)
 */

// 6 Test-Schüler: 3× 7a, 1× 7b, 2× 7d — für den Mehrfach-Filter
const SCHUELER_7ABD = [
  { code: '7A-T0001', vorname: 'Ali',   nachname: 'Aydin',   klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
  { code: '7A-T0002', vorname: 'Bea',   nachname: 'Braun',   klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
  { code: '7A-T0003', vorname: 'Cem',   nachname: 'Celik',   klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
  { code: '7B-T0004', vorname: 'Dora',  nachname: 'Dietz',   klasse: '7b', klassenstufe: 7, hat_gewaehlt: true,  zuteilung: null },
  { code: '7D-T0005', vorname: 'Emil',  nachname: 'Ernst',   klasse: '7d', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
  { code: '7D-T0006', vorname: 'Fina',  nachname: 'Fuchs',   klasse: '7d', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
];

async function openSchuelerTabMitSeed(page: any) {
  await openAppLoggedIn(page);
  await goToSection(page, 'schueler');
  await seedMockData(page, { schueler: SCHUELER_7ABD });
}

async function filtere7aUnd7d(page: any) {
  const filter = page.getByTestId('klassen-filter');
  await filter.locator('summary').click();
  await filter.locator('label').filter({ hasText: /^7A$/i }).locator('input').check();
  await filter.locator('label').filter({ hasText: /^7D$/i }).locator('input').check();
  // Dropdown schließen (Klick außerhalb)
  await page.locator('h1').first().click();
  await page.waitForTimeout(150);
}

test.describe('v38: Vorab-Zuordnung (Admin)', () => {
  test('Mehrfach-Klassenfilter: 7a + 7d gleichzeitig zeigt genau 5 Schüler', async ({ page }) => {
    await openSchuelerTabMitSeed(page);
    await filtere7aUnd7d(page);

    const rows = page.locator('table tbody tr');
    await expect(rows).toHaveCount(5); // 3× 7a + 2× 7d, die 7b-Schülerin nicht
    await expect(page.locator('table tbody')).not.toContainText('Dora');
  });

  test('Bulk-Zuordnung: gefilterte Klassen auswählen → Projekt zuordnen → Status 📌', async ({ page }) => {
    await openSchuelerTabMitSeed(page);
    await filtere7aUnd7d(page);

    // Kopf-Checkbox: alle 5 sichtbaren auswählen
    await page.locator('thead input[type="checkbox"]').check();
    await expect(page.locator('text=5 Schüler ausgewählt')).toBeVisible();

    // Modal öffnen, Projekt p3 (Weinberg-AG, Kl. 7–10) wählen
    await page.getByTestId('bulk-assign-open').click();
    await expect(page.getByTestId('bulk-assign-modal')).toBeVisible();
    await page.getByTestId('bulk-assign-projekt').selectOption('p3');
    await page.getByTestId('bulk-assign-confirm').click();

    // Erfolgs-Toast + Tabelle zeigt 📌 zugeordnet + Projekttitel
    await expect(page.locator('.toast.success, .toast.info')).toBeVisible({ timeout: 3_000 });
    await expect(page.locator('table tbody tr').filter({ hasText: 'Ali' })).toContainText('zugeordnet');
    await expect(page.locator('table tbody tr').filter({ hasText: 'Ali' })).toContainText('Weinberg');

    // Mock-State: alle 5 fixiert auf p3
    const fixierte = await page.evaluate(() =>
      (window as any).mockSchueler.filter((s: any) => s.fixiert && s.zuteilung === 'p3').map((s: any) => s.code)
    );
    expect(fixierte.sort()).toEqual(['7A-T0001', '7A-T0002', '7A-T0003', '7D-T0005', '7D-T0006']);
  });

  test('Bulk-Aufheben: Zuordnung wieder entfernen', async ({ page }) => {
    await openSchuelerTabMitSeed(page);

    // Direkt fixiert seeden (2 Schüler auf p3)
    await page.evaluate(() => {
      const list = (window as any).mockSchueler;
      ['7A-T0001', '7D-T0005'].forEach((code: string) => {
        const s = list.find((x: any) => x.code === code);
        s.zuteilung = 'p3'; s.fixiert = true;
      });
      window.dispatchEvent(new Event('krs:mock-seeded'));
    });
    await page.waitForTimeout(150);

    // Beide auswählen, aufheben (confirm-Dialog bestätigen)
    await page.locator('table tbody tr').filter({ hasText: 'Ali' }).locator('input[type="checkbox"]').check();
    await page.locator('table tbody tr').filter({ hasText: 'Emil' }).locator('input[type="checkbox"]').check();
    page.once('dialog', d => d.accept());
    await page.getByTestId('bulk-unassign').click();

    await expect(page.locator('.toast.success')).toBeVisible({ timeout: 3_000 });
    const nochFixiert = await page.evaluate(() =>
      (window as any).mockSchueler.filter((s: any) => s.fixiert).length
    );
    expect(nochFixiert).toBe(0);
  });

  test('Demo-Verlosung: fixierte Schüler werden übersprungen, Plätze angerechnet', async ({ page }) => {
    await openAppLoggedIn(page);
    await seedMockData(page, { schueler: SCHUELER_7ABD });

    // 2 Schüler fixiert auf p3 setzen, dann Verlosung (Preview) laufen lassen
    const result = await page.evaluate(async () => {
      const win = window as any;
      ['7A-T0001', '7D-T0005'].forEach((code: string) => {
        const s = win.mockSchueler.find((x: any) => x.code === code);
        s.zuteilung = 'p3'; s.fixiert = true;
      });
      const service = new win.KrsDataService();
      return await service.runVerteilung({ seed: 'test-v38', commit: false });
    });

    expect(result.success).toBe(true);
    expect(result.statistik.fixiert).toBe(2);

    // Fixierte tauchen im Ergebnis auf (wahl_nr null, fixiert true) …
    const fixierteImErgebnis = result.zuteilungen.filter((z: any) => z.fixiert);
    expect(fixierteImErgebnis.map((z: any) => z.schueler_code).sort()).toEqual(['7A-T0001', '7D-T0005']);
    fixierteImErgebnis.forEach((z: any) => expect(z.wahl_nr).toBeNull());

    // … und ihre Plätze sind in der Belegung von p3 enthalten
    expect(result.belegung['p3']).toBeGreaterThanOrEqual(2);

    // Kein fixierter Schüler wurde zusätzlich verlost
    const verlost = result.zuteilungen.filter((z: any) => !z.fixiert);
    expect(verlost.some((z: any) => z.schueler_code === '7A-T0001')).toBe(false);
  });

  test('CSV-Export lädt eine Datei mit den Schülerdaten herunter', async ({ page }) => {
    await openSchuelerTabMitSeed(page);

    const downloadPromise = page.waitForEvent('download');
    await page.getByTestId('csv-export').click();
    const download = await downloadPromise;

    expect(download.suggestedFilename()).toMatch(/^schueler-export-\d{4}-\d{2}-\d{2}\.csv$/);
    await expect(page.locator('.toast.success')).toBeVisible({ timeout: 3_000 });
  });
});

test.describe('v38: Vorab-Zuordnung (Schüler-App)', () => {
  test('Vorab zugeordneter Schüler sieht sein Projekt — kein Wahlformular, kein Tauschwunsch', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    // Anna (8A-T4P1, hat_gewaehlt=false) bekommt eine fixe Zuordnung zu p2
    // (Theater-Werkstatt) — wahl_nr null = manuell/vorab zugeteilt
    await page.evaluate(() => {
      (window as any).MOCK_SCHUELER['8A-T4P1'].status = {
        hat_gewaehlt: false,
        zuteilung: { projekt_id: 'p2', wahl_nr: null }
      };
    });

    await page.locator('button').filter({ hasText: /Anmeldung starten/i }).click();
    await page.locator('#code-input').fill('8A-T4P1');
    await page.locator('button').filter({ hasText: /Weiter/i }).click();

    // Direkt das Ergebnis statt Bestätigung/Wahlformular (Phase: anmeldung)
    await expect(page.locator('.ergebnis-projekt-titel')).toContainText('Theater', { timeout: 5_000 });
    await expect(page.locator('h2').filter({ hasText: /Bist du das/i })).toHaveCount(0);

    // Hinweistext für Direkt-Zuteilung, kein Tauschwunsch-Button in der Anmeldephase
    await expect(page.locator('.alert-info')).toContainText(/direkt zugeteilt/i);
    await expect(page.locator('button').filter({ hasText: /Tauschwunsch/i })).toHaveCount(0);
  });
});
