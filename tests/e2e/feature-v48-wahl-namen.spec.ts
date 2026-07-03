import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v48: Namentliche Wunsch-Liste pro Projekt (Admin/Projektleitung).
 * Ergänzt die aggregierte v47-Statistik um die Einzelnamen — für die
 * manuelle Nachbearbeitung (passende Umbuchungs-Kandidaten finden).
 * Demo-Modus: clientseitig aus mockSchueler[*].wahlen. Rein lesend.
 * Sichtbar nur in der Statistik-Section → super_admin + projektleitung.
 */
const PROJEKTE = [
  { id: 'p1', titel: 'Theater-AG',      kurzbeschreibung: '', max_plaetze: 10, min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p2', titel: 'Schach-Club',     kurzbeschreibung: '', max_plaetze: 5,  min_teilnehmer: 3, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p3', titel: 'Kunst-Werkstatt', kurzbeschreibung: '', max_plaetze: 8,  min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
];
const SCHUELER = [
  { code: 'A1', vorname: 'Anna',  nachname: 'Adler', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true,  wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p2', drittwahl_id: 'p3' } },
  { code: 'A2', vorname: 'Bea',   nachname: 'Berg',  klasse: '5a', klassenstufe: 5, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true,  wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p3', drittwahl_id: 'p2' } },
  { code: 'A3', vorname: 'Cem',   nachname: 'Cakir', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true,  wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p2', drittwahl_id: 'p3' } },
  { code: 'A4', vorname: 'Dirk',  nachname: 'Dorn',  klasse: '6a', klassenstufe: 6, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: true,  wahlen: { erstwahl_id: 'p2', zweitwahl_id: 'p1', drittwahl_id: 'p3' } },
  // inaktiver Schüler mit Wahl auf p1 — MUSS aus der Namensliste ausgeschlossen sein:
  { code: 'X9', vorname: 'Xaver', nachname: 'Xander', klasse: '6a', klassenstufe: 6, hat_gewaehlt: true, zuteilung: null, fixiert: false, aktiv: false, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p3', drittwahl_id: 'p2' } },
];

test.describe('v48: Namentliche Wunsch-Liste', () => {
  test('Projekt wählen zeigt Namen nach 1./2./3. Wunsch, ohne inaktive', async ({ page }) => {
    await openAppLoggedIn(page);
    await seedMockData(page, { projekte: PROJEKTE, schueler: SCHUELER });
    await goToSection(page, 'statistik');

    const card = page.getByTestId('wahl-namen-card');
    await expect(card).toBeVisible({ timeout: 15_000 });

    // Vor Auswahl: kein Namen-Grid, nur Hinweis
    await expect(page.getByTestId('wahl-namen-liste')).toHaveCount(0);

    // Theater-AG (p1) wählen
    await page.getByTestId('wahl-namen-select').selectOption('p1');
    await expect(page.getByTestId('wahl-namen-liste')).toBeVisible({ timeout: 10_000 });

    const s1 = page.getByTestId('wahl-namen-spalte-1');
    const s2 = page.getByTestId('wahl-namen-spalte-2');
    const s3 = page.getByTestId('wahl-namen-spalte-3');

    // 1. Wunsch p1: Anna, Bea, Cem (3) — NICHT Xaver (inaktiv)
    await expect(s1).toContainText('(3)');
    await expect(s1).toContainText('Anna Adler');
    await expect(s1).toContainText('Bea Berg');
    await expect(s1).toContainText('Cem Cakir');
    await expect(s1).not.toContainText('Xaver');

    // 2. Wunsch p1: nur Dirk (A4 hat p1 als Zweitwahl)
    await expect(s2).toContainText('(1)');
    await expect(s2).toContainText('Dirk Dorn');

    // 3. Wunsch p1: niemand
    await expect(s3).toContainText('(0)');
  });

  test('Filter grenzt die Namensliste ein', async ({ page }) => {
    await openAppLoggedIn(page);
    await seedMockData(page, { projekte: PROJEKTE, schueler: SCHUELER });
    await goToSection(page, 'statistik');

    await page.getByTestId('wahl-namen-select').selectOption('p1');
    await expect(page.getByTestId('wahl-namen-liste')).toBeVisible({ timeout: 10_000 });

    // Filter '6a' → im 1. Wunsch (nur 5a-Schüler) bleibt niemand, im 2. Wunsch bleibt Dirk (6a)
    await page.getByTestId('wahl-namen-filter').fill('6a');
    await expect(page.getByTestId('wahl-namen-spalte-1')).toContainText('(0)');
    await expect(page.getByTestId('wahl-namen-spalte-2')).toContainText('(1)');
    await expect(page.getByTestId('wahl-namen-spalte-2')).toContainText('Dirk Dorn');
  });
});
