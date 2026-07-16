# Übergabe v46 — Klassenzahlen, Projekt-Statistik, Auto-Update, gewählt/zugeordnet

Erstellt: 2026-06-17 · Apps: admin-dashboard v45→**v46**, schueler-frontend v42→**v46**
Grundsatz: **keine DB-Migration, keine Datenänderung** — alles rein clientseitig aus
Daten, die `loadAll()`/`admin_list_schueler` ohnehin liefern. Projekte, Wahlen und
Zuordnungen werden **nicht** angefasst.

## Was neu ist (deine 4 Wünsche)

| # | Wunsch | Umsetzung |
|---|--------|-----------|
| 1 | Lehrer sehen Anmeldezahlen ihrer Klasse | „Meine Klasse" zeigt jetzt **„X von N gebucht · A gewählt · B zugeordnet · C offen"**. Admin/Projektleitung: „Anmelde-Status" pro Klasse mit getrennten Zahlen. |
| 2 | Wie viele interessieren sich + welche Projekte kommen gut an | Neuer Tab **📊 Statistik** (Admin/Projektleitung): Belegung je Projekt, sortiert nach Beliebtheit, gewählt vs. 📌 zugeordnet, Auslastung; nach der Verlosung zusätzlich Zuteilungs-Qualität (Erst-/Zweit-/Drittwunsch). |
| 3 | App auf neuester Version halten + Update fordern | Beide Apps prüfen automatisch (nur Live, alle 5 min + bei Tab-Rückkehr), ob online eine neuere Version liegt, und zeigen ein **Banner „Neue Version verfügbar — jetzt aktualisieren"**. Kein Auto-Reload (laufende Eingabe bleibt erhalten). |
| 4 | Zugeordnete als „gebucht" + farbliche Unterscheidung | Überall zählen vorab Zugeordnete jetzt als erledigt (löst „5a alle zugeordnet, zeigt 0 gewählt"). Farben/Legende: **grün = selbst gewählt · blau 📌 = vorab zugeordnet · gelb = offen**. Neuer Schüler-Filter „📌 nur zugeordnete". |

## Geänderte Dateien
- `admin-dashboard-v2.html` (Helfer `zaehleStatus`/`istGebuchtS`, Versionsprüfung, StatistikView, Zähler in Dashboard/Anmeldungen/Meine Klasse, Legenden, Filter, v46)
- `schueler-frontend-v3.html` (Versionsprüfung + Update-Banner, v46)
- Neue Tests: `tests/e2e/feature-v46-status-zaehler.spec.ts`, `…-statistik-view.spec.ts`, `…-update-banner.spec.ts`
- `PLAN-v46-lehrer-statistik-update.md` (Plan + Self-Review)

## Verifikation (in dieser Session)
- ✅ JS-Syntax aller Script-Blöcke (`node --check`) sauber
- ✅ Alle 130 Playwright-Specs kompilieren, 7 neue v46-Tests erkannt (`playwright test --list`)
- ✅ TypeScript-Typecheck der Tests (`tsc`) fehlerfrei
- ⏳ **Browser-E2E läuft im GitHub-Actions-Gate** (im Sandbox kein Chromium-Download/keine Persistenz möglich). Bei Grün deployt Actions automatisch; bei Rot bleibt die alte Version live.

## DEPLOY (auf deinem Mac, ein Block)
Aus dem Sandbox heraus war kein Push möglich (kein GitHub-Token + `.git` schreibgeschützt).
Im Terminal ausführen:

```bash
cd "/Users/admin/Downloads/Codex playground/projekwoche app neu"
rm -f .git/index.lock                      # stale Lock entfernen (harmlos)
git add admin-dashboard-v2.html schueler-frontend-v3.html \
        tests/e2e/feature-v46-status-zaehler.spec.ts \
        tests/e2e/feature-v46-statistik-view.spec.ts \
        tests/e2e/feature-v46-update-banner.spec.ts \
        PLAN-v46-lehrer-statistik-update.md HANDOVER-2026-06-17-v46-lehrer-statistik-update.md
git commit -m "v46: Klassen-/Projekt-Statistik, gewählt vs. zugeordnet, Auto-Update-Banner"
git push origin main
```

Danach: **Actions** beobachten → bei Grün ist es live.
- Actions: https://github.com/kurpfalz-realschule/krs-projektwahl-2026/actions
- Live (Admin): https://kurpfalz-realschule.github.io/krs-projektwahl-2026/admin-dashboard-v2.html
- Live (Schüler): https://kurpfalz-realschule.github.io/krs-projektwahl-2026/schueler-frontend-v3.html

## Optionaler Zusatz (nicht nötig zum Deploy)
„Echte" Erstwunsch-Beliebtheit **vor** der Verlosung bräuchte die Wunsch-IDs pro Schüler.
`admin_list_schueler` liefert die heute nicht. Die Statistik fängt das ab und nutzt die
Belegung/Zuordnung — die Erstwunsch-Auswertung steckt weiterhin im Verteilung-Tab (Probelauf).
Wer es im Statistik-Tab schon vor der Verlosung sehen will, könnte `admin_list_schueler` um
`erstwahl_id/zweitwahl_id/drittwahl_id` erweitern (reine read-only `CREATE OR REPLACE FUNCTION`,
kein Datenrisiko); die Statistik schaltet die Erstwunsch-Ansicht dann automatisch frei.

## Live-Gang-Hinweis (echte Schüler!)
Vor dem Verteilen von Links/Codes wie immer: kurzer Testlauf mit einem Test-Schüler und
Phase prüfen. Das Update-Banner erzwingt keinen Reload — informiert nur.
