# Sprint OPUS — krs-projektwahl: Leck-C-Security (Code-Rotation vor Projektwoche)

Erstellt: 2026-07-12 von Fable (Orchestrator). Selbsterklärend — keine Chat-Historie nötig.

## Kontext

- **App:** KRS Projektwahl 2026 (Kurpfalz-Realschule Schriesheim). Single-File-Apps
  `admin-dashboard-v2.html` (Lehrkräfte/Admin) + `schueler-frontend-v3.html` (Schüler-Login
  per Zugangscode, KEIN Account). Repo: dieser Ordner (`krs-pw-deploy`), GitHub Pages,
  E2E-Gate via GitHub Actions.
- **Supabase-Projekt (eigenes, NICHT das Hub-Projekt):** `uzynvvtsyjfmtywsfxtz`
  (siehe `krs-supabase-config.js`). Publishable Key im Frontend, Schutz = RLS.
- **Stand:** v48 (siehe `HANDOVER-2026-07-02-v48-wuensche-popover.md`). RLS-Lockdown v35
  aktiv (`migration-v35-rls-lockdown.sql`), Schülerzugriff nur via
  `get_schueler_status(code)` SECURITY DEFINER, Admin-Listen via `is_app_user()`-Gate.
- **Anlass:** „Leck C" aus dem Security-Sprint. ⚠️ **WICHTIGE LÜCKE:** Der Detailplan
  `07-SECURITY-SPRINT-DETAILPLAN` liegt NICHT auf dem MacBook (vermutlich Mac Mini).
  Was „Leck C" genau ist, ist hier NIRGENDS definiert. Norberts Entscheidung (12.07.):
  trotzdem arbeiten, Lücke explizit behandeln — **DB selbst auditieren statt raten.**
- **Norberts Antwort:** Projektwoche 2026 **läuft noch / steht bevor** → Maßnahme ist
  **Code-Rotation + neue Serienbriefe** (nicht Deaktivierung). Zeitdruck: Sommerferien
  BW ~Ende Juli; Serienbrief-Druck braucht 1–2 Werktage Puffer.

## Ziel / Fertig wenn

Leck C ist durch eigenes DB-Audit identifiziert (oder als „nicht reproduzierbar"
dokumentiert), ein sicherer Rotations-Plan mit fertigem SQL liegt vor, und die
Übergabe an den Sonnet-Sprint (Serienbriefe + Testlauf) ist geschrieben.

## Betroffene Dateien/Pfade

- DB: Supabase `uzynvvtsyjfmtywsfxtz` — Tabellen `schueler` (PK `code` TEXT!),
  `wahlen`, `zuteilungen`, `tauschwuensche` (alle FK auf `schueler(code)`)
- `schema-v2-fixed.sql`, `migration-v35-rls-lockdown.sql`, `migration-v40-schueler-inaktiv.sql`
- Neu anzulegen: `migration-v49-code-rotation.sql`
- `SECURITY.md` (bei neuen Erkenntnissen ergänzen)

## Aufgaben

### 1. Leck-C-Audit (Skills: `sicherheitscheck`, `dsgvo-rls-pii-lockdown`, `supabase-rls-haertung`)
Per Supabase-MCP (read-only!) prüfen:
- [ ] Alle RLS-Policies auf `schueler`, `wahlen`, `zuteilungen`, `tauschwuensche`,
  `users`: existiert irgendwo noch `TO anon USING (true)` auf PII?
- [ ] `get_advisors` (security) laufen lassen.
- [ ] Sind Zugangscodes irgendwo massenhaft lesbar (Views! `schema-v2-fixed.sql`
  Zeilen ~270–350 definieren Views mit `schueler_code` — sind die anon-lesbar)?
- [ ] Git-Repo: keine echten Codes/Namen committet (CSV-Templates, Test-Fixtures)?
- [ ] Befund als „Leck C = <Befund>" dokumentieren. Wenn nichts gefunden:
  ehrlich schreiben „kein Leck reproduzierbar, Detailplan vom Mini nötig" — NICHT erfinden.
