import { test, expect, goToSection } from '../fixtures/app';

/**
 * Feature: Modal-Validierung
 *
 * Projekt-Modal:
 *  - Speichern mit leerem Titel ODER ohne Lehrer → Toast-Error, Modal bleibt offen
 *  - Max. Plätze < Min. Teilnehmer → Toast-Error
 *
 * Lehrer-Modal:
 *  - Speichern ohne Name oder E-Mail → Toast-Error
 *
 * Verifiziert wird, dass die Frontend-Validierung greift, BEVOR ein
 * mockProjekteData.push() oder ähnliches passiert.
 */
test.describe('Feature: Modal-Validierung', () => {
  test('Projekt-Modal: leerer Titel → Fehler-Toast, Modal bleibt offen', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    await page.getByRole('button', { name: /Neues Projekt|➕/i }).first().click();
    await expect(page.locator('.modal-content')).toBeVisible();

    // KEIN Titel-Fill, KEIN Lehrer wählen — direkt Speichern
    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();

    // Error-Toast
    await expect(
      page.locator('.toast.error').filter({ hasText: /Titel und Lehrer sind erforderlich/i })
    ).toBeVisible({ timeout: 15_000 });

    // Modal ist NICHT geschlossen
    await expect(page.locator('.modal-content')).toBeVisible();
  });

  test('Projekt-Modal: Titel ohne Lehrer → Fehler-Toast', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    await page.getByRole('button', { name: /Neues Projekt|➕/i }).first().click();
    await expect(page.locator('.modal-content')).toBeVisible();

    await page.locator('.modal-content input[type="text"]').first().fill('Validation-Test');
    await page.waitForTimeout(150);

    // Lehrer NICHT wählen
    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();

    await expect(
      page.locator('.toast.error').filter({ hasText: /Titel und Lehrer/i })
    ).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.modal-content')).toBeVisible();
  });

  test('Projekt-Modal: Max. Plätze < Min. Teilnehmer → Fehler-Toast', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    await page.getByRole('button', { name: /Neues Projekt|➕/i }).first().click();
    await expect(page.locator('.modal-content')).toBeVisible();

    // Titel + Kurzbeschreibung + Lehrer befüllen
    // (Kurzbeschreibung ist seit dem NOT-NULL-Bugfix Pflichtfeld — ohne sie
    //  würde deren Fehler-Toast zuerst feuern statt der Plätze-Validierung)
    await page.locator('.modal-content input[type="text"]').first().fill('Plätze-Test');
    await page.locator('.modal-content textarea').first().fill('Kurzbeschreibung für Plätze-Test');
    await page.waitForTimeout(150);
    const lehrerSelect = page.locator('.modal-content select').first();
    const opts = await lehrerSelect.locator('option').all();
    for (const o of opts) {
      const v = await o.getAttribute('value');
      if (v && v !== '') { await lehrerSelect.selectOption(v); break; }
    }
    await page.waitForTimeout(150);

    // Min Teilnehmer auf 20, Max Plätze auf 5 → Fehler
    const minInput = page.locator('[data-testid="projekt-min-teilnehmer-control"] input[type="number"]');
    const maxInput = page.locator('[data-testid="projekt-max-plaetze-control"] input[type="number"]');
    await minInput.fill('20');
    await page.waitForTimeout(150);
    await maxInput.fill('5');
    await page.waitForTimeout(150);

    // Robuster Speichern-Klick (Lost-Click-Race): Preact kann den Button beim
    // Re-Render austauschen → Klick verloren, kein Toast. Bis zum Fehler-Toast
    // erneut klicken; das Modal bleibt absichtlich offen.
    await expect(async () => {
      await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();
      await expect(
        page.locator('.toast.error').filter({ hasText: /Max\. Plätze müssen >= Min\. Teilnehmer/i })
      ).toBeVisible({ timeout: 3_000 });
    }).toPass({ timeout: 20_000 });
    await expect(page.locator('.modal-content')).toBeVisible();
  });

  test('Projekt-Modal: fehlende Kurzbeschreibung → Fehler-Toast', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    await page.getByRole('button', { name: /Neues Projekt|➕/i }).first().click();
    await expect(page.locator('.modal-content')).toBeVisible();

    // Titel + Lehrer befüllen, Kurzbeschreibung absichtlich leer lassen
    await page.locator('.modal-content input[type="text"]').first().fill('Ohne-Kurzbeschreibung-Test');
    await page.waitForTimeout(150);
    const lehrerSelect = page.locator('.modal-content select').first();
    const opts = await lehrerSelect.locator('option').all();
    for (const o of opts) {
      const v = await o.getAttribute('value');
      if (v && v !== '') { await lehrerSelect.selectOption(v); break; }
    }
    await page.waitForTimeout(150);

    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();

    await expect(
      page.locator('.toast.error').filter({ hasText: /Kurzbeschreibung ist erforderlich/i })
    ).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.modal-content')).toBeVisible();
  });

  test('Lehrer-Modal: leere Pflichtfelder → Fehler-Toast', async ({ appPage: page }) => {
    await goToSection(page, 'lehrer');

    const newBtn = page.locator('button').filter({ hasText: /Neuer Lehrer|Lehrer anlegen|➕/i }).first();
    await newBtn.click();
    await expect(page.locator('.modal-content')).toBeVisible();

    // Direkt Speichern — keine Felder befüllt
    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();

    await expect(
      page.locator('.toast.error').filter({ hasText: /Name und E-?Mail sind erforderlich/i })
    ).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.modal-content')).toBeVisible();
  });
});
