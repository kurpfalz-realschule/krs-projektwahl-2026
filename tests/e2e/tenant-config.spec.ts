import { test, expect } from '@playwright/test';

test.describe.configure({ mode: 'serial' });

/**
 * E2E: Tenant-Config (Sprint v32-tenant-prep)
 *
 * Stellt sicher, dass:
 *   1. tenant.js geladen wird und window.TENANT verfügbar ist
 *   2. Default-Werte (KRS) für Backward-Compat funktionieren
 *   3. Branding-CSS-Variablen aus TENANT.branding gesetzt werden
 *   4. Ein Override via addInitScript vor Page-Load durchschlägt
 *      (wichtig für Pilot-Schulen-Workflow)
 */
test.describe('Tenant-Config: Schul-Branding', () => {
  test('window.TENANT existiert mit Default-Werten (KRS)', async ({ page }) => {
    await page.goto('/admin-dashboard-v2.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).TENANT === 'object');

    const t = await page.evaluate(() => (window as any).TENANT);
    expect(t.schule.name_kurz).toBeTruthy();
    expect(t.schule.name_lang).toBeTruthy();
    expect(t.branding.primaer).toMatch(/^#[0-9a-fA-F]{3,8}$/);
    expect(t.termine.projektwoche_jahr).toBeGreaterThan(2024);
    expect(t.kontakt.verantwortlich_email).toContain('@');
  });

  test('document.title spiegelt TENANT.schule.name_kurz wider', async ({ page }) => {
    await page.goto('/admin-dashboard-v2.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).TENANT === 'object');
    await page.waitForTimeout(100);

    const title = await page.title();
    const kurz = await page.evaluate(() => (window as any).TENANT.schule.name_kurz);
    expect(title).toContain(kurz);
  });

  test('CSS-Variablen aus TENANT.branding werden auf :root gesetzt', async ({ page }) => {
    await page.goto('/admin-dashboard-v2.html?forceMode=demo');
    await page.waitForFunction(() => typeof (window as any).TENANT === 'object');
    await page.waitForTimeout(100);

    const branding = await page.evaluate(() => {
      const cs = getComputedStyle(document.documentElement);
      return {
        primaer: cs.getPropertyValue('--krs-blau').trim(),
        akzent:  cs.getPropertyValue('--krs-orange').trim(),
        warm:    cs.getPropertyValue('--krs-gelb').trim()
      };
    });
    const expected = await page.evaluate(() => (window as any).TENANT.branding);
    expect(branding.primaer.toLowerCase()).toBe(expected.primaer.toLowerCase());
    expect(branding.akzent.toLowerCase()).toBe(expected.akzent.toLowerCase());
    expect(branding.warm.toLowerCase()).toBe(expected.warm.toLowerCase());
  });

  test('TENANT-Override via addInitScript ändert Branding + Schul-Name', async ({ page }) => {
    // Pilot-Schul-Szenario: andere Werte vor Page-Load injizieren
    await page.addInitScript(`
      window.TENANT = {
        schule: { name_lang: 'Test-Realschule', name_kurz: 'TRS', ort: 'Testhausen' },
        branding: { logo_url: '', primaer: '#aa0000', akzent: '#00aa00', warm: '#0000aa' },
        termine: { projektwoche_jahr: 2099, projekttage_von: '2099-06-01', projekttage_bis: '2099-06-03', schulfest: '2099-06-03' },
        kontakt: { verantwortlich_name: 'Test Person', verantwortlich_email: 'test@example.invalid' },
        links: { datenschutz: 'https://example.invalid/dsg', impressum: 'https://example.invalid/imp' },
        supabase: { url: '', publishableKey: '' },
        deploy: { frontend_url: '', schueler_url: '' }
      };
    `);
    await page.goto('/admin-dashboard-v2.html?forceMode=demo');
    await page.waitForTimeout(200);

    const title = await page.title();
    expect(title).toContain('TRS');
    expect(title).toContain('2099');

    const branding = await page.evaluate(() => {
      const cs = getComputedStyle(document.documentElement);
      return cs.getPropertyValue('--krs-blau').trim();
    });
    expect(branding.toLowerCase()).toBe('#aa0000');
  });

  test('schueler-frontend liest TENANT für Header-Termine + Footer-Mail', async ({ page }) => {
    await page.addInitScript(`
      window.TENANT = {
        schule: { name_lang: 'Pilot-Schule', name_kurz: 'PIL', ort: 'Pilothausen' },
        branding: { logo_url: '', primaer: '#4A6A83', akzent: '#E87722', warm: '#F5B335' },
        termine: { projektwoche_jahr: 2030, projekttage_von: '2030-09-15', projekttage_bis: '2030-09-17', schulfest: '2030-09-17' },
        kontakt: { verantwortlich_name: 'Pilot Verantwortlich', verantwortlich_email: 'pilot@example.invalid' },
        links: { datenschutz: 'https://pilot.example/datenschutz', impressum: 'https://pilot.example/impressum' },
        supabase: { url: '', publishableKey: '' },
        deploy: { frontend_url: '', schueler_url: '' }
      };
    `);
    await page.goto('/schueler-frontend-v3.html?forceMode=demo');
    await page.waitForTimeout(200);

    // Header zeigt Jahr 2030 + Termin-Bereich-Format
    await expect(page.locator('.event-title')).toContainText('2030');

    // Footer zeigt die Pilot-Email
    const footerEmail = page.locator('footer a').first();
    await expect(footerEmail).toHaveAttribute('href', 'mailto:pilot@example.invalid');
  });
});
