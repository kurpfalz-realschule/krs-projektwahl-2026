import { test, expect, loginAs } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * Rollen-Schutz — prüft ALLOWED_SECTIONS je Rolle.
 *
 * ALLOWED_SECTIONS (v27/E1):
 *   super_admin:   null  → alle Sections sichtbar
 *   projektleitung: dashboard, projekte, anmeldungen, export, phase, feedback
 *   projektlehrer:  mein-projekt (NUR)
 *   klassenlehrer:  meine-klasse (NUR)
 */
test.describe('Feature: Role Guard', () => {
  test('projektleitung sieht Projekt-Tab aber keinen Lehrer-Tab', async ({ page }) => {
    await loginAs(page, 'projektleitung');

    // projektleitung hat Zugriff auf 'projekte'
    const projektNav = page.locator(`[data-section="projekte"]`);
    await expect(projektNav).toBeVisible({ timeout: 5_000 });

    // projektleitung DARF KEINEN 'lehrer'-Tab sehen
    const lehrerNav = page.locator(`[data-section="lehrer"]`);
    await expect(lehrerNav).not.toBeVisible();
  });

  test('projektlehrer sieht NUR "Mein Projekt"-Tab', async ({ page }) => {
    await loginAs(page, 'projektlehrer');

    // Mein Projekt sichtbar
    const meinProjektNav = page.locator(`[data-section="mein-projekt"]`);
    await expect(meinProjektNav).toBeVisible({ timeout: 5_000 });

    // Dashboard NICHT sichtbar für projektlehrer
    const dashboardNav = page.locator(`[data-section="dashboard"]`);
    await expect(dashboardNav).not.toBeVisible();

    // Projekte-Tab NICHT sichtbar
    const projekteNav = page.locator(`[data-section="projekte"]`);
    await expect(projekteNav).not.toBeVisible();
  });

  test('klassenlehrer sieht NUR "Meine Klasse"-Tab', async ({ page }) => {
    await loginAs(page, 'klassenlehrer');

    // Meine Klasse sichtbar
    const meineKlasseNav = page.locator(`[data-section="meine-klasse"]`);
    await expect(meineKlasseNav).toBeVisible({ timeout: 5_000 });

    // Dashboard NICHT sichtbar für klassenlehrer
    const dashboardNav = page.locator(`[data-section="dashboard"]`);
    await expect(dashboardNav).not.toBeVisible();

    // Projekte NICHT sichtbar
    const projekteNav = page.locator(`[data-section="projekte"]`);
    await expect(projekteNav).not.toBeVisible();

    // Anmeldungen NICHT sichtbar (war früher erlaubt, ist seit E1 entfernt)
    const anmeldungenNav = page.locator(`[data-section="anmeldungen"]`);
    await expect(anmeldungenNav).not.toBeVisible();
  });
});
