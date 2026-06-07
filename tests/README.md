# KRS Projektwahl 2026 — E2E-Tests

Automatisierte End-to-End-Tests mit **Playwright**. Ziel: Regressionen fallen in CI auf, bevor sie live gehen.

**Stand v25 (Sprint D-2):** 20 Spec-Files · ~60 Tests · 4 Rollen getestet

---

## Schnellstart (lokal)

```bash
cd "projekwoche app neu"
npm install
npm run test:install   # einmalig: Chromium mit Abhängigkeiten
npm run test:e2e       # alle Tests
```

Weitere Befehle:

| Befehl | Zweck |
|---|---|
| `npm run test:e2e:headed` | Tests mit sichtbarem Browser (Debug) |
| `npm run test:e2e:ui`     | Playwright UI-Mode (interaktiv) |
| `npm run test:list`       | Alle Tests auflisten (kein Browser nötig) |
| `npm run test:typecheck`  | TypeScript-Clean-Check der Test-Dateien |
| `npm run serve`           | Nur den http-server starten (Port 4173) |

Nach einem Fehlschlag erzeugt Playwright einen HTML-Report:
```bash
npx playwright show-report
```

---

## Architektur

### Test-Modus: `?forceMode=demo`

Die App erkennt den URL-Parameter `?forceMode=demo` und zwingt die
DataService-Schicht in den Demo-Modus — auch wenn Supabase-Credentials
im Bundle sind. Dadurch:

- Tests greifen **nie** auf die Produktiv-Datenbank zu
- Jeder Page-Load bekommt frische In-Memory-Mock-Arrays (hermetisch)
- Produktiv-Code und Test-Code durchlaufen dieselben UI-Pfade

### URL-Override: `?forceRolle=<rolle>` (neu in v25)

Zusätzlich zu `?forceMode=demo` kann die Rolle per URL gesetzt werden:

```
/admin-dashboard-v2.html?forceMode=demo&forceRolle=projektlehrer
```

Gültige Werte: `super_admin` · `projektleitung` · `projektlehrer` · `klassenlehrer`

Nur im Demo-Modus aktiv. Im Produktiv-Modus ignoriert.

---

## Fixtures

### `tests/fixtures/app.ts`

```ts
import { test, expect, loginAs, goToSection, openAppLoggedIn, resetMockState, seedMockData } from '../fixtures/app';
```

| Funktion | Signatur | Zweck |
|---|---|---|
| `openAppLoggedIn(page)` | `(Page) → void` | Öffnet App als super_admin (Standard) |
| `loginAs(page, rolle)` | `(Page, Rolle) → void` | Öffnet App mit forceRolle-Override |
| `goToSection(page, section)` | `(Page, string) → void` | Klickt Nav-Item via data-section |
| `resetMockState(page)` | `(Page) → void` | Reloaded die Seite + neu einloggen |
| `seedMockData(page, opts)` | `(Page, opts) → void` | Befüllt Mock-Arrays per evaluate() |

**`loginAs`-Beispiel:**

```ts
test('projektlehrer sieht Mein Projekt', async ({ page }) => {
  await loginAs(page, 'projektlehrer');
  await expect(page.locator('h1').filter({ hasText: /Mein Projekt/i })).toBeVisible();
});
```

**`seedMockData`-Beispiel:**

```ts
test('leere Schüler-Liste', async ({ page }) => {
  await openAppLoggedIn(page);
  await seedMockData(page, { schueler: [] });
  await goToSection(page, 'schueler');
  // ... Empty-State testen
});
```

### `tests/fixtures/uploads/`

| Datei | Zweck |
|---|---|
| `schueler-sample.csv` | 5 Beispiel-Schüler im CSV-Format (vorname;nachname;klasse) |
| `projekt-bild-sample.png` | 1×1 Pixel PNG für Bild-Upload-Tests |

---

## Alle Spec-Files (20 Stück)

### 11 CRUD-View-Specs (Bereich `tests/e2e/`)

| Datei | Beschreibung |
|---|---|
| `view-dashboard.spec.ts` | Dashboard-Tiles, Tile-Klick navigiert |
| `view-schueler.spec.ts` | Schüler-Liste lädt, Suchfeld filtert |
| `view-anmeldungen.spec.ts` | Klassen-Tabelle lädt, Prozent-Anzeige |
| `view-verteilung.spec.ts` | Pre-Flight-Button, Guard bei leeren Schülern |
| `view-zuteilungen.spec.ts` | Liste lädt, Klassen-Filter |
| `view-tauschwuensche.spec.ts` | Liste lädt, Genehmigen-Button |
| `view-umbuchung.spec.ts` | Schüler-Suche, Umbuchungs-Bestätigung |
| `view-export.spec.ts` | CSV-Button, PDF-Button |
| `view-feedback.spec.ts` | Demo-Hinweis, Filter-Buttons |
| `view-phase.spec.ts` | Aktuelle Phase hervorgehoben, Phasenwechsel |
| `view-einstellungen.spec.ts` | Settings-Form, Speichern-Button |

