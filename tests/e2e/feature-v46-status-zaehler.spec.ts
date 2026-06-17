import { test, expect, openAppLoggedIn, goToSection, loginAs, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v46: „gewählt" vs. „zugeordnet" — Zähler & farbliche Unterscheidung.
 *
 * Kernproblem (Norbert): eine komplett vorab zugeordnete Klasse (5a) wurde in
 * den Übersichten als „0 angemeldet / fehlt" angezeigt, obwohl alle versorgt
 * sind. Jetzt zählen vorab Zugeordnete als „gebucht".
 */

// 5a: 3× vorab zugeordnet (fixiert). 6a: 1 selbst gewählt, 1 zugeordnet, 1 offen.
const MIX = [
  { code: '5A-Z001', vorname: 'Ada', nachname: 'Alpha', klasse: '5a', klassenstufe: 5, hat_gewaehlt: false, zuteilung: 'p1', fixiert: true,  aktiv: true },
  { code: '5A-Z002', vorname: 'Ben', nachname: 'Beta',  klasse: '5a', klassenstufe: 5, hat_gewaehlt: false, zuteilung: 'p1', fixiert: true,  aktiv: true },
  { code: '5A-Z003', vorname: 'Cleo',nachname: 'Gamma', klasse: '5a', klassenstufe: 5, hat_gewaehlt: false, zuteilung: 'p1', fixiert: true,  aktiv: true },
  { code: '6A-G001', vorname: 'Dani',nachname: 'Delta', klasse: '6a', klassenstufe: 6, hat_gewaehlt: true,  zuteilung: null, fixiert: false, aktiv: true },
  { code: '6A-Z002', vorname: 'Eli', nachname: 'Epsil', klasse: '6a', klassenstufe: 6, hat_gewaehlt: false, zuteilung: 'p1', fixiert: true,  aktiv: true },
  { code: '6A-O003', vorname: 'Finn',nachname: 'Zeta',  klasse: '6a', klassenstufe: 6, hat_gewaehlt: false, zuteilung: null, fixiert: false, aktiv: true },
];

test.describe('v46: Status-Zähler (gewählt/zugeordnet/offen)', () => {
  test('Dashboard zählt vorab Zugeordnete als gebucht', async ({ page }) => {
    await openAppLoggedIn(page);
    await seedMockData(page, { schueler: MIX });

    // Tile „Gebucht": 5 von 6 (3× 5a + 1 gewählt + 1 zugeordnet in 6a)
    const tile = page.locator('.dash-tile').filter({ hasText: 'Gebucht' });
    await expect(tile).toContainText('5/6');
    await expect(tile).toContainText('4 zugeordnet');

    // Schnelle-Statistik-Legende
    const card = page.locator('.card').filter({ hasText: 'Schnelle Statistik' });
    await expect(card).toContainText('1 gewählt');
    await expect(card).toContainText('4 zugeordnet');
    await expect(card).toContainText('1 offen');
  });

  test('Anmelde-Status pro Klasse: 5a gilt als fertig (3/3)', async ({ page }) => {
    await openAppLoggedIn(page);
    // AnmeldungenView liest service.listSchueler() → window.MOCK_SCHUELER_LISTE
    await page.evaluate((data) => { (window as any).MOCK_SCHUELER_LISTE = data; }, MIX);
    await goToSection(page, 'anmeldungen');

    const subtitle = page.locator('.main-subtitle').first();
    await expect(subtitle).toContainText('5 von 6 gebucht');
    await expect(subtitle).toContainText('4 zugeordnet');

    // Klasse 5a → 3/3, keine offen
    const row5a = page.locator('.stat-row').filter({ hasText: 'Klasse 5a' });
    await expect(row5a).toContainText('3/3');
    await expect(row5a).toContainText('✓');
    // Klasse 6a → 2/3, 1 offen
    const row6a = page.locator('.stat-row').filter({ hasText: 'Klasse 6a' });
    await expect(row6a).toContainText('2/3');
    await expect(row6a).toContainText('1 offen');
  });

  test('KlassenlehrerView zeigt 📌 Zugeordnet-Badge + zählt es als gebucht', async ({ page }) => {
    await loginAs(page, 'klassenlehrer'); // Mock-Klassenlehrer = 7a
    await seedMockData(page, {
      schueler: [
        { code: '7A-GEW', vorname: 'Gigi', nachname: 'Wahl',  klasse: '7a', klassenstufe: 7, hat_gewaehlt: true,  zuteilung: null, fixiert: false, aktiv: true },
        { code: '7A-ZUO', vorname: 'Zara', nachname: 'Zuord', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: 'p1', fixiert: true,  aktiv: true },
        { code: '7A-OFF', vorname: 'Otto', nachname: 'Offen', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null, fixiert: false, aktiv: true },
      ],
    });

    // 2 von 3 gebucht (1 gewählt + 1 zugeordnet), 1 offen
    const subtitle = page.locator('.main-subtitle');
    await expect(subtitle).toContainText('2 von 3 gebucht');
    await expect(subtitle).toContainText('1 zugeordnet');

    // Zugeordnete Zeile: data-status="zugeordnet" + Badge-Text
    const rowZuo = page.locator('[data-testid="klassenlehrer-row"]').filter({ hasText: 'Zara' });
    await expect(rowZuo).toHaveAttribute('data-status', 'zugeordnet');
    await expect(rowZuo).toContainText('Zugeordnet');
  });

  test('Schüler-Filter „Noch offen" blendet vorab Zugeordnete aus', async ({ page }) => {
    await openAppLoggedIn(page);
    await seedMockData(page, { schueler: MIX });
    await goToSection(page, 'schueler');

    await page.locator('select').filter({ hasText: 'Noch offen' }).first().selectOption('fehlt');
    await page.waitForTimeout(150);
    // Nur der eine echte „offen"-Schüler (Finn), keine zugeordneten
    const rows = page.locator('table tbody tr');
    await expect(rows).toHaveCount(1);
    await expect(rows.first()).toContainText('Finn');
  });
});
