# Sprint D — Briefing (v2, kompakt)

**Erstellt:** 2026-04-24 Abend (nach v24-Deploy) · **Überarbeitet:** 2026-04-25
**Hauptziele:**
1. **Projektlehrer-Self-Service** — Lehrer pflegen ihre eigenen Projekte selbst (entlastet Nadine massiv)
2. **Playwright-Coverage** für alle kritischen App-Funktionen
**Status:** Planung — bereit zum Start

---

## 🎯 Warum diese 2 Ziele in einem Sprint?

Beides hängt zusammen:

- Eine **neue Rolle (projektlehrer als Self-Service-User)** = neue RLS-Policies + neuer UI-Bereich + neuer Test-Pfad
- Eine **Test-Offensive ohne neuen Code** wäre die Hälfte wert — die nächste Änderung kommt sowieso (Nadine selbst hat schon Wünsche)
- Self-Service entlastet Nadine genau dort, wo Sprint C sie hingestellt hat → konsequent zu Ende denken

Konsequenz: **Tests werden gleich für die neue Rolle mitgeschrieben**, nicht später nachgezogen.

---

## 📦 Block-Struktur (statt 7 Phasen → 2 Blöcke)

| Block | Modell | Inhalt | Geschätzte Zeit |
|-------|--------|--------|-----------------|
| **A · Architektur & Logik** | Opus | Projektlehrer-Self-Service (RLS, UI, Einladungs-Flow) + 3 E2E-Flow-Specs | 4–5 h |
| **B · Routine & Coverage** | Sonnet | Test-Infra erweitern, 17 Spec-Files, CI-Gate, Doku, UEBERGABE-v25 | 4–5 h |
| **C · Optional** | Opus oder Sonnet | EditModal-Refactor (Opus) oder Custom Domain (Sonnet) | 0,5–3 h |

**Gesamt:** 8–10 h reine Arbeit, splittbar auf 2–3 Sessions.

---

## 🅰️ Block A — Opus (Architektur & Logik)

### A1 · Projektlehrer-Self-Service (Kern)
**Was Lehrer können sollen:**
- Eigene Projekte (wo `betreuer1_id = self` oder `betreuer2_id = self`) sehen
- Eigene Projekte bearbeiten (Beschreibung, Zeiten, Materialien, **Bild upload**)
- **Nicht** bearbeiten: Klassenstufen, Plätze min/max, Status, Betreuer-Zuweisung (das bleibt bei Projektleitung)
- Eigenes Projekt **neu anlegen** in der Anmeldephase (mit Status `entwurf` → muss von Nadine freigegeben werden)

**Backend:**
- `migration-v25-projektlehrer-rls.sql`:
  - `is_projektlehrer()` Helper
  - SELECT-Policy auf `projekte`: own only
  - UPDATE-Policy auf `projekte`: own only, **mit Spalten-Whitelist** (Postgres `WITH CHECK` + Trigger oder View)
  - INSERT-Policy auf `projekte`: own only, status fest auf `entwurf`
- Storage-Policies erweitern: `projektlehrer` darf eigene Bilder hochladen

**Frontend:**
- Neue Sidebar-Section "Mein Projekt" (nur sichtbar für `rolle === 'projektlehrer'`)
- `ProjektLehrerView` mit reduzierter Edit-Maske (nur erlaubte Felder)
- Login-Routing: nach Login wird die Default-Section anhand der Rolle gesetzt
- Einladungs-Flow: Norbert/Nadine kann Lehrer einladen → PASSWORD_RECOVERY funktioniert bereits aus v24

### A2 · 3 E2E-Flow-Specs
- `flow-projektlehrer-self-service.spec.ts` — Login → eigene Projekte sehen → bearbeiten → speichern
- `flow-projektleitung-nadine.spec.ts` — Nadine legt Projekt an, gibt Entwurf eines Lehrers frei
- `flow-phase-lifecycle.spec.ts` — Phase-Wechsel und resultierende UI-Änderungen

---

## 🅱️ Block B — Sonnet (Routine & Coverage)

### B1 · Test-Infrastruktur erweitern
- `tests/fixtures/app.ts`: `loginAs(rolle)` Helper, `?forceMode=demo` + `?forceRolle=projektlehrer` URL-Override
- `resetMockState()`, `seedMockData()`
- Upload-Fixtures: `tests/fixtures/uploads/schueler-sample.csv`, `projekt-bild-sample.png`

### B2 · Spec-Files (17 Stück, ~55 Tests)
**11 CRUD-View-Specs:**
schueler, dashboard, anmeldungen, verteilung, zuteilungen, tauschwuensche, umbuchung, export, feedback, phase, einstellungen

**6 Cross-Feature-Specs:**
FeedbackButton, PhaseBadge, Role-Guard (super_admin vs projektleitung vs projektlehrer), Projekt-Bild-Upload, PDF-Export-Templates, PASSWORD_RECOVERY