### 6 Cross-Feature-Specs

| Datei | Beschreibung |
|---|---|
| `feature-feedback-button.spec.ts` | 💬-Button sichtbar, öffnet Modal |
| `feature-phase-badge.spec.ts` | Badge sichtbar, Klick → Phase-View |
| `feature-role-guard.spec.ts` | Rollen-Filter: projektleitung / projektlehrer / klassenlehrer |
| `feature-projekt-bild-upload.spec.ts` | Upload-Feld, URL-Feld, Größen-Validierung |
| `feature-pdf-export.spec.ts` | Klassenlisten-PDF, Teilnehmerlisten-PDF |
| `feature-password-recovery.spec.ts` | #type=recovery-Hash, Längen-Validierung |

### 3 Bestehende Smoke-Specs (v22.1)

| Datei | Beschreibung |
|---|---|
| `smoke-login.spec.ts` | Login-Gate, Falschpasswort, Console-Error |
| `smoke-lehrer-crud.spec.ts` | Lehrer anlegen/bearbeiten (v21/v22 Regression) |
| `smoke-projekt-crud.spec.ts` | Projekt anlegen/bearbeiten (v19/v22 Regression) |

### 3 E2E-Flow-Specs (v25)

| Datei | Beschreibung |
|---|---|
| `flow-projektlehrer-self-service.spec.ts` | Login → Mein Projekt → Edit → Titel ändern → Toast |
| `flow-projektleitung-nadine.spec.ts` | Login → Projekte → Neues Projekt → Status-Toggle |
| `flow-phase-lifecycle.spec.ts` | setup → Dashboard-Tile · anmeldung → Anmeldungen-Tab · nachbearbeitung → Tauschwünsche-Tab |

---

## Regeln für neue Tests

1. **Selektor-Strategie** (in Priorität):
   - `data-section="..."` für Nav-Items
   - `data-testid="..."` für spezifische Elemente
   - `.modal-content` für Modals
   - `getByRole` für Buttons/Headings
   - `filter({ hasText: /regex/i })` für Text-Matching
   - **Keine fragilen CSS-Pfade**

2. **Hermetik:** Kein Test darf Zustand von einem anderen Test voraussetzen.
   Bei Page-Load sind Mock-Arrays auf Default-Werte zurückgesetzt.

3. **Serielle Ausführung:** Jedes Describe-Block hat `test.describe.configure({ mode: 'serial' })`.
   `workers: 1` in `playwright.config.ts` (Mock-Arrays sind global).

4. **Fehler-Strategie:** Bei Test-Fehlschlag → Test-Erwartung anpassen.
   NICHT die App-Logik ändern. Bug in `UEBERGABE-v25.md` unter "Offene Bugs" dokumentieren.

5. **Nach jedem Edit an `admin-dashboard-v2.html`:** lokal `npm run test:e2e` laufen lassen.

---

## CI

`.github/workflows/playwright.yml` läuft bei Push auf `main` oder Pull Request.
Getriggert bei Änderungen an: `admin-dashboard-v2.html`, `tests/**`, `playwright.config.ts`, `package.json`.

Bei rotem Test: HTML-Report + Traces werden als GitHub-Artifact hochgeladen (14 Tage).

---

## Troubleshooting

**Test hängt an "Web Server failed to start"**
→ Port 4173 belegt. `lsof -i :4173` auf macOS, dann `kill <PID>`.

**Modal-Selektoren finden nichts**
→ Die App nutzt ein globales Modal-System. Selektor ist immer `.modal-content`.

**"appPage" ist undefined**
→ Fixture-Import prüfen: `from '../fixtures/app'` — NICHT `from '@playwright/test'`.

**loginAs setzt Rolle nicht**
→ `?forceMode=demo` muss im URL sein. Nur im Demo-Modus aktiv. Prüfe `KRS_MODE === 'demo'`.

**Selektoren finden die Nav-Items nicht**
→ `data-section` prüfen: Im DOM erscheinen nur erlaubte Sections (ALLOWED_SECTIONS-Filter).
   Für projektlehrer fehlen z.B. `[data-section="dashboard"]` usw. — das ist korrekt.
