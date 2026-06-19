# Übergabe v47 — Wahl-Statistik (wie oft wurde jedes Projekt gewählt)

Erstellt: 2026-06-19 · App: admin-dashboard v46→**v47**

## Problem (Norbert)
„Man sieht nicht, was die Schüler gewählt haben." Der Statistik-Tab (v46) zeigte in
Produktiv nur die **Belegung nach der Verlosung** — nicht die tatsächlichen Wünsche.
Grund: `admin_list_schueler()` liefert nur `hat_gewaehlt` (Boolean), nicht die
einzelnen Wahlen; das loadAll-Mapping reicht sie nicht durch.

## Lösung
Neue **Wahl-Statistik** im Statistik-Tab: pro Projekt, **wie oft es als Erst-/Zweit-/
Drittwahl gewählt** wurde — unabhängig von der Verlosung, sortiert nach Erstwunsch-
Beliebtheit. Funktioniert vor UND nach der Verlosung.

Datenquelle datenschutzfreundlich:
- **Produktiv:** neue read-only RPC `admin_projekt_wahl_statistik()` — gibt **nur Aggregate**
  pro Projekt zurück (keine Schüler-Codes, keine personenbezogenen Einzelwahlen).
  `SECURITY DEFINER` + `is_app_user()`-Gate wie `admin_list_schueler`.
- **Demo:** clientseitig aus `mockSchueler[*].wahlen` (3 Default-Schüler haben jetzt Demo-Wahlen).

## Geänderte/neue Dateien
- `migration-v47-wahl-statistik.sql` — **NEU**, read-only RPC (CHECK + Verifikations-Query inkl.)
- `admin-dashboard-v2.html` — Service `projektWahlStatistik()`, StatistikView-Sektion „🗳️ Wahl-Statistik", Demo-Wahlen geseedet, `KRS_VERSION = 'v47'`
- `tests/e2e/feature-v47-wahl-statistik.spec.ts` — **NEU**

## Verifikation (diese Session)
- ✅ node --check aller 4 Script-Blöcke sauber
- ✅ `tsc -p tsconfig.test.json` fehlerfrei
- ✅ `playwright test --list` erkennt den v47-Spec
- ⏳ Browser-E2E läuft im **GitHub-Actions-Gate** (Sandbox hat kein Chromium). Bei Grün Auto-Deploy.

## KRS-Fallen-Check (Self-Review)
- **normalizer-drift:** kein neues Feld über loadAll → Mapping unverändert; eigener RPC-Pfad. ✓
- **stale-closure:** useEffect mit Deps `[service, refreshKey]` + Cleanup (`alive`-Flag). ✓
- **RLS/DSGVO:** nur Aggregate, anon revoked, authenticated gated. ✓
- **SQL:** Skalar-Subqueries (kein kartesisches Produkt durch Mehrfach-Joins). ✓

## DEPLOY (auf Norberts Mac)

### 1) Migration zuerst (Supabase SQL-Editor) — nur für Produktiv-Daten nötig
Öffne `migration-v47-wahl-statistik.sql`, führe sie im SQL-Editor aus.
Danach testen: `SELECT * FROM admin_projekt_wahl_statistik() ORDER BY erstwahl DESC;`

### 2) Code pushen (ein Block)
```bash
cd "/Users/admin/Downloads/Codex playground/projekwoche app neu"
rm -f .git/index.lock
git add admin-dashboard-v2.html migration-v47-wahl-statistik.sql \
        tests/e2e/feature-v47-wahl-statistik.spec.ts \
        HANDOVER-2026-06-19-v47-wahl-statistik.md
git commit -m "v47: Wahl-Statistik (Erst-/Zweit-/Drittwahl pro Projekt), read-only RPC"
git push origin main
```
Dann **Actions** beobachten → bei Grün ist es live.
- Actions: https://github.com/kurpfalz-realschule/krs-projektwahl-2026/actions
- Live (Admin): https://kurpfalz-realschule.github.io/krs-projektwahl-2026/admin-dashboard-v2.html

Ohne Schritt 1 zeigt der neue Block live „Noch keine Wahlen abgegeben" (RPC fehlt) bzw.
fällt sauber auf leer zurück — kein Fehler, aber keine Zahlen.