### B3 · CI + Doku
- `.github/workflows/playwright.yml`: Deploy-Gate
- `tests/README.md` aktualisieren
- `UEBERGABE-v25.md` schreiben

---

## 🅲 Block C — Optional (am Sprint-Ende, je nach Restzeit)

| Option | Modell | Aufwand | Wert |
|--------|--------|---------|------|
| EditModal-Refactor (eine Komponente statt 4 Duplikate) | Opus | 3 h | Hoch (Wartung) |
| Custom Domain `projektwahl.realschule-schriesheim.de` | Sonnet | 0,5 h | Niedrig (kosmetisch) |

**Empfehlung:** EditModal-Refactor lohnt sich erst, wenn Tests stehen — also wenn überhaupt, dann **am Sprint-D-Ende oder Sprint E**. Custom Domain kann zu jedem Zeitpunkt kurz dazwischengeschoben werden.

---

## ✅ Definition of Done

- [ ] Projektlehrer kann eigenes Projekt einsehen, bearbeiten, Bild hochladen
- [ ] Projektlehrer-Einladung funktioniert end-to-end (mit PASSWORD_RECOVERY aus v24)
- [ ] RLS so dicht, dass ein Projektlehrer fremde Projekte **nicht** lesen oder editieren kann (manuell + automatisch geprüft)
- [ ] 50+ Playwright-Tests grün unter 5 Min
- [ ] CI-Gate aktiv (push auf main triggert Tests, Deploy nur bei grün)
- [ ] UEBERGABE-v25.md geschrieben
- [ ] HTML-Datei manuell hochgeladen, Live-URL mit `?v=v25` geprüft

---

## ⚠️ Risiken (5)

1. **RLS-Spalten-Whitelist** — Postgres-RLS kennt keine Spalten-Granularität nativ. Lösung: View `projekte_lehrer_writable` + Trigger oder Frontend-Whitelist + RLS-Policy mit `WITH CHECK`-Constraint auf nicht-änderbare Felder.
2. **Mock-State-Leakage** in Tests — Mocks sind globale Arrays, parallele Tests verletzen sich gegenseitig. Lösung: `workers: 1, fullyParallel: false` + `resetMockState()` in `beforeEach`.
3. **File-Upload in Playwright** — `setInputFiles()` zeigt korrekt in Mock, aber Storage-Upload muss in Tests gemockt sein, sonst echte Supabase-Calls.
4. **Projekt-Status-Workflow** — Wenn Lehrer Entwurf anlegt, muss Nadine sehen "X neue Entwürfe". Brauchen wir eine Notification? Sprint-D-Scope: Nein, Badge in Sidebar reicht.
5. **Norbert ist gleichzeitig super_admin und Projektlehrer (für sein eigenes Projekt)** — Rolle ist ein einzelnes Feld. Lösung: super_admin sieht ALLES inklusive "Mein Projekt"-Section (bequem) — also ein Sektions-Visibility-Flag, nicht ein Rollen-Switch.

---

## ❓ Offene Entscheidungen (vor Sprint-Start)

1. **Spalten-Whitelist via Trigger oder via View?**
   - Empfehlung: **Trigger** — sauberer, keine zusätzliche View, Audit-fähig.

2. **Wie kommen Lehrer an ihren Login?**
   - Option a: Nadine/Norbert lädt manuell ein (Supabase-Auth-Invite, wie Nadine selbst)
   - Option b: Bulk-Invite-Button im Lehrer-Tab — sendet allen `projektlehrer` mit gültiger E-Mail eine Einladung
   - Empfehlung: **a** zum Start, **b** als Quick-Win in Block B (Sonnet)

3. **EditModal-Refactor jetzt oder Sprint E?**
   - Empfehlung: **Sprint E** — Sprint D ist eh schon voll, Refactor profitiert von dann fertigem Test-Net.

4. **Custom Domain Sprint D oder separat?**
   - Empfehlung: **Separat** — 30 Minuten irgendwann zwischendurch, lenkt nicht von Test-Coverage ab.

---

## 🚀 Einstiegs-Prompt für Sprint-D-Start

```
Sprint D startet. Ich bin in /Users/admin/Downloads/Codex playground/projekwoche app neu/.
Briefing: SPRINT-D-BRIEFING.md (v2 kompakt).
Beginne mit Block A (Opus): Projektlehrer-Self-Service.
1. migration-v25-projektlehrer-rls.sql schreiben (idempotent)
2. ProjektLehrerView in admin-dashboard-v2.html ergänzen
3. Login-Routing auf Rolle anpassen
Erst Block A komplett, dann Block B in einer separaten Sonnet-Session.
```

---

**Bereit?** Sag mir noch zu den 4 offenen Entscheidungen kurz Ja/Nein zu meinen Empfehlungen, dann lege ich Tasks an und starte Block A.
