import { test, expect, goToSection } from '../fixtures/app';

/**
 * Smoke-Test: Projekt löschen
 *
 * Edit-Modal hat einen roten "Löschen"-Button. Klick → window.confirm() →
 * Bestätigen → mockProjekteData.splice() im Demo-Modus.
 *
 * Verifiziert wird:
 *  - Löschen-Button im Edit-Modal vorhanden
 *  - Nach Bestätigung: Toast „Projekt gelöscht" + Counter-Dekrement im Subtitle
 */
test.describe('Smoke: Projekt löschen', () => {
  test('Edit-Modal → Löschen → Projekt verschwindet aus Counter', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    // Counter-Stand vor Delete
    const subtitleBefore = await page.locator('.main-subtitle').first().textContent() || '';
    const countBefore = parseInt((subtitleBefore.match(/(\d+) Projekte angelegt/) || ['', '0'])[1], 10);

    if (countBefore === 0) {
      test.skip(true, 'Keine Projekte in Demo-Daten zum Löschen');
      return;
    }

    // Erstes Projekt zum Bearbeiten öffnen
    await page.locator('table tbody tr').first()
      .getByRole('button', { name: /Bearbeiten|✏️/i })
      .click();

    await expect(page.locator('.modal-content')).toBeVisible();

    // Löschen-Button im Modal sichtbar (nur bei bestehenden Projekten)
    const deleteBtn = page.locator('.modal-content').getByRole('button', { name: /^Löschen$/i });
    await expect(deleteBtn).toBeVisible();

    // window.confirm() automatisch akzeptieren
    page.once('dialog', d => d.accept());

    await deleteBtn.click();

    // Toast mit „Projekt gelöscht"
    await expect(
      page.locator('.toast').filter({ hasText: /Projekt gelöscht/i }).first()
    ).toBeVisible({ timeout: 3_000 });

    // Modal geschlossen
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 3_000 });

    // Counter ist um 1 gesunken
    await expect(async () => {
      const subtitleAfter = await page.locator('.main-subtitle').first().textContent() || '';
      const countAfter = parseInt((subtitleAfter.match(/(\d+) Projekte angelegt/) || ['', '0'])[1], 10);
      expect(countAfter, `Counter sollte gefallen sein (vorher ${countBefore})`).toBeLessThan(countBefore);
    }).toPass({ timeout: 5_000 });
  });

  test('Löschen mit Cancel im Confirm: Projekt bleibt erhalten', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    const subtitleBefore = await page.locator('.main-subtitle').first().textContent() || '';
    const countBefore = parseInt((subtitleBefore.match(/(\d+) Projekte angelegt/) || ['', '0'])[1], 10);

    if (countBefore === 0) {
      test.skip(true, 'Keine Projekte in Demo-Daten');
      return;
    }

    await page.locator('table tbody tr').first()
      .getByRole('button', { name: /Bearbeiten|✏️/i })
      .click();
    await expect(page.locator('.modal-content')).toBeVisible();

    // Diesmal: Confirm ablehnen
    page.once('dialog', d => d.dismiss());

    await page.locator('.modal-content').getByRole('button', { name: /^Löschen$/i }).click();
    await page.waitForTimeout(300);

    // Counter unverändert
    const subtitleAfter = await page.locator('.main-subtitle').first().textContent() || '';
    const countAfter = parseInt((subtitleAfter.match(/(\d+) Projekte angelegt/) || ['', '0'])[1], 10);
    expect(countAfter, 'Counter darf bei Cancel nicht ändern').toBe(countBefore);
  });
});
