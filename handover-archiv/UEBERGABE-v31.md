# UEBERGABE v31 — KRS Projektwahl 2026
**Datum:** 2026-04-27
**Sprint:** Mega-Bundle v29 + v30/E2 (alles in EINEM Deploy)
**Status:** ✅ 89/89 Tests grün · 1 SQL-Run + 1 deploy = fertig

---

## 🚀 Was in dieser Session passiert ist — VIER Sprints in einem Rutsch

### Bundle 1 (alle drei Admin-Sprints)
- **E1.6 Erinnerungs-Trigger** in KlassenlehrerView — druckbare Liste statt Mailto (Schüler haben keine Mails)
- **E1.7 Title→ID Cleanup** in UmbuchungView/ZuteilungenView/SchuelerView + globaler `resolveProjektTitel`-Helper
- **E1.8 Security-Patch** für `update_zuteilung` UND `run_verteilung` (Caller-Guard + REVOKE FROM anon)

### Bundle 2 (E2 Schüler-Frontend Refresh)
- **`KRS_VERSION = 'v30'`** + `?forceMode=demo`-Override im Schüler-Frontend (analog Admin-Pattern)
- **Demo `createWahl` Klassenstufen-Check** — Konsistenz mit Live-RPC (kein DOM-Tampering-Bypass mehr)
- **`MeinErgebnis` + `TauschwunschFormular`** defensiv gegen depublizierte/gelöschte Projekte
- **Frontend Error-Mapping** erweitert um `klassenstufe_passt_nicht`, `projekt_unbekannt`
- **3 neue Test-Spec-Files** für Schüler-Frontend (vorher 0 Tests dort!)

---

## 📊 Test-Stand

| Spec-File | Tests | Status |
|-----------|-------|--------|
| (alle v28-Specs + flow-klassenlehrer) | 76 | ✅ |
| **flow-umbuchung-cleanup (E1.7)** | 3 | ✅ |
| **flow-erinnerung (E1.6)** | 3 | ✅ |
| **schueler-frontend-smoke (E2)** | 3 | ✅ |
| **schueler-frontend-anmeldung (E2)** | 2 | ✅ |
| **schueler-frontend-tauschwunsch (E2)** | 2 | ✅ |
| **GESAMT** | **89** | **✅** |

Lokal: `89 passed (2.2m)`

---

## 🎯 Deploy-Schritte — minimal

