import { test, expect } from '@playwright/test';

test.describe.configure({ mode: 'serial' });

/**
 * E2E-Flow: Schüler-Frontend Wahl-Anmeldung (Sprint v30 / E2)
 *
 * Volle Anmeldung als Schüler 8A-T4P1 (Anna Schmidt, Klasse 8a, hat_gewaehlt=false):
 * Code → Bestätigung → 3 Projekte wählen → Absenden → Fertig-Screen.
 */
test.describe('Schüler-Frontend: Anmelde-Flow', () => {
  test('Code via URL → Bestätigung → 3 Projekte wählen → Wahl absenden → fertig', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo&code=8A-T4P1');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    // Bestätigung erscheint mit Schüler-Daten
    await expect(page.locator('h2').filter({ hasText: /Bist du das/i })).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('.bestaetigung-box')).toContainText('Anna Schmidt');
    await expect(page.locator('.bestaetigung-box')).toContainText('8a');

    // Bestätigen → Wahl-Screen
    await page.locator('button').filter({ hasText: /Ja, das bin ich/ }).click();
    await expect(page.locator('h2').filter({ hasText: /Deine Wunsch-Projekte/i })).toBeVisible();

    // 3 Projekte für Klassenstufe 8 wählen — alle in MOCK_PROJEKTE haben max_klasse>=8
    // außer p5 (5-8) ist OK, p4 (6-9) OK. Wir nehmen p2, p6, p7 (alle 5-9).
    const cards = page.locator('.projekt-card');
    await cards.filter({ hasText: 'Theater-Werkstatt' }).click();
    await cards.filter({ hasText: 'Kreatives Kochen' }).click();
    await cards.filter({ hasText: 'Sport & Spiel' }).click();

    // Status-Bar zeigt 3 gewählte Projekte
    await expect(page.locator('.status-wahl').nth(0)).toContainText('Theater-Werkstatt');
    await expect(page.locator('.status-wahl').nth(1)).toContainText('Kreatives Kochen');
    await expect(page.locator('.status-wahl').nth(2)).toContainText('Sport & Spiel');

    // Absenden
    await page.locator('button').filter({ hasText: /Absenden/ }).click();

    // Fertig-Screen — h2 "Super, <Vorname>!" + Erfolgs-Strong-Element
    await expect(page.locator('h2').filter({ hasText: /Super/i })).toBeVisible({ timeout: 5_000 });
    await expect(page.locator('strong').filter({ hasText: /Erfolgreich angemeldet/i })).toBeVisible();

    // Mock-State: 8A-T4P1 ist jetzt hat_gewaehlt=true
    const stored = await page.evaluate(() => {
      const s = (window as any).MOCK_SCHUELER['8A-T4P1'];
      return { hat_gewaehlt: !!(s.status && s.status.hat_gewaehlt), wahlen: s.status?.wahlen };
    });
    expect(stored.hat_gewaehlt).toBe(true);
    expect(stored.wahlen).toBeTruthy();
    expect(new Set([stored.wahlen.erstwahl_id, stored.wahlen.zweitwahl_id, stored.wahlen.drittwahl_id]).size).toBe(3);
  });

  test('Klassenstufen-Filter: 5er sieht nur passende Projekte (kein 7-9-Projekt)', async ({ page }) => {
    // 5A-B3X9 (Lisa, klassenstufe 5) ist in den Default-Mock-Daten hat_gewaehlt=true.
    // Wir laden ohne ?code, patchen den Mock, und gehen dann manuell durch den Flow.
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');
    await page.evaluate(() => {
      (window as any).MOCK_SCHUELER['5A-B3X9'].status = { hat_gewaehlt: false };
    });

    // Start-Screen → Code-Eingabe
    await page.locator('button').filter({ hasText: /anmelden|→/ }).first().click();
    await page.locator('#code-input').fill('5A-B3X9');
    await page.locator('button').filter({ hasText: /Weiter/ }).click();

    // Bestätigen
    await expect(page.locator('h2').filter({ hasText: /Bist du das/i })).toBeVisible({ timeout: 5_000 });
    await page.locator('button').filter({ hasText: /Ja, das bin ich/ }).click();

    // p1 (Fotografie, 7-9) und p3 (Weinberg, 7-9) dürfen NICHT erscheinen für klassenstufe 5
    await expect(page.locator('h2').filter({ hasText: /Wunsch-Projekte/i })).toBeVisible();
    const titles = await page.locator('.projekt-titel').allTextContents();
    expect(titles).not.toContain('Fotografie & Bildbearbeitung');
    expect(titles).not.toContain('Weinberg-AG intensiv');
    // Aber Theater-Werkstatt (5-9) MUSS drin sein
    expect(titles).toContain('Theater-Werkstatt');
  });
});
