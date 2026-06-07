import { test, expect, loginAs, seedMockData } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * E2E-Flow: KlassenlehrerView Erinnerungs-Trigger (Sprint v29 / E1.6)
 *
 * Klassenlehrer kann eine druckbare Liste der offenen Schüler erzeugen
 * (Schüler ohne hat_gewaehlt + ohne zuteilung). Schüler haben keine eigenen
 * E-Mail-Adressen → keine Mailto-Lösung; statt dessen window.open() mit
 * Druckansicht.
 */
test.describe('Flow: KlassenlehrerView Erinnerungs-Trigger (E1.6)', () => {
  test('Button erscheint nicht, wenn alle Schüler angemeldet sind', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');
    await seedMockData(page, {
      schueler: [
        { code: '7A-OK1', vorname: 'Anna', nachname: 'Test', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: null },
        { code: '7A-OK2', vorname: 'Ben',  nachname: 'Test', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: null },
      ],
    });

    await expect(page.locator('[data-testid="klassenlehrer-erinnerung-btn"]')).toHaveCount(0);
  });

  test('Button zeigt Counter und ist sichtbar wenn ≥1 offen', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');
    await seedMockData(page, {
      schueler: [
        { code: '7A-OFF1', vorname: 'Otto',   nachname: 'Offen', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
        { code: '7A-OFF2', vorname: 'Olga',   nachname: 'Offen', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
        { code: '7A-FERTIG', vorname: 'Frida', nachname: 'Fertig', klasse: '7a', klassenstufe: 7, hat_gewaehlt: true, zuteilung: null },
      ],
    });

    const btn = page.locator('[data-testid="klassenlehrer-erinnerung-btn"]');
    await expect(btn).toBeVisible();
    await expect(btn).toContainText(/2 offene/);
  });

  test('Klick öffnet Druckansicht (window.open) mit Klassenname und Schüler-Codes', async ({ page, context }) => {
    await loginAs(page, 'klassenlehrer');
    await seedMockData(page, {
      schueler: [
        { code: '7A-DRU1', vorname: 'Dora',  nachname: 'Druck', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
        { code: '7A-DRU2', vorname: 'Diego', nachname: 'Druck', klasse: '7a', klassenstufe: 7, hat_gewaehlt: false, zuteilung: null },
      ],
    });

    // Click triggert window.open → neuer Page-Event auf dem Context
    const popupPromise = context.waitForEvent('page', { timeout: 5_000 });
    await page.locator('[data-testid="klassenlehrer-erinnerung-btn"]').click();
    const popup = await popupPromise;
    await popup.waitForLoadState('domcontentloaded');

    // Druckansicht enthält Klassenname (uppercase) und beide Schüler-Codes
    const body = await popup.locator('body').textContent();
    expect(body).toContain('7A');
    expect(body).toContain('7A-DRU1');
    expect(body).toContain('7A-DRU2');
    expect(body).toContain('Erinnerung Projektwoche');
    await popup.close();
  });
});