### EINMAL Frontend deployen
```
deploy
```
`git push origin main` → Actions → Live (https://benditot.github.io/krs-projektwahl-2026/)

### EINMAL SQL in Supabase ausführen
1. Supabase Dashboard → KRS-Projekt → SQL Editor → **+ New query**
2. Inhalt von `migration-v29-bundle.sql` (415 Zeilen) reinkopieren → **Run**
3. Erwartet: `Success. No rows returned`

### Verifikation in Supabase (3 SQL-Queries)
```sql
-- a) Funktionen vorhanden + SECURITY DEFINER?
SELECT proname, prosecdef FROM pg_proc
 WHERE proname IN ('run_verteilung', 'update_zuteilung');
-- → 2 Zeilen, prosecdef = true

-- b) anon hat KEIN EXECUTE mehr?
SELECT
  has_function_privilege('anon', 'public.run_verteilung(text, boolean, uuid)', 'EXECUTE')   AS run_anon,
  has_function_privilege('anon', 'public.update_zuteilung(text, uuid, uuid, text)', 'EXECUTE') AS upd_anon;
-- → beide false

-- c) authenticated hat EXECUTE?
SELECT
  has_function_privilege('authenticated', 'public.run_verteilung(text, boolean, uuid)', 'EXECUTE')   AS run_auth,
  has_function_privilege('authenticated', 'public.update_zuteilung(text, uuid, uuid, text)', 'EXECUTE') AS upd_auth;
-- → beide true
```

### Live-Smoke-Tests
- **Admin:** Manuelle Umbuchung als super_admin → muss durchgehen
- **Admin:** Verteilung neu starten → muss durchgehen
- **Klassenlehrer:** „Meine Klasse" → Erinnerungs-Button → Druckdialog erscheint
- **Schüler:** https://benditot.github.io/krs-projektwahl-2026/ öffnen, einen echten Code eingeben → Wahl-Flow durchspielen
- **Schüler:** Eines der zugeteilten Schüler aus Live-Daten → Tauschwunsch stellen → Projektleitung sieht ihn im Admin-Dashboard

---

## 🐛 Bekannte Lücken / Out of Scope

- **`schueler.eltern_email`-Schemafeld** — nicht in v29 gesetzt. Wenn Erinnerung später per E-Mail gewünscht ist, muss das Schema erweitert + Edge Function gebaut werden.
- **`update_zuteilung` Klassenstufen-Hardblock** — Body lehnt eine Mismatch nicht ab, flagged sie nur. Bewusst (Admin-Override). Falls hard-block gewünscht, Mini-Sprint.
- **Service-Layer-Doppel-Definition** — `krs-supabase-service.js` ist immer noch dead code im Repo (Single-File-Deploy zieht inline-Block aus den HTML-Dateien). Aufräumen ist optional.

---

## 📁 Dateien geändert/neu

| Datei | Änderung |
|-------|----------|
| `migration-v29-bundle.sql` | **NEU** — Caller-Check + REVOKE für `update_zuteilung` + `run_verteilung` |
| `admin-dashboard-v2.html` | Globale Helper `resolveProjektTitel` + `htmlEscape`, Erinnerungs-Button KlassenlehrerView, Title→ID Cleanup, `window.mockUmbuchungen` exposed |
| `schueler-frontend-v3.html` | `KRS_VERSION='v30'`, `?forceMode=demo`-Override, Demo-Klassenstufen-Check in `createWahl`, defensive `MeinErgebnis` + `TauschwunschFormular`, erweiterte Error-Map |
| `tests/e2e/flow-umbuchung-cleanup.spec.ts` | **NEU** (3 Specs E1.7) |
| `tests/e2e/flow-erinnerung.spec.ts` | **NEU** (3 Specs E1.6) |
| `tests/e2e/schueler-frontend-smoke.spec.ts` | **NEU** (3 Specs E2) |
| `tests/e2e/schueler-frontend-anmeldung.spec.ts` | **NEU** (2 Specs E2) |
| `tests/e2e/schueler-frontend-tauschwunsch.spec.ts` | **NEU** (2 Specs E2) |

---

## 🔑 Wichtige Patterns (v31 Erweiterung)

1. **`?forceMode=demo`-Param** im Schüler-Frontend (analog Admin) — schützt Production vor Test-Mutationen + erzwingt Demo bei Tests trotz vorhandenem `window.supabase`.
2. **`KRS_VERSION` Window-Marker** in beiden Frontends — Tests können Deploy-Stale erkennen.
3. **Defensive Render-Checks** für Server-Daten — wenn ein referenziertes Projekt aus der Liste verschwindet (depubliziert/gelöscht), soll das Frontend das anzeigen, nicht crashen.
4. **Demo-Pfad muss Live-Pfad spiegeln** — wenn der Live-RPC eine Validation hat, muss die Demo dasselbe machen, sonst werden Tests gegen Demo grün, aber Live bricht.

---

## 🎯 Nächster Sprint (Vorschläge)

1. **E2.1: `update_zuteilung`-Klassenstufen-Hardblock** — falls Admins nicht mehr außerhalb Range buchen sollen.
2. **E1.9: E-Mail-Versand für Erinnerung** — `schueler.eltern_email` Schema-Add + Edge Function.
3. **E3: Cleanup `krs-supabase-service.js`** — dead-code-Datei löschen, klarere Architektur-Doku.
4. **CI-Migration runner** — Supabase-Migrationen aus `/migrations/`-Ordner automatisch deployen via GitHub Actions, statt manueller SQL-Editor-Run.

**Einstiegs-Prompt für neuen Chat:**
```
Ich arbeite an der KRS Projektwahl App (admin-dashboard-v2.html + schueler-frontend-v3.html, Preact+htm Single-Files).
Mega-Bundle v29 + E2 abgeschlossen — 89 Tests grün, Migration v29 in Supabase ausgeführt, Frontend live.

Ordner: /Users/admin/Downloads/Codex playground/projekwoche app neu
Übergabe-Dokument: UEBERGABE-v31.md

Mögliche nächste Schritte: E2.1 (Klassenstufen-Hardblock), E1.9 (E-Mail-Erinnerung),
E3 (krs-supabase-service.js dead code löschen), CI-Migration-Runner.
```
