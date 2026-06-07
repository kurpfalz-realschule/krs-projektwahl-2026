import { test, expect, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * Flow: Bulk-Veröffentlichen
 *
 * Der Button „📢 Alle Entwürfe veröffentlichen (N)" erscheint nur wenn
 * entwurfsCount > 0 (also mindestens ein Projekt mit status='entwurf').
 * Demo-Daten sind alle veroeffentlicht — wir legen also erst ein Entwurfs-
 * Projekt an, dann prüfen wir den Bulk-Button.
 *
 * Im Demo: handleBulkVeroeffentlichen() iteriert mockProjekteData und setzt
 * jedes 'entwurf'-Projekt auf 'veroeffentlicht' (line ~7497 admin-dashboard).
 */
test.describe('Flow: Bulk-Veröffentlichen', () => {
  test('Initial kein Bulk-Button (alle Demo-Projekte veröffentlicht)', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    const bulkBtn = page.locator('button').filter({ hasText: /Alle Entwürfe veröffentlichen/i });
    await expect(bulkBtn).toHaveCount(0);
  });

  test('Nach Anlegen eines Entwurfs: Bulk-Button erscheint', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    // Subtitle-Counter merken
    const subtitleBefore = await page.locator('.main-subtitle').first().textContent() || '';
    const countBefore = parseInt((subtitleBefore.match(/(\d+) Projekte angelegt/) || ['', '0'])[1], 10);

    // Neues Projekt mit Default-Status='entwurf' anlegen
    const uniqueTitel = 'Bulk-Test-' + Date.now();
    await page.getByRole('button', { name: /Neues Projekt|➕/i }).first().click();
    await expect(page.locator('.modal-content')).toBeVisible();

    await page.locator('.modal-content input[type="text"]').first().fill(uniqueTitel);
    await page.waitForTimeout(200);

    // Lehrer wählen
    const lehrerSelect = page.locator('.modal-content select').first();
    const opts = await lehrerSelect.locator('option').all();
    for (const o of opts) {
      const v = await o.getAttribute('value');
      if (v && v !== '') { await lehrerSelect.selectOption(v); break; }
    }
    await page.waitForTimeout(200);

    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 5_000 });

    // Counter ist gestiegen (proxy für „Save war erfolgreich")
    await expect(async () => {
      const subtitleAfter = await page.locator('.main-subtitle').first().textContent() || '';
      const countAfter = parseInt((subtitleAfter.match(/(\d+) Projekte angelegt/) || ['', '0'])[1], 10);
      expect(countAfter).toBeGreaterThan(countBefore);
    }).toPass({ timeout: 5_000 });

    // Subtitle zeigt jetzt „N Projekte angelegt · M Entwürfe" (M ≥ 1)
    await expect(page.locator('.main-subtitle').first()).toContainText(/\d+ Entwürfe?/);

    // BEKANNTER APP-BUG (siehe UEBERGABE-v26 #Bug 1): Conditional-Rendering
    // `entwurfsCount > 0 ? <button> : ''` aktualisiert sich nach mockProjekteData.push()
    // nicht zuverlässig. Re-Mount via Tab-Switch erzwingt Neu-Rendering.
    await goToSection(page, 'dashboard');
    await page.waitForTimeout(150);
    await goToSection(page, 'projekte');
    await page.waitForTimeout(300);

    // Bulk-Button jetzt sichtbar
    await expect(
      page.locator('button').filter({ hasText: /Alle Entwürfe veröffentlichen/i }).first()
    ).toBeVisible({ timeout: 5_000 });
  });

  test('Bulk-Button-Klick → Toast + Entwürfe verschwinden aus Subtitle', async ({ appPage: page }) => {
    await goToSection(page, 'projekte');

    // Erst einen Entwurf erzeugen
    const uniqueTitel = 'Bulk-Click-' + Date.now();
    await page.getByRole('button', { name: /Neues Projekt|➕/i }).first().click();
    await expect(page.locator('.modal-content')).toBeVisible();
    await page.locator('.modal-content input[type="text"]').first().fill(uniqueTitel);
    await page.waitForTimeout(200);
    const lehrerSelect = page.locator('.modal-content select').first();
    const opts = await lehrerSelect.locator('option').all();
    for (const o of opts) {
      const v = await o.getAttribute('value');
      if (v && v !== '') { await lehrerSelect.selectOption(v); break; }
    }
    await page.waitForTimeout(200);
    await page.locator('.modal-content').getByRole('button', { name: /speichern/i }).click();
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 5_000 });

    // Re-Mount erzwingen damit Bulk-Button rendert (siehe Bug 1)
    await goToSection(page, 'dashboard');
    await page.waitForTimeout(150);
    await goToSection(page, 'projekte');
    await page.waitForTimeout(300);

    // Bulk-Button da → klicken (window.confirm akzeptieren)
    page.once('dialog', d => d.accept());
    await page.locator('button').filter({ hasText: /Alle Entwürfe veröffentlichen/i }).first().click();

    // Erfolgs-Toast
    await expect(
      page.locator('.toast').filter({ hasText: /veröffentlicht/i }).first()
    ).toBeVisible({ timeout: 3_000 });

    // Bulk-Button sollte jetzt verschwunden sein (entwurfsCount === 0)
    // Hinweis: Im Demo mutiert handleBulkVeroeffentlichen p.status direkt — durch
    // Subtitle-Re-Render wird das sichtbar. Etwas Geduld geben.
    await expect(async () => {
      const subtitle = await page.locator('.main-subtitle').first().textContent() || '';
      // „· N Entwürfe" sollte verschwunden sein (oder N = 0)
      expect(subtitle, 'Entwürfe-Suffix sollte fehlen').not.toMatch(/· \d+ Entwürfe?/);
    }).toPass({ timeout: 5_000 });
  });
});
