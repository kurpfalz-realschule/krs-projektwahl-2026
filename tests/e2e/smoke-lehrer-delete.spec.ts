import { test, expect, goToSection } from '../fixtures/app';

/**
 * Smoke-Test: Lehrer löschen
 *
 * - Edit-Modal hat einen "Löschen"-Button (nur bei bestehenden Lehrern, NICHT für super_admin).
 * - Super-Admin-Accounts sind vor versehentlichem Löschen geschützt.
 * - Demo: mockLehrerData.splice() — Tabellen-Refresh durch Re-Render.
 *
 * Verifiziert wird:
 *  - Löschen-Button erscheint bei normalen Lehrern im Edit-Modal
 *  - Löschen-Button fehlt bei super_admin (Schutz vor Selbst-Löschen)
 *  - Nach Bestätigung: Toast „Lehrer gelöscht", Lehrer-Anzahl sinkt
 */
test.describe('Smoke: Lehrer löschen', () => {
  test('Super-Admin hat keinen Löschen-Button (Self-Protection)', async ({ appPage: page }) => {
    await goToSection(page, 'lehrer');

    const adminRow = page.locator('table tbody tr').filter({ hasText: /super_admin|Lehrkraft 22/i }).first();
    if (await adminRow.count() === 0) {
      test.skip(true, 'Kein Super-Admin in Demo-Daten');
      return;
    }

    await adminRow.getByRole('button', { name: /Bearbeiten|✏️/i }).click();
    await expect(page.locator('.modal-content')).toBeVisible();

    // Super-Admin: Löschen-Button darf NICHT vorhanden sein
    const deleteBtn = page.locator('.modal-content').getByRole('button', { name: /^Löschen$/i });
    await expect(deleteBtn).toHaveCount(0);
  });

  test('Anderen Lehrer (≠ u1) löschen → Anzahl sinkt', async ({ appPage: page }) => {
    await goToSection(page, 'lehrer');

    const rowsBefore = await page.locator('table tbody tr').count();
    if (rowsBefore < 2) {
      test.skip(true, 'Zu wenige Lehrer in Demo-Daten zum Löschen');
      return;
    }

    const deletableRow = page.locator('table tbody tr').filter({ hasNotText: /super_admin/i }).first();
    await deletableRow
      .getByRole('button', { name: /Bearbeiten|✏️/i })
      .click();
    await expect(page.locator('.modal-content')).toBeVisible();

    const deleteBtn = page.locator('.modal-content').getByRole('button', { name: /^Löschen$/i });
    await expect(deleteBtn).toBeVisible();

    page.once('dialog', d => d.accept());
    await deleteBtn.click();

    // Toast „Lehrer gelöscht"
    await expect(
      page.locator('.toast').filter({ hasText: /Lehrer gelöscht/i }).first()
    ).toBeVisible({ timeout: 15_000 });
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 15_000 });

    // Tabelle hat eine Zeile weniger
    await expect(async () => {
      const rowsAfter = await page.locator('table tbody tr').count();
      expect(rowsAfter, 'Tabelle sollte nach Delete um 1 schrumpfen').toBeLessThan(rowsBefore);
    }).toPass({ timeout: 15_000 });
  });
});
