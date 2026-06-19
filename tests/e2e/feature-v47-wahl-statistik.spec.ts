import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v47: Wahl-Statistik (Admin/Projektleitung) — zeigt, WIE OFT jedes Projekt
 * tatsächlich gewählt wurde (Erst-/Zweit-/Drittwahl), unabhängig von der
 * Verlosung. Demo-Modus: aggregiert clientseitig aus mockSchueler[*].wahlen.
 */
const PROJEKTE = [
  { id: 'p1', titel: 'Theater-AG', kurzbeschreibung: '', max_plaetze: 10, min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p2', titel: 'Schach-Club', kurzbeschreibung: '', max_plaetze: 5, min_teilnehmer: 3, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p3', titel: 'Kunst-Werkstatt', kurzbeschreibung: '', max_plaetze: 8, min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
];
const SCHUELER = [
  { code: 'A1', vorname: 'A', nachname: 'A', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p2', drittwahl_id: 'p3' } },
  { code: 'A2', vorname: 'B', nachname: 'B', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p3', drittwahl_id: 'p2' } },
  { code: 'A3', vorname: 'C', nachname: 'C', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p2', drittwahl_id: 'p3' } },
  { code: 'A4', vorname: 'D', nachname: 'D', klasse: '6a', klassenstufe: 6, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p2', zweitwahl_id: 'p1', drittwahl_id: 'p3' } },
  // inaktiver Schüler mit Wahl — MUSS aus der Statistik ausgeschlossen sein:
  { code: 'X9', vorname: 'X', nachname: 'X', klasse: '6a', klassenstufe: 6, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: false, wahlen: { erstwahl_id: 'p3', zweitwahl_id: 'p1', drittwahl_id: 'p2' } },
];

test.describe('v47: Wahl-Statistik', () => {
  test('Statistik-Tab zeigt Erst-/Zweit-/Drittwahl pro Projekt, nach Erstwahl sortiert', async ({ page }) => {
    await openAppLoggedIn(page);
    await seedMockData(page, { projekte: PROJEKTE, schueler: SCHUELER });
    await goToSection(page, 'statistik');

    const card = page.getByTestId('wahl-statistik');
    await expect(card).toBeVisible({ timeout: 15_000 });

    const rows = page.getByTestId('wahl-statistik-row');
    await expect(rows).toHaveCount(3);

    // Sortierung nach Erstwahl: Theater-AG (3) > Schach-Club (1) > Kunst-Werkstatt (0)
    await expect(rows.nth(0)).toContainText('Theater-AG');
    await expect(rows.nth(0)).toContainText('★ 3');
    await expect(rows.nth(1)).toContainText('Schach-Club');
    await expect(rows.nth(1)).toContainText('★ 1');
    await expect(rows.nth(2)).toContainText('Kunst-Werkstatt');
    await expect(rows.nth(2)).toContainText('★ 0');

    // Breakdown Theater-AG (p1): ★3 (A1,A2,A3) · ② 1 (A4 zweit p1) · ③ 0
    await expect(rows.nth(0)).toContainText('② 1');
    await expect(rows.nth(0)).toContainText('③ 0');

    // Gesamt: 4 aktive Schüler × 3 Wahlen = 12 Nennungen (inaktiver X9 NICHT gezählt)
    await expect(card).toContainText('Gesamt 12 Nennungen');
  });
});
