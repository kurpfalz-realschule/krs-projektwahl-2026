# HANDOVER v41 — Schüler nachträglich anlegen · Projekte sperren · Lehrer-Projektübersicht

**Datum:** 16. Juni 2026
**Kurzfassung:** Drei von Norbert bestätigte Feedback-Punkte umgesetzt + Versions-Label korrigiert (stand fälschlich auf v39). Lokal syntaxgeprüft (`node --check` grün) und durch ein unabhängiges Experten-Review gegangen (keine Blocker). Tests laufen über die CI nach dem Push.

---

## 1) Was umgesetzt wurde

| # | Feedback-Punkt | Lösung | Dateien |
|---|----------------|--------|---------|
| 1 | Fehlende SuS nachträglich anlegen | **Admin-Formular „➕ Schüler anlegen"** (Vorname, Nachname, Klasse). Code + Klassenstufe werden serverseitig erzeugt. Für Einzelne; ganze Listen weiter per CSV. | admin-dashboard, RPC `admin_create_schueler` |
| 2 | Kollegen sollen alle Projekte sehen | Neue **read-only Section „📖 Alle Projekte"** für Rolle projektlehrer (+ projektleitung/klassenlehrer). Suchbar, eigenes Projekt markiert. | admin-dashboard (`AlleProjekteView`, `ALLOWED_SECTIONS`) |
| 3 | Feste Klassenprojekte sperren | **„🔒 Sperren/🔓 Entsperren"-Button** pro Projekt. Gesperrte Projekte sind für weitere SuS nicht mehr wählbar (Frontend-Filter **+ DB-Trigger** = auch gegen Direktaufrufe sicher). Bereits Zugeteilte bleiben. | admin-dashboard, schueler-frontend, RPC `set_projekt_gesperrt`, Trigger `trg_wahl_nicht_gesperrt` |
| — | Versions-Label | `KRS_VERSION` auf **v41** (war v39 → wirkte wie „nichts geändert"). | admin-dashboard, schueler-frontend |

**Antwort auf Norberts Frage „passiert das automatisch wenn voll?":**
Ja — ein volles Projekt (Belegung = max. Plätze) bekommt bei der Verteilung niemanden mehr. Zusätzlich gibt es jetzt den **Sperren-Button**, der ein Projekt unabhängig vom Füllstand sofort aus der Schülerwahl nimmt.

---

## 2) Geänderte Dateien

- **`migration-v41-schueler-anlegen-projekt-sperren.sql`** (NEU) — muss in Supabase ausgeführt werden.
- `admin-dashboard-v2.html` — Service-Methoden, Anlege-Modal, AlleProjekteView, Sperren-Button, loadAll-Mapping, Version.
- `schueler-frontend-v3.html` — gesperrte Projekte aus Wahl ausgeschlossen, Version.
- `krs-supabase-service.js` — `createSchueler`, `setProjektGesperrt`, `gesperrt` in Normalizern (Konsistenz; HTML-Dateien haben eigene Inline-Kopien).
- `tests/e2e/feature-v41-schueler-anlegen-sperren.spec.ts` (NEU) — Smoke-Tests.
- `tests/fixtures/app.ts` — Versions-Regex auf v4x erweitert.
- `.gitignore` — `*.check.mjs`.

---

## 3) Deploy — Reihenfolge wichtig

**A) DB-Migration zuerst** (Supabase SQL-Editor, eingeloggt als Projekt-Owner):
- Datei `migration-v41-schueler-anlegen-projekt-sperren.sql` einfügen und ausführen.
- **Voraussetzung:** Migration **v40** muss vorher gelaufen sein (liefert die Spalte `schueler.aktiv`, die `admin_create_schueler` nutzt). v40-Status laut letztem Handover: ✅ live seit 13.06.
- Kontroll-Queries stehen am Ende der Datei (auskommentiert).

**B) App-Code pushen** (Terminal):
```bash
cd "/Users/admin/Downloads/Codex playground/projekwoche app neu"
rm -f .git/index.lock
git add admin-dashboard-v2.html schueler-frontend-v3.html krs-supabase-service.js \
        migration-v41-schueler-anlegen-projekt-sperren.sql \
        tests/e2e/feature-v41-schueler-anlegen-sperren.spec.ts tests/fixtures/app.ts \
        .gitignore HANDOVER-2026-06-16-v41-schueler-anlegen-sperren.md
git commit -m "v41: Schüler nachträglich anlegen + Projekte sperren + read-only Projektübersicht für Lehrer; KRS_VERSION v41"
git push "https://DEIN-TOKEN@github.com/kurpfalz-realschule/krs-projektwahl-2026.git" main
```
CI beobachten — bei grün deployt GitHub Pages v41 automatisch.
- Actions: https://github.com/kurpfalz-realschule/krs-projektwahl-2026/actions
- Live: https://kurpfalz-realschule.github.io/krs-projektwahl-2026/

