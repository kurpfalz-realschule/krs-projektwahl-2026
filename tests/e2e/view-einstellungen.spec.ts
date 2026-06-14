import { test, expect, openAppLoggedIn, goToSection } from '../fixtures/app';

test.describe.configure({ mode: 'serial' });

/**
 * v37: Einstellungen-View ist an system_settings angebunden (vorher Attrappe).
 * Demo-Modus: Termine kommen aus window.MOCK_SETTINGS (Default-Seed in der App,
 * via addInitScript überschreibbar — die App respektiert vorhandene Werte).
 */
test.describe('View: Einstellungen (v37 — system_settings)', () => {
  test('Termine laden aus MOCK_SETTINGS in die Eingabefelder', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'einstellungen');

    await expect(page.locator('h1').filter({ hasText: /Einstellungen/i })).toBeVisible({ timeout: 15_000 });

    await expect(page.getByTestId('termin-anmelde-deadline')).toHaveValue('2026-07-10T23:59');
    await expect(page.getByTestId('termin-tausch-deadline')).toHaveValue('2026-07-17T23:59');
    await expect(page.getByTestId('termin-projekttage-beginn')).toHaveValue('2026-07-21');
    await expect(page.getByTestId('termin-projekttage-ende')).toHaveValue('2026-07-23');
  });

  test('Ändern + Speichern schreibt in MOCK_SETTINGS und zeigt Erfolgs-Toast', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'einstellungen');

    await page.getByTestId('termin-anmelde-deadline').fill('2026-07-08T18:00');
    await page.getByTestId('termine-speichern').click();

    await expect(page.locator('.toast.success')).toBeVisible({ timeout: 15_000 });

    const saved = await page.evaluate(() => (window as any).MOCK_SETTINGS.anmelde_deadline);
    expect(saved, 'setSystemSetting soll im Demo-Modus MOCK_SETTINGS schreiben').toBe('2026-07-08T18:00');
  });

  test('Validierung: Anmelde-Deadline nach Tausch-Deadline → Fehler-Toast, kein Speichern', async ({ page }) => {
    await openAppLoggedIn(page);
    await goToSection(page, 'einstellungen');

    // 20.07. liegt NACH der Tausch-Deadline (17.07.) → muss abgelehnt werden
    await page.getByTestId('termin-anmelde-deadline').fill('2026-07-20T12:00');
    await page.getByTestId('termine-speichern').click();

    await expect(page.locator('.toast.error')).toBeVisible({ timeout: 15_000 });

    const saved = await page.evaluate(() => (window as any).MOCK_SETTINGS.anmelde_deadline);
    expect(saved, 'Ungültiger Wert darf nicht gespeichert werden').not.toBe('2026-07-20T12:00');
  });

  test('Deadline-Banner erscheint, wenn Anmelde-Deadline überschritten (Phase: anmeldung)', async ({ page }) => {
    // Termine VOR App-Start auf Vergangenheit seeden — der MOCK_SETTINGS-Init
    // in der App respektiert vorhandene Werte (window.MOCK_SETTINGS || {…}).
    await page.addInitScript(() => {
      (window as any).MOCK_SETTINGS = {
        anmelde_deadline: '2020-01-01T00:00',
        tausch_deadline: '2099-12-31T23:59',
        projekttage_beginn: '2099-07-21',
        projekttage_ende: '2099-07-23'
      };
    });
    await openAppLoggedIn(page);

    await expect(page.getByTestId('deadline-banner')).toBeVisible({ timeout: 15_000 });
    await expect(page.getByTestId('deadline-banner')).toContainText('Anmelde-Deadline');
  });

  test('Kein Banner, wenn alle Deadlines in der Zukunft liegen', async ({ page }) => {
    // Explizit Zukunfts-Termine seeden — NICHT auf die App-Defaults verlassen,
    // sonst kippt der Test, sobald das reale Datum die Default-Deadline überholt.
    await page.addInitScript(() => {
      (window as any).MOCK_SETTINGS = {
        anmelde_deadline: '2099-07-10T23:59',
        tausch_deadline: '2099-07-17T23:59',
        projekttage_beginn: '2099-07-21',
        projekttage_ende: '2099-07-23'
      };
    });
    await openAppLoggedIn(page);
    await page.waitForTimeout(500);

    await expect(page.getByTestId('deadline-banner')).toHaveCount(0);
  });
});

/**
 * v37: Schüler-Frontend zeigt die Termine aus system_settings an
 * (Demo: window.MOCK_SETTINGS) — Deadline-Hinweis im Header + Projekttage-Zeitraum.
 */
test.describe('Schüler-Frontend: Termine (v37)', () => {
  test('Deadline-Hinweis im Header während Phase anmeldung', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    const hint = page.getByTestId('deadline-hinweis');
    await expect(hint).toBeVisible({ timeout: 15_000 });
    await expect(hint).toContainText('Anmeldung bis');
    await expect(hint).toContainText('10.07.2026');
  });

  test('Projekttage-Zeitraum aus MOCK_SETTINGS im Header', async ({ page }) => {
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    await expect(page.locator('.event-accent')).toContainText('21.07.2026', { timeout: 15_000 });
  });

  test('Tausch-Hinweis während Phase nachbearbeitung', async ({ page }) => {
    await page.addInitScript(() => { (window as any).MOCK_PHASE = 'nachbearbeitung'; });
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).KRS_VERSION === 'string');

    const hint = page.getByTestId('deadline-hinweis');
    await expect(hint).toBeVisible({ timeout: 15_000 });
    await expect(hint).toContainText('Tauschwünsche bis');
  });
});
