import { defineConfig, devices } from '@playwright/test';

/**
 * KRS Projektwahl 2026 — Playwright E2E-Konfiguration
 *
 * Was das tut:
 * - Startet lokal einen http-server auf Port 4173, der den Projekt-Ordner serviert
 * - Lädt admin-dashboard-v2.html?forceMode=demo (v22.1 Test-Override) → keine
 *   Supabase-Mutationen, in-memory Mock-Arrays
 * - Jeder Test ist hermetisch: Demo-Daten werden bei jedem Page-Load frisch geladen
 *
 * Lokaler Lauf:
 *   npm install
 *   npm run test:install   # einmalig: Chromium mit Deps
 *   npm run test:e2e
 *
 * Headed-Modus zum Debuggen:
 *   npm run test:e2e:headed
 *
 * CI:
 *   Läuft über .github/workflows/playwright.yml bei jedem Push auf main.
 */
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false,          // Mock-Arrays sind global — parallele Tests kollidieren
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',

  use: {
    baseURL: 'http://127.0.0.1:4173',
    actionTimeout: 5_000,
    navigationTimeout: 10_000,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium-demo',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: {
    command: 'npm run serve',
    url: 'http://127.0.0.1:4173/admin-dashboard-v2.html',
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
});
