import { test, expect, openAppLoggedIn, goToSection, seedMockData } from '../fixtures/app';
import type { Page } from '@playwright/test';

test.describe.configure({ mode: 'serial' });

/**
 * v48.3: Wunsch-Pool in der Zuteilungen-View.
 * Wenn der Projekt-Filter gesetzt ist, erscheint ein read-only Panel mit allen
 * aktiven Schüler:innen, die das Projekt als 1./2./3. Wunsch gewählt haben —
 * inkl. Status: ✓ hier zugeteilt / → aktuelles Projekt / ohne Zuteilung.
 * Demo-Modus: clientseitig aus mockSchueler[*].wahlen + zuteilung.
 */
const PROJEKTE = [
  { id: 'p1', titel: 'Theater-AG',      kurzbeschreibung: '', max_plaetze: 10, min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p2', titel: 'Schach-Club',     kurzbeschreibung: '', max_plaetze: 5,  min_teilnehmer: 3, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
  { id: 'p3', titel: 'Kunst-Werkstatt', kurzbeschreibung: '', max_plaetze: 8,  min_teilnehmer: 4, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
];
const SCHUELER = [
  // hat p1 gewählt UND ist dort zugeteilt → "✓ hier":
  { code: 'A1', vorname: 'Anna', vorname2: '', nachname: 'Adler', klasse: '5a', klassenstufe: 5, hat_gewaehlt: true, zuteilung: 'p1', fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p2', drittwahl_id: 'p3' } },
  // hat p1 als Erstwunsch, ist aber in p2 gelandet → Kandidatin "→ Schach-Club":
  { code: 'B2', vorname: 'Bea', nachname: 'Berg', klasse: '6b', klassenstufe: 6, hat_gewaehlt: true, zuteilung: 'p2', fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p3', drittwahl_id: 'p2' } },
  // hat p1 als Zweitwunsch, in p3 zugeteilt:
  { code: 'C3', vorname: 'Cem', nachname: 'Cakir', klasse: '7c', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'p3', fixiert: false, aktiv: true, wahlen: { erstwahl_id: 'p3', zweitwahl_id: 'p1', drittwahl_id: 'p2' } },
  // inaktiv, hat p1 gewählt — MUSS ausgeschlossen sein:
  { code: 'X9', vorname: 'Xaver', nachname: 'Xander', klasse: '6b', klassenstufe: 6, hat_gewaehlt: true, zuteilung: 'p2', fixiert: false, aktiv: false, wahlen: { erstwahl_id: 'p1', zweitwahl_id: 'p2', drittwahl_id: 'p3' } },
];

async function openZuteilungenGeseedet(page: Page) {
  await openAppLoggedIn(page);
  await goToSection(page, 'zuteilungen');
  await seedMockData(page, { projekte: PROJEKTE, schueler: SCHUELER });
  // Component re-mounten: weg- und zurücknavigieren → useMemo läuft neu
  await page.locator('[data-section="projekte"]').first().click();
  await page.waitForTimeout(150);
  await page.locator('[data-section="zuteilungen"]').first().click();
  await page.waitForTimeout(300);
}

test.describe('v48.3: Wunsch-Pool in Zuteilungen', () => {
  test('Projekt-Filter zeigt Wunsch-Pool mit Status pro Schüler, ohne inaktive', async ({ page }) => {
    await openZuteilungenGeseedet(page);

    // Ohne Projekt-Filter: kein Pool-Panel
    await expect(page.getByTestId('wunsch-pool-card')).toHaveCount(0);

    // Projekt-Filter auf Theater-AG (Filter arbeitet mit Titeln)
    await page.locator('.input-group', { hasText: 'Projekt' }).locator('select').selectOption('Theater-AG');

    const card = page.getByTestId('wunsch-pool-card');
    await expect(card).toBeVisible({ timeout: 10_000 });
    await expect(card).toContainText('Wunsch-Pool: Theater-AG');
    await expect(page.getByTestId('wunsch-pool-liste')).toBeVisible({ timeout: 10_000 });

    // 1. Wunsch p1: Anna (✓ hier) + Bea (→ Schach-Club) — NICHT Xaver (inaktiv)
    const s1 = page.getByTestId('wunsch-pool-spalte-1');
    await expect(s1).toContainText('(2)');
    await expect(s1).toContainText('Anna Adler');
    await expect(s1).toContainText('✓ hier');
    await expect(s1).toContainText('Bea Berg');
    await expect(s1).toContainText('→ Schach-Club');
    await expect(s1).not.toContainText('Xaver');

    // 2. Wunsch p1: Cem (aktuell Kunst-Werkstatt)
    const s2 = page.getByTestId('wunsch-pool-spalte-2');
    await expect(s2).toContainText('(1)');
    await expect(s2).toContainText('Cem Cakir');
    await expect(s2).toContainText('→ Kunst-Werkstatt');

    // 3. Wunsch p1: niemand
    await expect(page.getByTestId('wunsch-pool-spalte-3')).toContainText('(0)');

    // Kandidaten-Summe: 3 Nennungen, 1 bereits hier, 2 Kandidaten
    await expect(card).toContainText('3 Nennungen');
    await expect(card).toContainText('2 potenzielle Kandidaten');
  });

  test('Filter zurücksetzen blendet den Pool aus', async ({ page }) => {
    await openZuteilungenGeseedet(page);

    const projektSelect = page.locator('.input-group', { hasText: 'Projekt' }).locator('select');
    await projektSelect.selectOption('Theater-AG');
    await expect(page.getByTestId('wunsch-pool-card')).toBeVisible({ timeout: 10_000 });

    await projektSelect.selectOption('');
    await expect(page.getByTestId('wunsch-pool-card')).toHaveCount(0);
  });
});