- **Akzeptanz:** Jede Policy/View namentlich gelistet mit Bewertung ✓/⚠️.

### 2. Phasen-Check VOR Rotationsentscheidung
- [ ] Aktuelle Phase/Settings aus DB lesen (anmeldung_offen o. Ä., `migration-v37-termine-seed.sql`).
- [ ] Zählen: Wie viele Schüler haben bereits gewählt (`wahlen`)? Wie viele Zuteilungen?
- **Akzeptanz:** Klare Aussage, ob Rotation Wahlen/Zuteilungen berühren würde.

### 3. Rotations-SQL schreiben (Skill: `sichere-massen-sql-migration`)
⚠️ **Falle:** `schueler.code` ist PRIMARY KEY; `wahlen`/`zuteilungen`/`tauschwuensche`
referenzieren ihn per FK (`ON DELETE CASCADE` — ob `ON UPDATE CASCADE` gesetzt ist,
in der DB verifizieren, nicht annehmen!). Naives `UPDATE schueler SET code=…` kann
FKs brechen oder Wahlen verwaisen.
- [ ] `migration-v49-code-rotation.sql` nach KRS-Muster: **CHECK-Query (zählen) →
  AKTION → UNDO-Snippet**, idempotent, nicht-destruktiv. Mapping-Tabelle
  `code_rotation_log` (alt→neu, timestamp) für die Serienbriefe und als Undo-Basis.
- [ ] Neue Codes: gleiches Format wie bisher (Frontend validiert `UPPER(TRIM(...))`),
  kryptografisch zufällig, kollisionfrei.
- [ ] **NICHT AUSFÜHREN.** CHECK-Query-Ergebnis Norbert zeigen, erst nach seinem OK
  die AKTION laufen lassen (so hat er es angeordnet).
- **Akzeptanz:** SQL-Datei liegt im Repo, CHECK/AKTION/UNDO getrennt markiert,
  FK-Verhalten verifiziert und im Kommentar belegt.

### 4. DSGVO-Notiz für DSB-Gespräch (Skill: `dsgvo-schul-webapp-bw`)
- [ ] 1-Seiter `DSGVO-NOTIZ-DSB-projektwahl.md` in diesem Ordner: Was ist passiert
  (Leck-C-Befund aus Aufgabe 1, ehrlich inkl. „Detailplan lag auf anderem Rechner"),
  betroffene Datenkategorien (Codes = pseudonym, aber Schülernamen in DB!),
  Bewertung Meldepflicht Art. 33 (Einschätzung, kein Rechtsrat), ergriffene
  Maßnahmen (Rotation, RLS-Stand v35), offene Punkte. Sachlich, Sie-Form-tauglich.
- **Akzeptanz:** Passt auf 1 Seite, keine erfundenen Fakten, Unsicherheiten markiert.

## Scope-Grenze

**Mach NUR diese Aufgaben.** Serienbriefe, QR-Codes, Testlauf-Protokoll und Deploy
gehören dem Sonnet-Sprint (`sprint sonnet krs-projektwahl.md`) — nicht anfassen.
Nichts Zusätzliches „verbessern" (kein Refactoring, keine neuen Features, keine
UI-Änderungen). Rotation NICHT ohne Norberts explizites OK ausführen.

## Abschlusspflicht

Am Ende: `sprint sonnet krs-projektwahl.md` aktualisieren (Abschnitt „Input von
Opus": Leck-C-Befund, Rotations-Status, Mapping-Tabellenname) UND kanonische
`HANDOVER.md` dieses Ordners aktualisieren (keine neue v-Datei). Session-Abschluss
nach Norberts Standard: klickbare Links, max. 1 Terminal-Befehl, Abschnitt
„Was Norbert jetzt tut" mit genau EINER Handlung.
