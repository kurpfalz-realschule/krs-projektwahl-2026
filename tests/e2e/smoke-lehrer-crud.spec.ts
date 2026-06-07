import { test, expect, goToSection } from '../fixtures/app';

/**
 * Regression-Test für den v22-Bug:
 * Im Produktiv-Modus wurde nach Lehrer-Edit die Tabelle nicht refresht,
 * weil subscribeUsers fehlte und loadAll() nicht getriggert wurde.
 *
 * Im Demo-Modus mutiert die App die Mock-Arrays direkt — hier testen wir
 * primär die UI-Pfade (Modal öffnet prefilled, Änderung erscheint in Tabelle).
 */

test.describe('Smoke: Lehrer-CRUD', () => {
  test('Lehrer-Tabelle ist sichtbar und enthält Demo-Daten', async ({ appPage: page }) => {
    await goToSection(page, 'lehrer');
    await expect(page.getByRole('heading', { name: /lehrer/i })).toBeVisible();
    // Demo-Daten haben mindestens einen Lehrer-Eintrag
    await expect(page.locator('table tbody tr').first()).toBeVisible();
  });

  test('Neuen Lehrer anlegen → erscheint in Tabelle', async ({ appPage: page }) => {
    await goToSection(page, 'lehrer');

    const uniqueName = 'Testlehrer-' + Date.now();
    await page.getByRole('button', { name: /Neuer Lehrer|Lehrer anlegen|➕/i }).first().click();

    // Modal sichtbar
    await expect(page.locator('.modal-content')).toBeVisible();

    // Name-Feld füllen (erstes text-Input im Modal)
    const nameInput = page.locator('.modal-content input[type="text"]').first();
    await nameInput.fill(uniqueName);
    await page.waitForTimeout(200);  // Preact-Re-render abwarten (stale closure fix)

    // E-Mail, falls Pflichtfeld
    const emailInput = page.locator('.modal-content input[type="email"]').first();
    if (await emailInput.count()) await emailInput.fill(`test-${Date.now()}@krs.test`);
    await page.waitForTimeout(200);  // Preact-Re-render abwarten (stale closure fix)

    // Speichern
    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();

    // Modal schließt
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 3_000 });

    // Neuer Eintrag in Tabelle sichtbar
    await expect(page.getByRole('cell', { name: uniqueName })).toBeVisible();
  });

  test('Lehrer bearbeiten → Änderung erscheint in Tabelle (v21-Regression!)', async ({ appPage: page }) => {
    await goToSection(page, 'lehrer');

    // Ersten Lehrer bearbeiten
    await page.locator('table tbody tr').first()
      .getByRole('button', { name: /Bearbeiten|✏️/i })
      .click();

    await expect(page.locator('.modal-content')).toBeVisible();

    // v21-Regression: Modal muss prefilled sein (useEffect-Pattern)
    const nameInput = page.locator('.modal-content input[type="text"]').first();
    const originalValue = await nameInput.inputValue();
    expect(originalValue, 'Name-Feld darf nicht leer sein (v21-Bug!)').not.toBe('');

    const newName = originalValue + ' [editiert-' + Date.now() + ']';
    await nameInput.fill(newName);

    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 3_000 });

    // v22-Regression: Änderung muss OHNE Reload in der Tabelle erscheinen
    await expect(page.getByRole('cell', { name: newName })).toBeVisible({ timeout: 3_000 });
  });
});
