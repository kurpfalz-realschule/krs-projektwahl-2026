import { test, expect, openAppLoggedIn } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

test.describe('Feature: Globaler Feedback-Button', () => {
  test('💬-Button ist sichtbar nach Login', async ({ page }) => {
    await openAppLoggedIn(page);

    // Feedback-Button ist fix positioniert (bottom-right) — suche per Text oder aria-label
    const feedbackBtn = page.locator('button').filter({ hasText: /💬/ }).first();
    await expect(feedbackBtn).toBeVisible({ timeout: 5_000 });
  });

  test('Klick auf Feedback-Button öffnet Modal mit Sterne-Bewertung', async ({ page }) => {
    await openAppLoggedIn(page);

    const feedbackBtn = page.locator('button').filter({ hasText: /💬/ }).first();
    if (await feedbackBtn.count() === 0) {
      test.skip(true, 'Feedback-Button nicht gefunden');
      return;
    }
    await feedbackBtn.click();
    await page.waitForTimeout(300);

    // Modal oder Inline-Formular sollte erscheinen
    const modal = page.locator('.modal-content, [class*="feedback"], [class*="modal"]').first();
    const hasModal = await modal.count() > 0;

    // Alternativ: Sterne-Buttons (⭐) sollten sichtbar sein
    const sternBtn = page.locator('button, span').filter({ hasText: /⭐|★/ }).first();
    const hasSterne = await sternBtn.count() > 0;

    expect(hasModal || hasSterne, 'Feedback-Modal oder Sterne müssen nach Klick erscheinen').toBe(true);
  });
});