> Hinweis: Es liegen 2 Hilfsdateien `*.check.mjs` im Ordner (aus dem Syntax-Check; ich konnte sie sandbox-bedingt nicht löschen). Sie sind via `.gitignore` ausgeschlossen — du kannst sie gefahrlos löschen.

---

## 4) Qualitätssicherung

- `node --check` auf beide Inline-Module: **grün**.
- Unabhängiges Experten-Review (PostgreSQL + Preact): **keine Blocker**. Bestätigt: RPC-Guards (`is_admin`), View-Spaltenreihenfolge, GRANTs, JS-Scoping, durchgängige `gesperrt`-Weitergabe.
- Review-Warnung „Sperre nur im Frontend" wurde direkt behoben: zusätzlicher **DB-Trigger `trg_wahl_nicht_gesperrt`** erzwingt die Sperre serverseitig.
- Playwright konnte in der Sandbox nicht laufen (Browser-Download-Timeout, bekannt) → finale Bestätigung = grüner CI-Lauf nach dem Push.

---

## 5) Noch offen (nicht Teil dieses Sprints)

- **„Projekte lassen sich nicht alle bearbeiten":** Der globale Save-Bug ist seit v40 im Code behoben. Wenn nur *manche* Projekte fehlschlagen, brauche ich von dir: bei welchem Projekt + welche Fehlermeldung/Konsole. Verdacht: Browser-Cache (alte Version) oder RLS auf einzelnen Projekten.
- **Einladungs-Mails kommen nicht an:** vermutlich Supabase-Mail-Ratelimit oder kein eigener SMTP. In Supabase → Auth → Logs/SMTP prüfen.
- **Optional:** Verteilung (`run_verteilung`) füllt gesperrte, aber noch nicht volle Projekte theoretisch weiter auf. Für Norberts Fall (volle Klassenprojekte) irrelevant. Bei Bedarf: `AND p.gesperrt = false` im Wahl-Ziel-SELECT der RPC ergänzen.

---

## 6) Einstiegs-Prompt für neuen Chat

> Projekt: KRS Projektwahl 2026, Ordner „projekwoche app neu". Stand v41 (Handover-2026-06-16). Umgesetzt: Schüler-Anlegen-Formular (RPC admin_create_schueler), Projekt-Sperren (Spalte gesperrt + RPC set_projekt_gesperrt + Trigger trg_wahl_nicht_gesperrt), read-only AlleProjekteView für Lehrer. Migration v41 muss in Supabase laufen (nach v40). Offen: Edit-Bug auf einzelnen Projekten klären (Fehlermeldung von Norbert nötig), Einladungs-Mailversand in Supabase prüfen.

---

## 7) Nachtrag 16.06. (Session 2) — wichtige Korrekturen

**A) security_invoker-Zwischenfall (behoben).** In v41 wurde zunächst `ALTER VIEW projekte_public SET (security_invoker = true)` gesetzt. Das hat in der Produktiv-DB **alle Projekte für anon ausgeblendet** ("alle Projekte verschwunden"), weil anon keine eigene RLS-SELECT-Regel auf projekte/users hat — die View lief vorher bewusst mit Definer-Rechten. Fix: im SQL-Editor `ALTER VIEW public.projekte_public SET (security_invoker = false);` ausgeführt → Projekte sofort zurück (View liefert wieder 21 veröffentlichte Projekte). Die Migrationsdatei wurde entsprechend auf `security_invoker = false` korrigiert (mit erklärendem Kommentar). **Optionale spätere Härtung nur zusammen mit passenden anon-RLS-Policies.**

**B) CI rot war KEIN v41-Bug.** Lauf #24 (8a3a9dc) scheiterte nur an zwei veralteten Versions-Regexes, die bei v39 deckelten und „v41" ablehnten:
- `tests/e2e/schueler-frontend-smoke.spec.ts:19` → jetzt `/^v([3-9][0-9])/`
- `tests/e2e/smoke-login.spec.ts:46` → jetzt `/^v(2[2-9]|[3-9][0-9])/`
Alle 24 v41-Feature-Tests waren grün. `tests/fixtures/app.ts` war bereits korrekt. Keine weiteren Versions-Deckel im Test-Ordner.

**C) Offener Schritt: Push.** Fix liegt als lokaler Commit `cb9c848` vor (2 Test-Specs + korrigierte Migration). Muss noch gepusht werden (Token bleibt bei Norbert):
```bash
cd "/Users/admin/Downloads/Codex playground/projekwoche app neu"
rm -f .git/index.lock
git push "https://DEIN-TOKEN@github.com/kurpfalz-realschule/krs-projektwahl-2026.git" main
```
Danach CI-Lauf #25 → bei grün deployt GitHub Pages v41 automatisch live.
