import { test, expect } from '@playwright/test';

test.describe.configure({ mode: 'serial' });

/**
 * E2E-Flow: Schüler-Frontend Tauschwunsch (Sprint v30 / E2)
 *
 * Lisa (5A-B3X9) hat in den Demo-Daten die Zuteilung p6 (Kreatives Kochen, wahl_nr=2).
 * In Phase 'nachbearbeitung' sollte ihr MeinErgebnis-Screen einen Tausch-Button zeigen
 * (wahl_nr !== 1). Sie kann einen Tauschwunsch zu einem anderen Projekt stellen.
 */
test.describe('Schüler-Frontend: Tauschwunsch-Flow', () => {
  test('Lisa (wahl_nr=2) → Tauschwunsch → Begründung → senden → Bestätigung', async ({ page }) => {
    // Phase 'nachbearbeitung' VOR der App-Init setzen (analog Admin-Test-Pattern)
    await page.addInitScript(`window.MOCK_PHASE = 'nachbearbeitung';`);
    await page.goto('/schueler-frontend-v3.html?forceMode=demo&code=5A-B3X9');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    // MeinErgebnis-Screen erscheint (wahl_nr=2 → Tauschwunsch-Button vorhanden)
    await expect(page.locator('.ergebnis-projekt-titel')).toContainText('Kreatives Kochen', { timeout: 5_000 });
    await expect(page.locator('button').filter({ hasText: /Tauschwunsch stellen/i })).toBeVisible();

    // Tauschwunsch öffnen
    await page.locator('button').filter({ hasText: /Tauschwunsch stellen/i }).click();
    await expect(page.locator('h2').filter({ hasText: /Tauschwunsch/i })).toBeVisible();

    // Dropdown enthält nur Projekte für Klassenstufe 5 — und nicht das aktuelle p6.
    // Wir wählen p2 (Theater-Werkstatt, 5-9).
    const select = page.locator('select');
    await select.selectOption({ value: 'p2' });

    // Begründung mind. 10 Zeichen
    await page.locator('textarea').fill('Ich interessiere mich viel mehr für Theater als fürs Kochen.');

    // Senden
    await page.locator('button').filter({ hasText: /Wunsch senden/i }).click();

    // Bestätigungs-Screen
    await expect(page.locator('h2').filter({ hasText: /Tauschwunsch gesendet/i })).toBeVisible({ timeout: 5_000 });
  });

  test('Tauschwunsch ohne Begründung → Fehler-Toast bleibt im Formular', async ({ page }) => {
    await page.addInitScript(`window.MOCK_PHASE = 'nachbearbeitung';`);
    await page.goto('/schueler-frontend-v3.html?forceMode=demo&code=9C-K7M2');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    // Tom (9C-K7M2) ist in p1 (Fotografie, wahl_nr=3) → Tausch-Button verfügbar
    await page.locator('button').filter({ hasText: /Tauschwunsch stellen/i }).click();
    await expect(page.locator('h2').filter({ hasText: /Tauschwunsch/i })).toBeVisible();

    // Ziel auswählen, aber Begründung leer lassen
    await page.locator('select').selectOption({ index: 1 });
    await page.locator('button').filter({ hasText: /Wunsch senden/i }).click();

    // Fehler-Alert mit Begründungs-Hinweis
    await expect(page.locator('.alert-error')).toContainText(/Begründung|10 Zeichen/i);

    // Wir sind weiterhin im Tauschwunsch-Formular (keine Bestätigungsseite)
    await expect(page.locator('h2').filter({ hasText: /Tauschwunsch gesendet/i })).toHaveCount(0);
  });
});
