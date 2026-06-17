import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v46: Projekt-Statistik (Admin) — Belegung/Beliebtheit der Projekte,
 * gewählt vs. vorab zugeordnet, sortiert nach Belegung.
 */
const PROJEKTE = [
  { id: 'p1', titel: 'Theater-AG',  kurzbeschreibung: '', max_plaetze: 10, min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p2', titel: 'Schach-Club', kurzbeschreibung: '', max_plaetze: 5,  min_teilnehmer: 3, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
];
const SCHUELER = [
  { code: 'A1', vorname: 'A', nachname: 'A', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true,  zuteilung: 'p1', fixiert: false, aktiv: true },
  { code: 'A2', vorname: 'B', nachname: 'B', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true,  zuteilung: 'p1', fixiert: false, aktiv: true },
  { code: 'A3', vorname: 'C', nachname: 'C', klasse: '5a', klassenstufe: 5, hat_gewaehlt: false, zuteilung: 'p1', fixiert: true,  aktiv: true },
  { code: 'A4', vorname: 'D', nachname: 'D', klasse: '5a', klassenstufe: 5, hat_gewaehlt: false, zuteilung: 'p1', fixiert: true,  aktiv: true },
  { code: 'B1', vorname: 'E', nachname: 'E', klasse: '6a', klassenstufe: 6, hat_gewaehlt: true,  zuteilung: 'p2', fixiert: false, aktiv: true },
];

test.describe('v46: Statistik-View', () => {
  test('Statistik-Tab zeigt Belegung pro Projekt, nach Beliebtheit sortiert', async ({ page }) => {
    await openAppLoggedIn(page);
    await seedMockData(page, { projekte: PROJEKTE, schueler: SCHUELER });
    await goToSection(page, 'statistik');

    await expect(page.getByTestId('statistik-view')).toBeVisible({ timeout: 15_000 });

    // Kopfzeile: 2 Projekte, 5 Plätze belegt, 2 vorab zugeordnet
    const subtitle = page.locator('.main-subtitle').first();
    await expect(subtitle).toContainText('2 Projekte');
    await expect(subtitle).toContainText('5 Plätze belegt');
    await expect(subtitle).toContainText('2 vorab zugeordnet');

    const rows = page.getByTestId('statistik-row');
    await expect(rows).toHaveCount(2);
    // Sortierung nach Belegung: Theater-AG (4) vor Schach-Club (1)
    await expect(rows.first()).toContainText('Theater-AG');
    await expect(rows.first()).toContainText('4/10');
    await expect(rows.first()).toContainText('📌 2'); // 2 davon vorab zugeordnet
    await expect(rows.nth(1)).toContainText('Schach-Club');
    await expect(rows.nth(1)).toContainText('1/5');
  });
});
