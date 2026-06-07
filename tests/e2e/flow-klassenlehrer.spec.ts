import { test, expect, loginAs, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * E2E-Flow: KlassenlehrerView (v27 / Sprint E1)
 *
 * Testet:
 *  - Login als klassenlehrer landet automatisch in "Meine Klasse"
 *  - Schüler werden nach `klassenlehrer_von` der eigenen User-Row gefiltert
 *  - Anmelde-Status (hat_gewaehlt) wird korrekt angezeigt
 *  - Zähler im Header (X von Y angemeldet, %) stimmt
 */
test.describe('Flow: KlassenlehrerView', () => {
  test('Login als klassenlehrer → Default-Section "Meine Klasse"', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');

    // Header der KlassenlehrerView
    await expect(page.locator('h1').filter({ hasText: /Meine Klasse/i })).toBeVisible({ timeout: 5_000 });

    // Mock-Klassenlehrer u23 ist Klassenlehrer von 7a
    await expect(page.locator('h1')).toContainText('7A');
  });

  test('Tabelle zeigt nur Schüler der eigenen Klasse', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');
    await page.waitForTimeout(200);

    const rows = page.locator('[data-testid="klassenlehrer-row"]');
    const count = await rows.count();
    expect(count, 'Mindestens 1 Schüler in 7a erwartet').toBeGreaterThan(0);

    // Keiner der Codes darf mit einer anderen Klasse beginnen
    // Codes haben das Schema "<KLASSE>-<ID>", z.B. "7A-H6RD"
    for (let i = 0; i < count; i++) {
      const code = await rows.nth(i).locator('code').textContent();
      expect(code?.toUpperCase()).toMatch(/^7A-/);
    }
  });

  test('Anmelde-Status wird korrekt angezeigt', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');

    // Setze 2 Schüler aus 7a auf hat_gewaehlt: true
    await seedMockData(page, {
      schueler: [
        { code: '7A-AAAA', vorname: 'Anna', nachname: 'Anders', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true,  zuteilung: null },
        { code: '7A-BBBB', vorname: 'Ben',  nachname: 'Berger', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
        { code: '8B-CCCC', vorname: 'Carla',nachname: 'Conrad', klasse: '8b', klassenstufe: 8, hat_gewaehlt: true,  zuteilung: null },
      ],
    });

    // Subtitle sollte "1 von 2 angemeldet (50%) · 1 offen" zeigen
    const subtitle = page.locator('.main-subtitle');
    await expect(subtitle).toContainText(/1 von 2/);
    await expect(subtitle).toContainText(/50%/);

    // 7a-Schüler sind in Tabelle, 8b nicht
    await expect(page.locator('[data-testid="klassenlehrer-row"]')).toHaveCount(2);
    const codes = await page.locator('[data-testid="klassenlehrer-row"] code').allTextContents();
    expect(codes).toEqual(expect.arrayContaining(['7A-AAAA', '7A-BBBB']));
    expect(codes).not.toContain('8B-CCCC');

    // Status-Badges: 1× "Angemeldet", 1× "Offen"
    const angemeldet = page.locator('[data-testid="klassenlehrer-row"][data-status="angemeldet"]');
    const offen = page.locator('[data-testid="klassenlehrer-row"][data-status="offen"]');
    await expect(angemeldet).toHaveCount(1);
    await expect(offen).toHaveCount(1);
  });

  test('E1.5: Klassenlehrer weist offenen Schüler einem Projekt zu', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');
    await seedMockData(page, {
      projekte: [
        { id: 'p-zu-1', titel: 'Direkt-Test-Projekt', kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
      ],
      schueler: [
        { code: '7A-OFFEN', vorname: 'Otto', nachname: 'Offen', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
      ],
    });

    const row = page.locator('[data-testid="klassenlehrer-row"]').filter({ has: page.locator('code', { hasText: '7A-OFFEN' }) });
    await expect(row).toHaveAttribute('data-status', 'offen');

    const select = row.locator('[data-testid="klassenlehrer-zuteilung-select"]');
    await select.selectOption('p-zu-1');

    // Status flippt auf 'angemeldet', Header-Counter zieht mit
    await expect(row).toHaveAttribute('data-status', 'angemeldet');
    await expect(page.locator('.main-subtitle')).toContainText(/1 von 1/);
    await expect(page.locator('.main-subtitle')).toContainText(/100%/);

    // mockSchueler.zuteilung ist die Projekt-ID (nicht der Titel)
    const stored = await page.evaluate(() => {
      const s = (window as any).mockSchueler.find((x: any) => x.code === '7A-OFFEN');
      return { zuteilung: s?.zuteilung, hat_gewaehlt: s?.hat_gewaehlt };
    });
    expect(stored.zuteilung).toBe('p-zu-1');
    expect(stored.hat_gewaehlt).toBe(true);
  });

  test('E1.5: Klassenlehrer kann Zuteilung wieder entfernen', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');
    await seedMockData(page, {
      projekte: [
        { id: 'p-zu-2', titel: 'Wegnehmen-Test', kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'veroeffentlicht' },
      ],
      schueler: [
        { code: '7A-DRIN', vorname: 'Dora', nachname: 'Drin', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: 'p-zu-2' },
      ],
    });

    const row = page.locator('[data-testid="klassenlehrer-row"]').filter({ has: page.locator('code', { hasText: '7A-DRIN' }) });
    await expect(row).toHaveAttribute('data-status', 'angemeldet');

    const select = row.locator('[data-testid="klassenlehrer-zuteilung-select"]');
    await select.selectOption('');

    await expect(row).toHaveAttribute('data-status', 'offen');
    await expect(page.locator('.main-subtitle')).toContainText(/0 von 1/);

    const stored = await page.evaluate(() => {
      const s = (window as any).mockSchueler.find((x: any) => x.code === '7A-DRIN');
      return { zuteilung: s?.zuteilung, hat_gewaehlt: s?.hat_gewaehlt };
    });
    expect(stored.zuteilung).toBeNull();
    expect(stored.hat_gewaehlt).toBe(false);
  });

  test('E1.5: Dropdown filtert auf veröffentlicht + passende Klassenstufe', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');
    await seedMockData(page, {
      projekte: [
        // passt: veröffentlicht + 7. Klasse drin
        { id: 'p-ok-1', titel: 'OK Sieben-Neun', kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 7, max_klasse: 9, status: 'veroeffentlicht' },
        // passt nicht: Entwurf
        { id: 'p-no-1', titel: 'Entwurf-Projekt', kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 9, status: 'entwurf' },
        // passt nicht: Klassenstufen-Range 5-6 endet vor 7
        { id: 'p-no-2', titel: 'Nur 5-6', kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 6, status: 'veroeffentlicht' },
        // passt: veröffentlicht + 7 in Range
        { id: 'p-ok-2', titel: 'OK Fünf-Acht', kurzbeschreibung: '', max_plaetze: 12, min_teilnehmer: 6, min_klasse: 5, max_klasse: 8, status: 'veroeffentlicht' },
      ],
      schueler: [
        { code: '7A-PICK', vorname: 'Paul', nachname: 'Pick', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
      ],
    });

    const select = page.locator('[data-testid="klassenlehrer-zuteilung-select"][data-code="7A-PICK"]');
    const optionValues = await select.locator('option').evaluateAll(opts =>
      opts.map(o => (o as HTMLOptionElement).value)
    );

    // erwartet: '— keine —' (value="") + p-ok-1 + p-ok-2 — in dieser Reihenfolge alphabetisch nach Titel
    expect(optionValues).toEqual(['', 'p-ok-2', 'p-ok-1']);
    expect(optionValues).not.toContain('p-no-1');
    expect(optionValues).not.toContain('p-no-2');
  });
});
