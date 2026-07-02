import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v48: Wünsche-Popover in der Zuteilungen-View — Klick auf die Wahl-Pill
 * zeigt die 1./2./3. Wahl des Schülers; das zugeteilte Projekt ist markiert.
 * Demo-Modus: Daten aus mockSchueler[*].wahlen + mockProjekteData.
 */
const PROJEKTE = [
  { id: 'p1', titel: 'Theater-AG', kurzbeschreibung: '', max_plaetze: 10, min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p2', titel: 'Schach-Club', kurzbeschreibung: '', max_plaetze: 5, min_teilnehmer: 3, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p3', titel: 'Kunst-Werkstatt', kurzbeschreibung: '', max_plaetze: 8, min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
];
const SCHUELER = [
  // zugeteilt auf Zweitwunsch p2:
  { code: 'W1', vorname: 'Wanda', nachname: 'Wunsch', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'p2', fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p2', drittwahl_id: 'p3' } },
  // manuell zugeteilt ohne Wahlen:
  { code: 'M1', vorname: 'Manu', nachname: 'Manuell', klasse: '8b', klassenstufe: 8, hat_gewaehlt: false, zuteilung: 'p3', fixiert: false, aktiv: true, wahlen: null },
];

test.describe('v48: Wünsche-Popover in Zuteilungen', () => {
  test('Klick auf Wahl-Pill zeigt die drei Wünsche, zugeteiltes Projekt markiert', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'zuteilungen');
    await seedMockData(page, { projekte: PROJEKTE, schueler: SCHUELER });

    // Component re-mounten: weg- und zurücknavigieren → useMemo läuft neu
    await page.locator('[data-section="projekte"]').first().click();
    await page.waitForTimeout(150);
    await page.locator('[data-section="zuteilungen"]').first().click();
    await page.waitForTimeout(300);

    // Zeile von Wanda: Wahl-Pill-Button klicken
    const row = page.locator('table tbody tr').filter({ hasText: 'Wanda' });
    await expect(row).toHaveCount(1);
    await row.getByTestId('wahl-popover-btn').click();

    const popover = page.getByTestId('wahlen-popover');
    await expect(popover).toBeVisible({ timeout: 5_000 });
    await expect(popover).toContainText('Wünsche: Wanda Wunsch');

    // Drei Wunsch-Zeilen in Reihenfolge
    const rows = page.getByTestId('wahlen-popover-row');
    await expect(rows).toHaveCount(3);
    await expect(rows.nth(0)).toContainText('Theater-AG');
    await expect(rows.nth(1)).toContainText('Schach-Club');
    await expect(rows.nth(2)).toContainText('Kunst-Werkstatt');

    // Zugeteiltes Projekt (p2 = Schach-Club, Zweitwunsch) ist markiert
    await expect(rows.nth(1)).toContainText('✓ zugeteilt');
    await expect(rows.nth(0)).not.toContainText('✓ zugeteilt');

    // Schließen über X
    await popover.locator('.modal-close').click();
    await expect(popover).not.toBeVisible();
  });

  test('Schüler ohne Wahlen: Popover erklärt manuelle Zuteilung', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'zuteilungen');
    await seedMockData(page, { projekte: PROJEKTE, schueler: SCHUELER });

    await page.locator('[data-section="projekte"]').first().click();
    await page.waitForTimeout(150);
    await page.locator('[data-section="zuteilungen"]').first().click();
    await page.waitForTimeout(300);

    const row = page.locator('table tbody tr').filter({ hasText: 'Manu' });
    await expect(row).toHaveCount(1);
    await row.getByTestId('wahl-popover-btn').click();

    const popover = page.getByTestId('wahlen-popover');
    await expect(popover).toBeVisible({ timeout: 5_000 });
    await expect(popover).toContainText('Keine Wahlen abgegeben');
  });
});
