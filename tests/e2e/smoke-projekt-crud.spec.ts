import { test, expect, goToSection } from '../fixtures/app';

/**
 * Smoke-Test für Projekt-CRUD — analog zu Lehrer-CRUD.
 * Deckt die v19/v22-Kombi ab: Modal-Prefill + Tabellen-Refresh nach Edit.
 */

test.describe('Smoke: Projekt-CRUD', () => {
  test('Projekte-View ist erreichbar', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');
    await expect(page.getByRole('heading', { name: /projekte/i })).toBeVisible();
  });

  test('Neues Projekt anlegen → erscheint in Tabelle', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    // Counter-Stand vor Save merken (für Inkrement-Check)
    const subtitleBefore = await page.locator('.main-subtitle').first().textContent() || '';
    const countBefore = parseInt((subtitleBefore.match(/(\d+) Projekte angelegt/) || ['', '0'])[1], 10);

    const uniqueTitel = 'Test-Projekt-' + Date.now();
    await page.getByRole('button', { name: /Neues Projekt|Projekt anlegen|➕/i }).first().click();

    await expect(page.locator('.modal-content')).toBeVisible();

    // Titel-Feld (erstes text-Input im Modal) + kurz warten damit Preact propagiert
    await page.locator('.modal-content input[type="text"]').first().fill(uniqueTitel);
    await page.waitForTimeout(200);

    // Lehrer-Dropdown: erste gültige Option wählen
    const lehrerSelect = page.locator('.modal-content select').first();
    const options = await lehrerSelect.locator('option').all();
    for (const opt of options) {
      const val = await opt.getAttribute('value');
      if (val && val !== '') {
        await lehrerSelect.selectOption(val);
        break;
      }
    }
    await page.waitForTimeout(200);

    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 5_000 });

    // Direkter DOM-Check: neues Projekt muss in der Tabelle erscheinen
    // (möglich dank key=${p.id} Fix in admin-dashboard-v2.html — Bug 1 E0)
    await expect(page.locator('table tbody').getByText(uniqueTitel).first()).toBeVisible({ timeout: 5_000 });
  });

  test('Zwei Lehrer aktivieren 24 Plätze und die +/- Schalter funktionieren', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    const uniqueTitel = 'Zwei-Lehrer-Projekt-' + Date.now();
    await page.getByRole('button', { name: /Neues Projekt|Projekt anlegen|➕/i }).first().click();
    await expect(page.locator('.modal-content')).toBeVisible();

    await page.locator('.modal-content input[type="text"]').first().fill(uniqueTitel);

    const lehrer1 = page.locator('[data-testid="projekt-lehrer1-select"]');
    const lehrer2 = page.locator('[data-testid="projekt-lehrer2-select"]');
    const firstTeacher = await lehrer1.locator('option:not([value=""])').first().getAttribute('value');
    expect(firstTeacher).toBeTruthy();
    await lehrer1.selectOption(firstTeacher!);
    await expect(lehrer1).toHaveValue(firstTeacher!);

    await expect(lehrer2.locator(`option[value="${firstTeacher}"]`)).toHaveCount(0);
    const secondTeacherValues = await lehrer2.locator('option:not([value=""])').evaluateAll(options =>
      options.map(o => (o as HTMLOptionElement).value)
    );
    const secondTeacher = secondTeacherValues.find(v => v && v !== firstTeacher);
    expect(secondTeacher).toBeTruthy();
    await lehrer2.selectOption(secondTeacher!);
    await expect(lehrer2).toHaveValue(secondTeacher!);

    const maxControl = page.locator('[data-testid="projekt-max-plaetze-control"]');
    const maxInput = maxControl.locator('input[type="number"]');
    await expect(maxInput).toHaveValue('24');

    await maxControl.getByRole('button', { name: /Max\. Plätze verringern/i }).click();
    await expect(maxInput).toHaveValue('23');
    await maxControl.getByRole('button', { name: /Max\. Plätze erhöhen/i }).click();
    await expect(maxInput).toHaveValue('24');

    await maxInput.fill('18');
    await expect(maxInput).toHaveValue('18');
    await maxInput.fill('24');
    await expect(maxInput).toHaveValue('24');

    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 5_000 });
    await expect(page.locator('table tbody').getByText(uniqueTitel).first()).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('table tbody tr').filter({ hasText: uniqueTitel })).toContainText('/24');
  });

  test('Projekt bearbeiten → Modal prefilled, Änderung persistiert', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    // Ersten Projekt-Bearbeiten-Button klicken
    const firstEditBtn = page.locator('table tbody tr').first()
      .getByRole('button', { name: /Bearbeiten|✏️/i });

    // Falls keine Projekte existieren, erst eines anlegen
    if (await firstEditBtn.count() === 0) {
      test.skip(true, 'Keine Projekte in Demo-Daten vorhanden');
    }

    await firstEditBtn.click();
    await expect(page.locator('.modal-content')).toBeVisible();

    const titelInput = page.locator('.modal-content input[type="text"]').first();
    const original = await titelInput.inputValue();
    expect(original, 'Modal-Prefill darf nicht leer sein (v19-Bug!)').not.toBe('');

    const edited = original + ' [edit-' + Date.now() + ']';
    await titelInput.fill(edited);

    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 3_000 });

    await expect(page.getByText(edited).first()).toBeVisible({ timeout: 3_000 });
  });
});
