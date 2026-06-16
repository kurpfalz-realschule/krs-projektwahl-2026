import { test, expect, openAppLoggedIn, goToSection, loginAs } from '../fixtures/app';

/**
 * v41-Features (Demo-Modus, hermetisch):
 *  1. Admin kann einzelnen Schüler anlegen (Name + Klasse)
 *  2. Admin kann Projekt sperren/entsperren (gesperrt-Badge)
 *  3. Projektlehrer sieht read-only "Alle Projekte"-Übersicht
 */

test.describe.configure({ mode: 'serial' });

test.describe('v41: Schüler anlegen', () => {
  test('Admin legt einen Schüler über das Formular an', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'schueler');

    const before = await page.locator('table tbody tr').count();

    await page.locator('[data-testid="schueler-anlegen-btn"]').click();
    await page.locator('[data-testid="create-vorname"]').fill('Testkind');
    await page.locator('[data-testid="create-nachname"]').fill('Nachzügler');
    await page.locator('[data-testid="create-klasse"]').fill('7b');
    await page.locator('[data-testid="create-submit"]').click();

    // Erfolgs-Toast erscheint
    await expect(page.locator('.toast', { hasText: 'angelegt' }).first())
      .toBeVisible({ timeout: 10_000 });

    // Liste enthält den neuen Namen (Suche einsetzen, da viele Demo-Zeilen)
    await page.locator('input[placeholder*="Name oder Code"], input[placeholder*="Code"]').first().fill('Nachzügler');
    await page.waitForTimeout(250);
    await expect(page.locator('table tbody tr', { hasText: 'Nachzügler' }).first()).toBeVisible();
  });

  test('Ungültige Klasse wird abgelehnt', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'schueler');
    await page.locator('[data-testid="schueler-anlegen-btn"]').click();
    await page.locator('[data-testid="create-vorname"]').fill('Falsche');
    await page.locator('[data-testid="create-nachname"]').fill('Klasse');
    await page.locator('[data-testid="create-klasse"]').fill('13z');
    await page.locator('[data-testid="create-submit"]').click();
    await expect(page.locator('.toast', { hasText: 'Klasse ungültig' }).first())
      .toBeVisible({ timeout: 10_000 });
  });
});

test.describe('v41: Projekt sperren', () => {
  test('Sperr-Toggle setzt gesperrt-Badge', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'projekte');

    const firstRow = page.locator('table tbody tr').first();
    await expect(firstRow).toBeVisible({ timeout: 15_000 });

    // confirm()-Dialog automatisch bestätigen
    page.on('dialog', d => d.accept());

    await firstRow.locator('[data-testid="sperr-toggle"]').click();
    await expect(page.locator('.toast', { hasText: 'gesperrt' }).first())
      .toBeVisible({ timeout: 10_000 });
    await expect(firstRow.locator('text=🔒 gesperrt').first()).toBeVisible();
  });
});

test.describe('v41: Alle Projekte (Lehrer-Leseansicht)', () => {
  test('Projektlehrer sieht Übersicht aller Projekte', async ({ page }) => {
    await loginAs(page, 'projektlehrer');

    const nav = page.locator('[data-section="alle-projekte"]').first();
    await expect(nav).toBeVisible({ timeout: 10_000 });
    await nav.click();
    await page.waitForTimeout(200);

    await expect(page.locator('.main-title', { hasText: 'Alle Projekte' })).toBeVisible();
    // Tabelle mit mehr als nur dem eigenen Projekt
    const rows = await page.locator('table tbody tr').count();
    expect(rows, 'Lehrer sollte mehrere Projekte sehen').toBeGreaterThan(1);
  });
});
