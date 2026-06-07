# Sprint D-2 (= Block B) — Sonnet-Aufgabenliste

**Modell:** Sonnet (Routine, kein Architektur-Denken)
**Vorgänger:** Sprint D Block A (Opus) — Projektlehrer-Self-Service ist live (v25.1)
**Geschätzter Aufwand:** 4–5 Stunden, 1 Session
**Working directory:** `/Users/admin/Downloads/Codex playground/projekwoche app neu/`
**Hauptdatei:** `admin-dashboard-v2.html` (~9700 Zeilen, NICHT umstrukturieren)
**Ziel:** Bestehende Funktionen mit Tests absichern, KEINE neuen Features.

---

## ✅ Definition of Done (Akzeptanz-Kriterien)

- [ ] `npm run test:e2e` läuft alle Tests grün durch unter 5 Min
- [ ] `loginAs(rolle)`-Helper funktioniert für 4 Rollen (super_admin, projektleitung, projektlehrer, klassenlehrer)
- [ ] `?forceRolle=<rolle>`-URL-Override aktiviert
- [ ] 17 Spec-Files vorhanden, jeder mit mind. 2 Tests
- [ ] 3 E2E-Flow-Specs laufen
- [ ] CI-Gate-Workflow `.github/workflows/playwright.yml` aktiv
- [ ] `tests/README.md` aktualisiert
- [ ] `UEBERGABE-v25.md` final geschrieben

---

## 📦 B1 — Test-Infrastruktur erweitern

### B1.1 — `tests/fixtures/app.ts` erweitern

**Bestand prüfen:** Diese Datei existiert seit v22.1. Erweitern, nicht überschreiben.

Neue Helper:

| Helper | Signatur | Zweck |
|--------|----------|-------|
| `loginAs(page, rolle)` | `(page: Page, rolle: 'super_admin'\|'projektleitung'\|'projektlehrer'\|'klassenlehrer')` | Setzt URL-Override `?forceMode=demo&forceRolle=<rolle>`, navigiert zur App, klickt Demo-Login |
| `resetMockState(page)` | `(page: Page)` | Re-loaded die Seite, setzt `window.MOCK_*`-Arrays auf Initial-Werte zurück |
| `seedMockData(page, options)` | `(page: Page, opts: { projekte?, lehrer?, schueler? })` | Befüllt Mock-Arrays per `page.evaluate()` |
| `appPage` Fixture | (existing) | Erweitern um automatisches Reset zwischen Tests |

**URL-Override `?forceRolle=…`** ist bereits in v25.1 eingebaut (siehe `App()`-useEffect, Zeile ~6439):
- Akzeptierte Werte: `super_admin`, `projektleitung`, `projektlehrer`, `klassenlehrer`
- Funktioniert nur im Demo-Modus (sicherheitsgeprüft)
- Setzt `currentUserRolle` + Default-Section (projektlehrer → 'mein-projekt', klassenlehrer → 'anmeldungen', sonst 'dashboard')
- Globaler Hook: `window.__KRS_FORCED_ROLLE` (für Test-Assertions verfügbar)
- Test-URL-Format: `http://localhost:4173/admin-dashboard-v2.html?forceMode=demo&forceRolle=projektlehrer`

### B1.2 — Test-Fixtures-Ordner

```
tests/fixtures/uploads/
├── schueler-sample.csv      # 5 Beispiel-Schüler im erwarteten CSV-Format
└── projekt-bild-sample.png  # kleines PNG (~10 KB) für Bild-Upload-Test
```

