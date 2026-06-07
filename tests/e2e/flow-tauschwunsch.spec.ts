import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * Flow: Tauschwunsch-Bearbeitung (Genehmigen + Ablehnen)
 *
 * Demo-Daten haben 3 Tauschwünsche (MOCK_TAUSCHWUENSCHE).
 * Tauschwünsche-Section ist phasen-abhängig → goToSection setzt MOCK_PHASE='nachbearbeitung'.
 *
 * Der Genehmigen-Modal-Flow:
 *   ✓ Genehmigen Button → Modal öffnet → "✓ Genehmigen und tauschen" Button →
 *   replaceArray entfernt Tauschwunsch aus mockTauschData → Toast.
 *
 * Der Ablehnen-Modal-Flow:
 *   ✗ Ablehnen Button → Modal mit Begründungs-Textarea → "✗ Ablehnen" Button →
 *   replaceArray entfernt Tauschwunsch → Toast.
 */
test.describe('Flow: Tauschwunsch bearbeiten', () => {
  test('Demo-Daten zeigen 3 offene Tauschwünsche', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'tauschwuensche');

    // Subtitle „N offene Wünsche"
    const subtitle = page.locator('.main-subtitle').first();
    await expect(subtitle).toContainText(/offene Wünsche/i);

    // Mindestens 3 Karten (eine pro Wunsch)
    const cards = page.locator('.card');
    expect(await cards.count(), 'Demo hat 3 Tauschwünsche').toBeGreaterThanOrEqual(3);
  });

  test('„✓ Genehmigen" → Modal öffnet → Bestätigen → Wunsch verschwindet', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'tauschwuensche');

    const cardsBefore = await page.locator('.card').count();
    if (cardsBefore === 0) {
      test.skip(true, 'Keine Tauschwünsche in Demo-Daten');
      return;
    }

    // Auf den ersten „✓ Genehmigen" Button (NICHT 1:1) klicken — wir nehmen
    // den btn-primary, nicht den btn-success (1:1-Tausch).
    const genehmigenBtn = page.locator('button.btn-primary')
      .filter({ hasText: /^✓ Genehmigen$/i }).first();
    await expect(genehmigenBtn).toBeVisible({ timeout: 3_000 });
    await genehmigenBtn.click();

    // Bestätigungs-Modal mit „✓ Genehmigen und tauschen" Button
    await expect(page.locator('.modal-content')).toBeVisible();
    const confirmBtn = page.locator('.modal-content')
      .getByRole('button', { name: /Genehmigen und tauschen/i });
    await expect(confirmBtn).toBeVisible();
    await confirmBtn.click();

    // Modal schließt
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 3_000 });

    // Erfolgs-Toast
    await expect(
      page.locator('.toast').filter({ hasText: /genehmigt/i }).first()
    ).toBeVisible({ timeout: 3_000 });

    // Eine Karte weniger
    await expect(async () => {
      const cardsAfter = await page.locator('.card').count();
      expect(cardsAfter, `Karten sollten von ${cardsBefore} auf ${cardsBefore - 1} fallen`)
        .toBeLessThan(cardsBefore);
    }).toPass({ timeout: 5_000 });
  });

  test('„✗ Ablehnen" → Begründungs-Modal → Wunsch verschwindet', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'tauschwuensche');

    const cardsBefore = await page.locator('.card').count();
    if (cardsBefore === 0) {
      test.skip(true, 'Keine Tauschwünsche zum Ablehnen');
      return;
    }

    // Ersten „✗ Ablehnen" Button klicken
    const ablehnenBtn = page.locator('button')
      .filter({ hasText: /^✗ Ablehnen$/i }).first();
    await expect(ablehnenBtn).toBeVisible();
    await ablehnenBtn.click();

    // Modal mit Textarea „Begründung"
    await expect(page.locator('.modal-content')).toBeVisible();
    const textarea = page.locator('#tausch-ablehnung-grund');
    await expect(textarea).toBeVisible();
    await textarea.fill('Zielprojekt voll, kein Tauschpartner.');

    // „✗ Ablehnen" Button im Modal
    const confirmBtn = page.locator('.modal-content')
      .getByRole('button', { name: /^✗ Ablehnen$/i });
    await confirmBtn.click();

    // Modal schließt
    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 3_000 });

    // Erfolgs-Toast
    await expect(
      page.locator('.toast').filter({ hasText: /abgelehnt/i }).first()
    ).toBeVisible({ timeout: 3_000 });

    // Eine Karte weniger
    await expect(async () => {
      const cardsAfter = await page.locator('.card').count();
      expect(cardsAfter).toBeLessThan(cardsBefore);
    }).toPass({ timeout: 5_000 });
  });

  test('„🔁 1:1-Tausch genehmigen" → Modal + mind. 1 Wunsch entfernt', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'tauschwuensche');

    // Demo-Daten haben Anna mit eins_zu_eins_moeglich=true und tauschpartner=Lukas,
    // ABER Lukas hat keinen eigenen Tauschwunsch in MOCK_TAUSCHWUENSCHE → der
    // Demo-Match-Algorithmus (findePartnerTauschId) findet keinen Partner-Wunsch
    // und entfernt nur Annas Wunsch. Saubere 2-Wunsch-Entfernung würde echte
    // reziproke Demo-Daten brauchen — daher hier nur „mindestens 1 entfernt".
    const oneToOneBtn = page.locator('button.btn-success')
      .filter({ hasText: /1:1-Tausch genehmigen/i }).first();

    if (await oneToOneBtn.count() === 0) {
      test.skip(true, 'Kein 1:1-Tausch-Match in Demo-Daten');
      return;
    }

    const cardsBefore = await page.locator('.card').count();
    await oneToOneBtn.click();

    // Modal-Confirm
    await expect(page.locator('.modal-content')).toBeVisible();
    await page.locator('.modal-content')
      .getByRole('button', { name: /Genehmigen und tauschen/i })
      .click();

    await expect(page.locator('.modal-content')).toBeHidden({ timeout: 3_000 });

    // Toast „Tauschwunsch genehmigt" beweist dass Aktion ausgeführt wurde
    await expect(
      page.locator('.toast').filter({ hasText: /genehmigt/i }).first()
    ).toBeVisible({ timeout: 3_000 });

    // Mindestens 1 Karte weniger (Annas Wunsch entfernt)
    await expect(async () => {
      const cardsAfter = await page.locator('.card').count();
      expect(cardsAfter, 'Mindestens 1 Wunsch sollte entfernt sein').toBeLessThan(cardsBefore);
    }).toPass({ timeout: 5_000 });
  });
});