CSV-Format bitte aus `admin-dashboard-v2.html` ablesen (Suche: „CSV-Import Info-Button" / Format-Modal aus v23 Task #7).

---

## 📦 B2 — Spec-Files (17 Stück, ~55 Tests)

**Speicherort:** `tests/e2e/`

**Konvention:**
- Datei-Name: `<view-oder-feature>.spec.ts`
- Mind. 2 Tests pro File: ein „happy path" + ein Edge-Case
- Selektoren über `[data-section="..."]` / `[data-testid="..."]` — KEINE Text-Selektoren (siehe Memory-Hinweis aus v22.1)
- Falls ein Selector fehlt: in `admin-dashboard-v2.html` ein `data-testid` ergänzen (kleine Edits OK, KEINE Logik-Änderung)
- Alle Tests nutzen `?forceMode=demo`

### 11 CRUD-View-Specs

Jeder Test: `loginAs(page, 'super_admin')` → navigate zur View → Action → Assert.

| Datei | Mindest-Tests |
|-------|---------------|
| `view-schueler.spec.ts` | (1) Liste lädt mit ≥1 Schüler · (2) Suchfeld filtert |
| `view-dashboard.spec.ts` | (1) Tiles zeigen die Counts (Schüler, Projekte, Lehrer) · (2) Tile-Klick navigiert |
| `view-anmeldungen.spec.ts` | (1) Klassen-Tabelle lädt · (2) Prozent-Anzeige stimmt mit gewählten Schülern überein |
| `view-verteilung.spec.ts` | (1) „Neue Verteilung"-Button öffnet Modal · (2) Pre-Flight-Guard wirft bei 0 Schülern Fehler |
| `view-zuteilungen.spec.ts` | (1) Zuteilungs-Liste lädt · (2) Filter nach Klasse funktioniert |
| `view-tauschwuensche.spec.ts` | (1) Liste lädt · (2) Genehmigen-Button updated Status |
| `view-umbuchung.spec.ts` | (1) Schüler-Suche findet Schüler · (2) Umbuchung-Bestätigung erscheint |
| `view-export.spec.ts` | (1) CSV-Klassenlisten-Button löst Download aus · (2) PDF-Klassenlisten-Button löst Download aus |
| `view-feedback.spec.ts` | (1) Liste lädt mit gerenderten Sterne-Bewertungen · (2) Mark-as-done updated UI |
| `view-phase.spec.ts` | (1) Aktuelle Phase ist hervorgehoben · (2) Phasenwechsel-Button schaltet um |
| `view-einstellungen.spec.ts` | (1) Settings-Form lädt · (2) Save-Button speichert (im Demo-Modus stub) |

### 6 Cross-Feature-Specs

| Datei | Mindest-Tests |
|-------|---------------|
| `feature-feedback-button.spec.ts` | (1) Globaler 💬-Button öffnet Modal · (2) Sterne+Text → Submit funktioniert |
| `feature-phase-badge.spec.ts` | (1) Badge sichtbar in main-Bereich · (2) Klick navigiert zu Phase-View |
| `feature-role-guard.spec.ts` | (1) projektleitung sieht 6 Tabs (kein lehrer/schueler/etc) · (2) projektlehrer sieht NUR „Mein Projekt" · (3) klassenlehrer sieht dashboard+anmeldungen |
| `feature-projekt-bild-upload.spec.ts` | (1) Upload setzt Thumbnail · (2) Delete entfernt Thumbnail · (3) Größenlimit (>5MB) wirft Toast |
| `feature-pdf-export.spec.ts` | (1) Klassenlisten-PDF wird generiert · (2) Teilnehmerlisten-PDF wird generiert (download-event triggert) |
| `feature-password-recovery.spec.ts` | (1) URL mit `#type=recovery` zeigt Passwort-Modal · (2) zu kurzes Passwort wirft Fehler |

### 3 E2E-Flow-Specs

| Datei | Was getestet wird |
|-------|-------------------|
| `flow-projektlehrer-self-service.spec.ts` | `loginAs('projektlehrer')` → „Mein Projekt" lädt → Karte klicken → Edit-Modal → titel ändern → Save → Toast „aktualisiert!" → Karte zeigt neuen Titel |
| `flow-projektleitung-nadine.spec.ts` | `loginAs('projektleitung')` → Projekte → „➕ Neues Projekt" → speichern → Status-Toggle klicken → status=veroeffentlicht → Bulk-Veröffentlichen-Button-Test |
| `flow-phase-lifecycle.spec.ts` | super_admin → Phase auf „setup" → Dashboard zeigt Setup-Tile · Phase auf „anmeldung" → Anmeldungen-Badge · Phase auf „nachbearbeitung" → Tauschwünsche-Tab sichtbar |

---

## 📦 B3 — CI + Doku

### B3.1 — `.github/workflows/playwright.yml`

**Bestand prüfen:** Existiert seit v22.1 mit 3 Smoke-Tests.

Erweitern:
- `runs-on: ubuntu-latest`
- Triggert auf `pull_request` und `push: branches: [main]`
- Workers: 1, fullyParallel: false (Mock-Arrays sind global)
- Artifacts: failed traces für 14 Tage
- **Deploy-Gate:** Falls dein Deploy-Workflow existiert (vermutlich nicht) → branch protection rule würde Tests als Voraussetzung anforden, aber das macht Norbert manuell in GitHub-Settings

### B3.2 — `tests/README.md`

Update mit:
- Liste aller 17 + 3 = 20 Spec-Files mit Kurz-Beschreibung
- `loginAs(rolle)`-Beispiel
- Wie Mock-Daten geseedet werden
- Hinweis: nach jedem Edit an `admin-dashboard-v2.html` lokal `npm run test:e2e` laufen lassen

### B3.3 — `UEBERGABE-v25.md` (final)

Sprint-D-Komplett-Übergabe schreiben:
- Was Block A geliefert hat (kopiere aus `UEBERGABE-v25-block-a.md`)
- Was Block B geliefert hat (Tests)
- Was offen bleibt (Sprint E — siehe `UEBERGABE-sprint-e.md`)
- Smoke-Test-Checkliste für nächsten Deploy
- Einstiegs-Prompt für Sprint E

---

## ⚠️ Wichtige Regeln

1. **Keine Logik-Änderungen** in `admin-dashboard-v2.html` außer:
   - `data-testid`-Attribute ergänzen, falls für Tests nötig
   - URL-Override `?forceRolle=...` einbauen (B1.1)
2. **Tests müssen alle grün laufen** bevor du fertig bist
3. **Realistische Mock-Daten** verwenden (mockLehrerData, mockSchueler, mockProjekteData haben bereits sinnvolle Inhalte)
4. **Memory-Pattern beachten** (aus Sprint A-D Lessons):
   - `data-section` > Text-Selektoren
   - `?forceMode=demo` zwingt Demo-Modus auch im Produktiv-Build
   - `workers: 1, fullyParallel: false` weil Mocks global sind
5. **Bei jedem Test-File:** `test.describe.configure({ mode: 'serial' })` — Tests innerhalb einer Datei laufen sequenziell

---

## 📝 Wenn ein Test fehlschlägt

Sonnet-Regel: **NICHT die Logik der App ändern, um den Test grün zu kriegen.** Stattdessen:
1. Test-Erwartung an realen Code anpassen, oder
2. Bug dokumentieren in `UEBERGABE-v25.md` unter „Offene Bugs aus Sprint-D-2", für Opus-Behandlung in Sprint E

---

## 🧭 Wenn fertig

1. Tests lokal grün: `npm run test:e2e`
2. `tests/README.md` und `UEBERGABE-v25.md` reviewen
3. `git commit` (oder Drag&Drop-Upload, je nach Setup)
4. Memory-Update: `project_krs_projektwahl_2026.md` → „v25 Sprint D KOMPLETT"
5. Norbert pingen mit Status: „Sprint D-2 fertig. Tests grün. UEBERGABE-v25.md ist final."
